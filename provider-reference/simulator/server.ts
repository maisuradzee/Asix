/**
 * Local-only mock operator wallet for ASIX partner-adapter development.
 *
 * NOT a production wallet and NOT connected to ASIX production.
 * Run with: deno run --allow-net=127.0.0.1:8787 provider-reference/simulator/server.ts
 */

type Operation = "BET" | "WIN" | "REFUND";
type TxState = "PENDING" | "CONFIRMED" | "DECLINED";

interface WalletRequest {
  transactionRef: string;
  playerRef: string;
  amountMinor: number;
  currency: string;
  sessionRef: string;
  roundRef: string;
  originalTransactionRef?: string;
}

interface StoredTransaction {
  transactionRef: string;
  idempotencyKey: string;
  payloadHash: string;
  operation: Operation;
  playerRef: string;
  amountMinor: number;
  currency: string;
  sessionRef: string;
  roundRef: string;
  originalTransactionRef?: string;
  refundedMinor: number;
  state: TxState;
  faultMode: string;
  responseCode: string;
  responseAt: string;
}

export interface MockPartnerOptions {
  initialBalanceMinor?: number;
}

export interface MockPartner {
  handler(request: Request): Promise<Response>;
  getBalance(playerRef: string, currency: string): number;
  transactionCount(): number;
}

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });

async function sha256(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function validText(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0 && value.length <= 200;
}

export function createMockPartner(options: MockPartnerOptions = {}): MockPartner {
  const initialBalance = options.initialBalanceMinor ?? 100_000;
  if (!Number.isSafeInteger(initialBalance) || initialBalance < 0) {
    throw new Error("INVALID_INITIAL_BALANCE");
  }

  const byIdempotency = new Map<string, StoredTransaction>();
  const byReference = new Map<string, StoredTransaction>();
  const balances = new Map<string, number>();

  const balanceKey = (playerRef: string, currency: string) => `${playerRef}:${currency}`;
  const getBalance = (playerRef: string, currency: string): number => {
    const key = balanceKey(playerRef, currency);
    if (!balances.has(key)) balances.set(key, initialBalance);
    return balances.get(key)!;
  };

  const responseFor = (tx: StoredTransaction) => ({
    transactionRef: tx.transactionRef,
    state: tx.state,
    operation: tx.operation,
    amountMinor: tx.amountMinor,
    currency: tx.currency,
    playerRef: tx.playerRef,
    availableBalanceMinor: getBalance(tx.playerRef, tx.currency),
    responseCode: tx.responseCode,
    responseAt: tx.responseAt,
  });

  const applyEffect = (tx: StoredTransaction): void => {
    const key = balanceKey(tx.playerRef, tx.currency);
    const current = getBalance(tx.playerRef, tx.currency);

    if (tx.operation === "BET") {
      if (current < tx.amountMinor) {
        tx.state = "DECLINED";
        tx.responseCode = "INSUFFICIENT_BALANCE";
        tx.responseAt = new Date().toISOString();
        return;
      }
      balances.set(key, current - tx.amountMinor);
    } else if (tx.operation === "WIN") {
      const next = current + tx.amountMinor;
      if (!Number.isSafeInteger(next)) {
        tx.state = "DECLINED";
        tx.responseCode = "BALANCE_LIMIT";
        tx.responseAt = new Date().toISOString();
        return;
      }
      balances.set(key, next);
    } else {
      const original = tx.originalTransactionRef
        ? byReference.get(tx.originalTransactionRef)
        : undefined;
      if (!original || original.operation !== "BET" || original.state !== "CONFIRMED" ||
          original.playerRef !== tx.playerRef || original.currency !== tx.currency) {
        tx.state = "DECLINED";
        tx.responseCode = "ORIGINAL_BET_NOT_FOUND";
        tx.responseAt = new Date().toISOString();
        return;
      }
      if (original.refundedMinor + tx.amountMinor > original.amountMinor) {
        tx.state = "DECLINED";
        tx.responseCode = "REFUND_EXCEEDS_ORIGINAL_BET";
        tx.responseAt = new Date().toISOString();
        return;
      }
      const next = current + tx.amountMinor;
      if (!Number.isSafeInteger(next)) {
        tx.state = "DECLINED";
        tx.responseCode = "BALANCE_LIMIT";
        tx.responseAt = new Date().toISOString();
        return;
      }
      original.refundedMinor += tx.amountMinor;
      balances.set(key, next);
    }

    tx.state = "CONFIRMED";
    tx.responseCode = "OK";
    tx.responseAt = new Date().toISOString();
  };

  async function handler(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true, service: "asix-mock-operator-wallet", mode: "local-simulator" });
    }

    if (request.method === "GET" && url.pathname.startsWith("/wallet/transactions/")) {
      const transactionRef = decodeURIComponent(url.pathname.split("/").pop() || "");
      const tx = byReference.get(transactionRef);
      if (!tx) return json({ ok: false, error: "TRANSACTION_NOT_FOUND" }, 404);

      if (tx.state === "PENDING" && tx.faultMode === "pending_then_confirm") {
        applyEffect(tx);
      }
      return json({ ok: true, transaction: responseFor(tx) });
    }

    const routeToOperation: Record<string, Operation> = {
      "/wallet/bet": "BET",
      "/wallet/win": "WIN",
      "/wallet/refund": "REFUND",
    };
    const operation = request.method === "POST" ? routeToOperation[url.pathname] : undefined;
    if (!operation) return json({ ok: false, error: "NOT_FOUND" }, 404);

    const idempotencyKey = request.headers.get("idempotency-key") || "";
    if (!validText(idempotencyKey)) {
      return json({ ok: false, error: "IDEMPOTENCY_KEY_REQUIRED" }, 400);
    }

    const body = await request.json().catch(() => null) as Partial<WalletRequest> | null;
    if (!body || !validText(body.transactionRef) || !validText(body.playerRef) ||
        !validText(body.sessionRef) || !validText(body.roundRef) ||
        !Number.isSafeInteger(body.amountMinor) || (body.amountMinor ?? 0) <= 0 ||
        !/^[A-Z]{3}$/.test(body.currency || "")) {
      return json({ ok: false, error: "INVALID_WALLET_REQUEST" }, 400);
    }
    if (operation === "REFUND" && !validText(body.originalTransactionRef)) {
      return json({ ok: false, error: "ORIGINAL_TRANSACTION_REQUIRED" }, 400);
    }

    const canonical = {
      operation,
      transactionRef: body.transactionRef,
      playerRef: body.playerRef,
      amountMinor: body.amountMinor,
      currency: body.currency,
      sessionRef: body.sessionRef,
      roundRef: body.roundRef,
      originalTransactionRef: body.originalTransactionRef || null,
    };
    const payloadHash = await sha256(JSON.stringify(canonical));
    const existing = byIdempotency.get(idempotencyKey);

    if (existing) {
      if (existing.payloadHash !== payloadHash) {
        return json({ ok: false, error: "IDEMPOTENCY_CONFLICT" }, 409);
      }
      const response = {
        ok: existing.state === "CONFIRMED",
        transaction: responseFor(existing),
        replay: true,
      };
      return json(response, existing.state === "PENDING" ? 202 : 200);
    }

    if (byReference.has(body.transactionRef!)) {
      return json({ ok: false, error: "TRANSACTION_REFERENCE_CONFLICT" }, 409);
    }

    const faultMode = request.headers.get("x-simulate-fault") || "normal";
    if (!["normal", "decline", "accept_then_timeout", "pending_then_confirm"].includes(faultMode)) {
      return json({ ok: false, error: "INVALID_SIMULATION_MODE" }, 400);
    }

    const tx: StoredTransaction = {
      transactionRef: body.transactionRef!,
      idempotencyKey,
      payloadHash,
      operation,
      playerRef: body.playerRef!,
      amountMinor: body.amountMinor!,
      currency: body.currency!,
      sessionRef: body.sessionRef!,
      roundRef: body.roundRef!,
      originalTransactionRef: body.originalTransactionRef,
      refundedMinor: 0,
      state: "PENDING",
      faultMode,
      responseCode: "PENDING",
      responseAt: new Date().toISOString(),
    };
    byIdempotency.set(idempotencyKey, tx);
    byReference.set(tx.transactionRef, tx);

    if (faultMode === "decline") {
      tx.state = "DECLINED";
      tx.responseCode = "SIMULATED_DECLINE";
      tx.responseAt = new Date().toISOString();
    } else if (faultMode === "pending_then_confirm") {
      tx.state = "PENDING";
      tx.responseCode = "PROCESSING";
    } else {
      applyEffect(tx);
    }

    // Simulates the critical distributed-systems case: partner applies the
    // wallet effect, persists it, but the HTTP response is lost.
    if (faultMode === "accept_then_timeout" && tx.state === "CONFIRMED") {
      return json({ ok: false, error: "SIMULATED_RESPONSE_LOST_AFTER_ACCEPTANCE" }, 504);
    }

    return json(
      { ok: tx.state === "CONFIRMED", transaction: responseFor(tx), replay: false },
      tx.state === "PENDING" ? 202 : 200,
    );
  }

  return {
    handler,
    getBalance,
    transactionCount: () => byReference.size,
  };
}

if (import.meta.main) {
  const port = Number(Deno.env.get("PORT") || "8787");
  const initialBalanceMinor = Number(Deno.env.get("SIM_INITIAL_BALANCE_MINOR") || "100000");
  const mock = createMockPartner({ initialBalanceMinor });
  console.log(`ASIX mock operator wallet listening on http://127.0.0.1:${port}`);
  Deno.serve({ hostname: "127.0.0.1", port }, mock.handler);
}

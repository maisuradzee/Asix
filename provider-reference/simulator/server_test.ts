import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createMockPartner } from "./server.ts";

const base = {
  transactionRef: "tx-bet-001",
  playerRef: "player-1",
  amountMinor: 1_000,
  currency: "GEL",
  sessionRef: "session-1",
  roundRef: "round-1",
};

function walletRequest(
  path: string,
  key: string,
  body: Record<string, unknown>,
  fault?: string,
): Request {
  const headers = new Headers({
    "content-type": "application/json",
    "idempotency-key": key,
  });
  if (fault) headers.set("x-simulate-fault", fault);
  return new Request(`http://127.0.0.1${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

Deno.test("same idempotency key creates one debit only", async () => {
  const mock = createMockPartner({ initialBalanceMinor: 10_000 });
  const first = await mock.handler(walletRequest("/wallet/bet", "idem-001", base));
  const second = await mock.handler(walletRequest("/wallet/bet", "idem-001", base));
  assertEquals(first.status, 200);
  assertEquals(second.status, 200);
  assertEquals(mock.getBalance("player-1", "GEL"), 9_000);
  assertEquals(mock.transactionCount(), 1);
});

Deno.test("same key with changed amount is rejected", async () => {
  const mock = createMockPartner({ initialBalanceMinor: 10_000 });
  await mock.handler(walletRequest("/wallet/bet", "idem-002", base));
  const altered = { ...base, amountMinor: 2_000 };
  const response = await mock.handler(walletRequest("/wallet/bet", "idem-002", altered));
  assertEquals(response.status, 409);
  assertEquals(mock.getBalance("player-1", "GEL"), 9_000);
});

Deno.test("accepted debit with lost response is recovered by status query without second debit", async () => {
  const mock = createMockPartner({ initialBalanceMinor: 10_000 });
  const timeout = await mock.handler(walletRequest(
    "/wallet/bet", "idem-003", base, "accept_then_timeout",
  ));
  assertEquals(timeout.status, 504);
  assertEquals(mock.getBalance("player-1", "GEL"), 9_000);

  const status = await mock.handler(new Request(
    `http://127.0.0.1/wallet/transactions/${base.transactionRef}`,
  ));
  const payload = await status.json();
  assertEquals(payload.transaction.state, "CONFIRMED");

  await mock.handler(walletRequest("/wallet/bet", "idem-003", base));
  assertEquals(mock.getBalance("player-1", "GEL"), 9_000);
  assertEquals(mock.transactionCount(), 1);
});

Deno.test("pending transaction is resolved exactly once by status query", async () => {
  const mock = createMockPartner({ initialBalanceMinor: 10_000 });
  const pending = await mock.handler(walletRequest(
    "/wallet/bet", "idem-004", base, "pending_then_confirm",
  ));
  assertEquals(pending.status, 202);
  assertEquals(mock.getBalance("player-1", "GEL"), 10_000);

  await mock.handler(new Request(
    `http://127.0.0.1/wallet/transactions/${base.transactionRef}`,
  ));
  assertEquals(mock.getBalance("player-1", "GEL"), 9_000);

  await mock.handler(new Request(
    `http://127.0.0.1/wallet/transactions/${base.transactionRef}`,
  ));
  assertEquals(mock.getBalance("player-1", "GEL"), 9_000);
});

Deno.test("refund cannot exceed original bet amount", async () => {
  const mock = createMockPartner({ initialBalanceMinor: 10_000 });
  await mock.handler(walletRequest("/wallet/bet", "idem-005", base));

  const refund = await mock.handler(walletRequest("/wallet/refund", "idem-006", {
    ...base,
    transactionRef: "tx-refund-001",
    amountMinor: 1_001,
    originalTransactionRef: base.transactionRef,
  }));
  const payload = await refund.json();
  assertEquals(payload.transaction.state, "DECLINED");
  assertEquals(mock.getBalance("player-1", "GEL"), 9_000);
});


Deno.test("declined debit remains declined on idempotent replay", async () => {
  const mock = createMockPartner({ initialBalanceMinor: 10_000 });
  const declined = await mock.handler(walletRequest("/wallet/bet", "idem-007", base, "decline"));
  const replay = await mock.handler(walletRequest("/wallet/bet", "idem-007", base));
  const firstPayload = await declined.json();
  const secondPayload = await replay.json();
  assertEquals(firstPayload.transaction.state, "DECLINED");
  assertEquals(secondPayload.transaction.state, "DECLINED");
  assertEquals(secondPayload.ok, false);
  assertEquals(secondPayload.replay, true);
  assertEquals(mock.getBalance("player-1", "GEL"), 10_000);
  assertEquals(mock.transactionCount(), 1);
});

Deno.test("win credit is idempotent", async () => {
  const mock = createMockPartner({ initialBalanceMinor: 10_000 });
  const winBody = { ...base, transactionRef: "tx-win-001", amountMinor: 2_500 };
  await mock.handler(walletRequest("/wallet/win", "idem-008", winBody));
  await mock.handler(walletRequest("/wallet/win", "idem-008", winBody));
  assertEquals(mock.getBalance("player-1", "GEL"), 12_500);
  assertEquals(mock.transactionCount(), 1);
});

Deno.test("partial refund is capped and duplicate refund has one effect", async () => {
  const mock = createMockPartner({ initialBalanceMinor: 10_000 });
  await mock.handler(walletRequest("/wallet/bet", "idem-009", base));
  const partial = {
    ...base,
    transactionRef: "tx-refund-partial-001",
    amountMinor: 400,
    originalTransactionRef: base.transactionRef,
  };
  await mock.handler(walletRequest("/wallet/refund", "idem-010", partial));
  await mock.handler(walletRequest("/wallet/refund", "idem-010", partial));
  assertEquals(mock.getBalance("player-1", "GEL"), 9_400);
  assertEquals(mock.transactionCount(), 2);
});


Deno.test("refund against a declined bet is rejected with no balance effect", async () => {
  const mock = createMockPartner({ initialBalanceMinor: 10_000 });
  await mock.handler(walletRequest("/wallet/bet", "idem-011", base, "decline"));
  const refund = await mock.handler(walletRequest("/wallet/refund", "idem-012", {
    ...base,
    transactionRef: "tx-refund-declined-001",
    amountMinor: 500,
    originalTransactionRef: base.transactionRef,
  }));
  const payload = await refund.json();
  assertEquals(payload.transaction.state, "DECLINED");
  assertEquals(payload.transaction.responseCode, "ORIGINAL_BET_NOT_FOUND");
  assertEquals(mock.getBalance("player-1", "GEL"), 10_000);
});

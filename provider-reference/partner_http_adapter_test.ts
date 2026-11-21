import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  HttpPartnerWalletAdapter,
  PartnerHttpAdapterError,
  type PartnerHttpRequestPlan,
  type PartnerHttpResponse,
  type PartnerRequestSigner,
  type PartnerWalletProtocol,
  type PartnerFetch,
} from "./partner_http_adapter.ts";
import type {
  PartnerCode,
  IsoCurrencyCode,
  MinorUnits,
  WalletCommand,
  WalletResult,
  TransactionStatusQuery,
  PartnerHealth,
} from "./contracts.ts";

const partnerCode = "partner-a" as PartnerCode;
const currency = "GEL" as IsoCurrencyCode;

const cmd: WalletCommand = {
  transactionId: "provider-tx-1",
  idempotencyKey: "partner-idem-1",
  operation: "BET",
  partnerCode,
  partnerPlayerRef: "opaque-player",
  partnerSessionRef: "operator-session",
  roundId: "round-1",
  amountMinor: 500n as MinorUnits,
  currency,
  currencyExponent: 2,
  correlationId: "corr-1",
  adapterVersion: "adapter-v1",
  protocolVersion: "protocol-v1",
  createdAt: "2026-11-21T08:00:00.000Z",
};

function result(command: WalletCommand, state: WalletResult["state"] = "CONFIRMED"): WalletResult {
  return {
    transactionId: command.transactionId,
    partnerCode: command.partnerCode,
    state,
    partnerTransactionRef: "operator-tx-1",
    amountMinor: command.amountMinor,
    currency: command.currency,
    responseCode: "OK",
    responseAt: "2026-11-21T08:00:01.000Z",
    responseHash: "sha256:response",
    correlationId: command.correlationId,
    adapterVersion: command.adapterVersion,
    protocolVersion: command.protocolVersion,
  };
}

const protocol: PartnerWalletProtocol = {
  buildWalletRequest: async (operation, command): Promise<PartnerHttpRequestPlan> => ({
    method: "POST",
    path: `wallet/${operation.toLowerCase()}`,
    body: JSON.stringify({
      transaction_id: command.transactionId,
      player: command.partnerPlayerRef,
      amount_minor: command.amountMinor.toString(),
      currency: command.currency,
    }),
    readOnly: false,
  }),
  parseWalletResponse: async (_response, command) => result(command),
  buildStatusRequest: async (query): Promise<PartnerHttpRequestPlan> => ({
    method: "GET",
    path: `wallet/transactions/${encodeURIComponent(query.partnerTransactionRef ?? query.transactionId)}`,
    readOnly: true,
  }),
  parseStatusResponse: async (response, query) => ({
    ...result({
      ...cmd,
      transactionId: query.transactionId,
      idempotencyKey: query.idempotencyKey,
      partnerCode: query.partnerCode,
      correlationId: query.correlationId,
      adapterVersion: query.adapterVersion,
      protocolVersion: query.protocolVersion,
    }, response.status === 200 ? "CONFIRMED" : "UNKNOWN"),
  }),
  buildHealthRequest: async (): Promise<PartnerHttpRequestPlan> => ({
    method: "GET",
    path: "health",
    readOnly: true,
  }),
  parseHealthResponse: async (_response, p): Promise<PartnerHealth> => ({
    partnerCode: p as PartnerCode,
    healthy: true,
    checkedAt: "2026-11-21T08:00:01.000Z",
  }),
};

const signer: PartnerRequestSigner = {
  sign: async () => ({ "x-partner-signature": "test-signature" }),
};

function makeAdapter(fetcher: PartnerFetch, overrides: Record<string, unknown> = {}) {
  return new HttpPartnerWalletAdapter({
    partnerCode: "partner-a",
    baseUrl: "https://wallet.operator.example/api/v1/",
    credentialReference: "kms://partner-a/key-v1",
    adapterVersion: "adapter-v1",
    protocolVersion: "protocol-v1",
    ...overrides,
  }, protocol, signer, fetcher, () => new Date("2026-11-21T08:00:00.000Z"));
}

Deno.test("wallet request uses HTTPS base path, idempotency and partner signature", async () => {
  let seenUrl = "";
  let seenInit: RequestInit | undefined;
  const fetcher: PartnerFetch = async (url, init) => {
    seenUrl = String(url);
    seenInit = init;
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  };
  const adapter = makeAdapter(fetcher);
  const response = await adapter.debitBet(cmd);
  assertEquals(response.state, "CONFIRMED");
  assertEquals(seenUrl, "https://wallet.operator.example/api/v1/wallet/bet");
  const headers = new Headers(seenInit?.headers);
  assertEquals(headers.get("idempotency-key"), "partner-idem-1");
  assertEquals(headers.get("x-partner-signature"), "test-signature");
  assertEquals(seenInit?.redirect, "error");
});

Deno.test("partner scope and adapter version mismatch are rejected before network", async () => {
  let calls = 0;
  const fetcher: PartnerFetch = async () => {
    calls += 1;
    return new Response("{}", { status: 200 });
  };
  const adapter = makeAdapter(fetcher);
  await assertRejects(
    () => adapter.debitBet({ ...cmd, partnerCode: "partner-b" as PartnerCode }),
    PartnerHttpAdapterError,
    "PARTNER_SCOPE_MISMATCH",
  );
  await assertRejects(
    () => adapter.debitBet({ ...cmd, adapterVersion: "old" }),
    PartnerHttpAdapterError,
    "PARTNER_ADAPTER_VERSION_MISMATCH",
  );
  assertEquals(calls, 0);
});

Deno.test("absolute or cross-origin adapter path is rejected", async () => {
  const badProtocol: PartnerWalletProtocol = {
    ...protocol,
    buildWalletRequest: async () => ({
      method: "POST",
      path: "https://evil.example/steal",
      body: "{}",
      readOnly: false,
    }),
  };
  const fetcher: PartnerFetch = async () => new Response("{}", { status: 200 });
  const adapter = new HttpPartnerWalletAdapter({
    partnerCode: "partner-a",
    baseUrl: "https://wallet.operator.example/api/v1/",
    credentialReference: "kms://partner-a/key-v1",
    adapterVersion: "adapter-v1",
    protocolVersion: "protocol-v1",
  }, badProtocol, signer, fetcher);
  await assertRejects(
    () => adapter.debitBet(cmd),
    PartnerHttpAdapterError,
    "INVALID_PARTNER_REQUEST_PATH",
  );
});

Deno.test("timeouts are surfaced as uncertain and are not automatically retried", async () => {
  let calls = 0;
  const fetcher: PartnerFetch = async (_url, init) => {
    calls += 1;
    return await new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")));
    });
  };
  const adapter = makeAdapter(fetcher, { requestTimeoutMs: 50 });
  await assertRejects(
    () => adapter.debitBet(cmd),
    PartnerHttpAdapterError,
    "PARTNER_REQUEST_TIMEOUT",
  );
  assertEquals(calls, 1);
});

Deno.test("oversized partner response is rejected", async () => {
  const fetcher: PartnerFetch = async () => new Response("1234567890", { status: 200 });
  const adapter = makeAdapter(fetcher, { maxResponseBytes: 4 });
  await assertRejects(
    () => adapter.debitBet(cmd),
    PartnerHttpAdapterError,
    "PARTNER_RESPONSE_TOO_LARGE",
  );
});

Deno.test("status query must be explicitly marked read-only", async () => {
  const unsafeProtocol: PartnerWalletProtocol = {
    ...protocol,
    buildStatusRequest: async () => ({
      method: "POST",
      path: "wallet/status",
      body: JSON.stringify({ transaction_id: "x" }),
      readOnly: false,
    }),
  };
  let calls = 0;
  const fetcher: PartnerFetch = async () => {
    calls += 1;
    return new Response("{}", { status: 200 });
  };
  const adapter = new HttpPartnerWalletAdapter({
    partnerCode: "partner-a",
    baseUrl: "https://wallet.operator.example/api/v1/",
    credentialReference: "kms://partner-a/key-v1",
    adapterVersion: "adapter-v1",
    protocolVersion: "protocol-v1",
  }, unsafeProtocol, signer, fetcher);
  const query: TransactionStatusQuery = {
    transactionId: cmd.transactionId,
    idempotencyKey: cmd.idempotencyKey,
    partnerCode: cmd.partnerCode,
    correlationId: cmd.correlationId,
    adapterVersion: cmd.adapterVersion,
    protocolVersion: cmd.protocolVersion,
    requestedAt: cmd.createdAt,
  };
  await assertRejects(
    () => adapter.getTransactionStatus(query),
    PartnerHttpAdapterError,
    "STATUS_REQUEST_MUST_BE_READ_ONLY",
  );
  assertEquals(calls, 0);
});

Deno.test("health check can use only a read-only partner health request", async () => {
  const fetcher: PartnerFetch = async () => new Response("{}", { status: 200 });
  const adapter = makeAdapter(fetcher);
  const health = await adapter.healthCheck({
    partnerCode: cmd.partnerCode,
    correlationId: cmd.correlationId,
    adapterVersion: cmd.adapterVersion,
    protocolVersion: cmd.protocolVersion,
  });
  assertEquals(health.healthy, true);
});

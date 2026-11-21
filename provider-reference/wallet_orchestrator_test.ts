import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import type {
  PartnerWalletAdapter,
  WalletCommand,
  WalletResult,
  PartnerCode,
  IsoCurrencyCode,
  MinorUnits,
} from "./contracts.ts";
import {
  WalletOrchestrator,
  IdempotencyConflictError,
  computeWalletRequestHash,
} from "./wallet_orchestrator.ts";
import { InMemoryWalletTransactionRepository } from "./testing/in_memory_repository.ts";

const partner = "operator-demo" as PartnerCode;
const currency = "GEL" as IsoCurrencyCode;

function command(overrides: Partial<WalletCommand> = {}): WalletCommand {
  return {
    transactionId: "tx-provider-001",
    idempotencyKey: "idem-provider-001",
    operation: "BET",
    partnerCode: partner,
    partnerPlayerRef: "pseudonymous-player-1",
    partnerSessionRef: "operator-session-1",
    roundId: "round-1",
    amountMinor: 500n as MinorUnits,
    currency,
    currencyExponent: 2,
    correlationId: "corr-1",
    adapterVersion: "mock-v1",
    protocolVersion: "provider-v1",
    createdAt: "2026-11-21T00:00:00.000Z",
    ...overrides,
  };
}

function result(cmd: WalletCommand, state: WalletResult["state"]): WalletResult {
  return {
    transactionId: cmd.transactionId,
    partnerCode: cmd.partnerCode,
    state,
    amountMinor: cmd.amountMinor,
    currency: cmd.currency,
    responseCode: state === "CONFIRMED" ? "OK" : state,
    responseAt: "2026-11-21T00:00:01.000Z",
    responseHash: "sha256:mock-response",
    ...(state === "CONFIRMED" ? { partnerTransactionRef: `partner-${cmd.transactionId}` } : {}),
    correlationId: cmd.correlationId,
    adapterVersion: cmd.adapterVersion,
    protocolVersion: cmd.protocolVersion,
  };
}

function makeAdapter(overrides: Partial<PartnerWalletAdapter> = {}): PartnerWalletAdapter {
  return {
    debitBet: async (cmd) => result(cmd, "CONFIRMED"),
    creditWin: async (cmd) => result(cmd, "CONFIRMED"),
    refund: async (cmd) => result(cmd, "CONFIRMED"),
    getTransactionStatus: async (query) => {
      const cmd = command({
        transactionId: query.transactionId,
        idempotencyKey: query.idempotencyKey,
        partnerCode: query.partnerCode,
        correlationId: query.correlationId,
        adapterVersion: query.adapterVersion,
        protocolVersion: query.protocolVersion,
      });
      return result(cmd, "CONFIRMED");
    },
    healthCheck: async () => ({
      partnerCode: partner,
      healthy: true,
      checkedAt: "2026-11-21T00:00:01.000Z",
    }),
    ...overrides,
  };
}

Deno.test("confirmed bet is sent once and duplicate request returns stored result", async () => {
  const repo = new InMemoryWalletTransactionRepository();
  let sends = 0;
  const adapter = makeAdapter({
    debitBet: async (cmd) => {
      sends += 1;
      return result(cmd, "CONFIRMED");
    },
  });
  const service = new WalletOrchestrator(repo, () => adapter);
  const cmd = command();

  const first = await service.execute(cmd, "worker-a");
  const second = await service.execute(cmd, "worker-b");

  assertEquals(first.state, "CONFIRMED");
  assertEquals(second.state, "CONFIRMED");
  assertEquals(sends, 1);
});

Deno.test("transport failure becomes UNKNOWN then resolves by read-only status query", async () => {
  const repo = new InMemoryWalletTransactionRepository();
  let statusQueries = 0;
  const adapter = makeAdapter({
    debitBet: async () => {
      throw new Error("network timeout after partner accepted request");
    },
    getTransactionStatus: async (query) => {
      statusQueries += 1;
      const cmd = command({
        transactionId: query.transactionId,
        idempotencyKey: query.idempotencyKey,
        partnerCode: query.partnerCode,
        correlationId: query.correlationId,
        adapterVersion: query.adapterVersion,
        protocolVersion: query.protocolVersion,
      });
      return result(cmd, "CONFIRMED");
    },
  });
  const service = new WalletOrchestrator(repo, () => adapter);
  const cmd = command();
  const sent = await service.execute(cmd, "worker-a");
  assertEquals(sent.state, "UNKNOWN");
  assertEquals(statusQueries, 0);

  const resolved = await service.resolveUnknown(cmd.transactionId);
  assertEquals(resolved.state, "CONFIRMED");
  assertEquals(statusQueries, 1);
});

Deno.test("same idempotency key with a different financial payload is rejected", async () => {
  const repo = new InMemoryWalletTransactionRepository();
  const service = new WalletOrchestrator(repo, () => makeAdapter());
  await service.execute(command(), "worker-a");
  await assertRejects(
    () => service.execute(command({ amountMinor: 750n as MinorUnits }), "worker-b"),
    IdempotencyConflictError,
  );
});

Deno.test("expired dispatch lease becomes UNKNOWN and is never automatically resent", async () => {
  const repo = new InMemoryWalletTransactionRepository();
  const now = new Date("2026-11-21T00:00:00.000Z");
  const afterLeaseExpiry = new Date("2026-11-21T00:00:02.000Z");
  const service = new WalletOrchestrator(repo, () => makeAdapter({
    debitBet: async () => new Promise<WalletResult>(() => {}),
  }), () => afterLeaseExpiry, 1_000, 50);

  // Insert and claim through the repository to simulate a worker crash after dispatch.
  const cmd = command();
  const inserted = await repo.createOrGet(cmd, await computeWalletRequestHash(cmd), now.toISOString());
  assertEquals(inserted.record.state, "CREATED");
  await repo.claimInitialDispatch(cmd.transactionId, "crashed-worker", "2026-11-21T00:00:01.000Z", now.toISOString());

  const recovered = await service.recoverExpiredDispatch(cmd.transactionId);
  assertEquals(recovered.state, "UNKNOWN");
  assertEquals(recovered.attemptCount, 1);
});

Deno.test("partner response with wrong transaction context is held as UNKNOWN", async () => {
  const repo = new InMemoryWalletTransactionRepository();
  const cmd = command();
  const adapter = makeAdapter({
    debitBet: async (input) => ({
      ...result(input, "CONFIRMED"),
      transactionId: "other-transaction",
    }),
  });
  const service = new WalletOrchestrator(repo, () => adapter);
  const record = await service.execute(cmd, "worker-a");
  assertEquals(record.state, "UNKNOWN");
  assertEquals(record.lastErrorCode, "PARTNER_RESPONSE_CONTEXT_MISMATCH");
});


Deno.test("hung partner request times out to UNKNOWN without retry", async () => {
  const repo = new InMemoryWalletTransactionRepository();
  let dispatches = 0;
  const adapter = makeAdapter({
    debitBet: async () => {
      dispatches += 1;
      return new Promise<WalletResult>(() => {});
    },
  });
  const service = new WalletOrchestrator(repo, () => adapter, () => new Date(), 30_000, 50);
  const cmd = command({ transactionId: "tx-timeout-001", idempotencyKey: "idem-timeout-001" });
  const record = await service.execute(cmd, "worker-timeout");
  assertEquals(record.state, "UNKNOWN");
  assertEquals(record.lastErrorCode, "PARTNER_REQUEST_TIMEOUT");
  assertEquals(dispatches, 1);
});


Deno.test("refund commands require original ASIX and partner transaction references", async () => {
  const repo = new InMemoryWalletTransactionRepository();
  const service = new WalletOrchestrator(repo, () => makeAdapter());
  await assertRejects(
    () => service.execute(command({
      transactionId: "tx-refund-invalid",
      idempotencyKey: "idem-refund-invalid",
      operation: "REFUND",
    }), "worker-refund"),
    Error,
    "INVALID_WALLET_COMMAND",
  );
});

Deno.test("confirmed refund carries original debit references into adapter", async () => {
  const repo = new InMemoryWalletTransactionRepository();
  let observedOriginalId = "";
  let observedOriginalPartnerRef = "";
  const adapter = makeAdapter({
    refund: async (cmd) => {
      observedOriginalId = cmd.originalTransactionId ?? "";
      observedOriginalPartnerRef = cmd.originalPartnerTransactionRef ?? "";
      return result(cmd, "CONFIRMED");
    },
  });
  const service = new WalletOrchestrator(repo, () => adapter);
  const refundCommand = command({
    transactionId: "tx-refund-002",
    idempotencyKey: "idem-refund-002",
    operation: "REFUND",
    originalTransactionId: "tx-bet-original",
    originalPartnerTransactionRef: "operator-bet-original",
  });
  const record = await service.execute(refundCommand, "worker-refund");
  assertEquals(record.state, "CONFIRMED");
  assertEquals(observedOriginalId, "tx-bet-original");
  assertEquals(observedOriginalPartnerRef, "operator-bet-original");
});

Deno.test("status query cannot replace an existing partner transaction reference", async () => {
  const repo = new InMemoryWalletTransactionRepository();
  const original = command();
  const adapter = makeAdapter({
    debitBet: async (cmd) => ({ ...result(cmd, "PENDING"), partnerTransactionRef: "partner-tx-original" }),
    getTransactionStatus: async (query) => {
      const cmd = command({
        transactionId: query.transactionId,
        idempotencyKey: query.idempotencyKey,
        partnerCode: query.partnerCode,
        correlationId: query.correlationId,
        adapterVersion: query.adapterVersion,
        protocolVersion: query.protocolVersion,
      });
      return { ...result(cmd, "CONFIRMED"), partnerTransactionRef: "partner-tx-unexpected" };
    },
  });
  const service = new WalletOrchestrator(repo, () => adapter);
  const sent = await service.execute(original, "worker-a");
  assertEquals(sent.state, "PENDING");
  const resolved = await service.resolveUnknown(original.transactionId);
  assertEquals(resolved.state, "PENDING");
  assertEquals(resolved.lastErrorCode, "PARTNER_RESPONSE_REFERENCE_MISMATCH");
});

import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ProviderPostgresRepository,
  ProviderDatabaseError,
  type ProviderPgExecutor,
  type PgQueryResult,
} from "./postgres_repository.ts";

class MockPg implements ProviderPgExecutor {
  calls: Array<{ sql: string; parameters: readonly unknown[] }> = [];
  responder: (sql: string, parameters: readonly unknown[]) => Record<string, unknown>[] = () => [];

  async query<T extends Record<string, unknown>>(
    sql: string,
    parameters: readonly unknown[],
  ): Promise<PgQueryResult<T>> {
    this.calls.push({ sql, parameters });
    const rows = this.responder(sql, parameters) as T[];
    return { rows, rowCount: rows.length };
  }
}

const hash = new Uint8Array(32).fill(7);

Deno.test("partner key resolution returns only active key metadata and secret references", async () => {
  const db = new MockPg();
  db.responder = () => [{
    partner_id: "partner-uuid",
    partner_code: "ci-operator",
    key_id: "ci-key-1",
    auth_profile: "ASIX_HMAC_SHA256_V1",
    protocol_version: "provider-v1",
    secret_reference: "kms://partners/ci-operator/hmac-v1",
    public_key_reference: null,
  }];
  const repo = new ProviderPostgresRepository(db);
  const key = await repo.resolvePartnerKey("ci-operator", "ci-key-1");
  assertEquals(key?.partner_id, "partner-uuid");
  assertEquals(key?.auth_profile, "ASIX_HMAC_SHA256_V1");
  assertEquals(key?.secret_reference, "kms://partners/ci-operator/hmac-v1");
  assertEquals(db.calls[0].sql.includes("resolve_partner_key"), true);
  assertEquals(db.calls[0].parameters, ["ci-operator", "ci-key-1"]);
});

Deno.test("unknown or inactive partner key metadata resolves to null", async () => {
  const db = new MockPg();
  db.responder = () => [];
  const repo = new ProviderPostgresRepository(db);
  assertEquals(await repo.resolvePartnerKey("ci-operator", "revoked-key"), null);
});

Deno.test("invalid partner-key lookup parameters are rejected before database access", async () => {
  const db = new MockPg();
  const repo = new ProviderPostgresRepository(db);
  await assertRejects(
    () => repo.resolvePartnerKey("INVALID partner", "key-1"),
    ProviderDatabaseError,
    "INVALID_PARTNER_KEY_LOOKUP",
  );
  assertEquals(db.calls.length, 0);
});

Deno.test("nonce consumption calls atomic DB function with hash", async () => {
  const db = new MockPg();
  db.responder = () => [{ consumed: true }];
  const repo = new ProviderPostgresRepository(db);
  const consumed = await repo.consumePartnerNonce({
    partnerId: "00000000-0000-4000-8000-000000000001",
    keyId: "key-a",
    nonceHash: hash,
    expiresAt: "2026-11-21T12:00:00.000Z",
  });
  assertEquals(consumed, true);
  assertEquals(db.calls.length, 1);
  assertEquals(db.calls[0].sql.includes("consume_partner_nonce"), true);
  assertEquals(db.calls[0].parameters[2], hash);
});

Deno.test("duplicate nonce returns false", async () => {
  const db = new MockPg();
  db.responder = () => [{ consumed: false }];
  const repo = new ProviderPostgresRepository(db);
  const consumed = await repo.consumePartnerNonce({
    partnerId: "00000000-0000-4000-8000-000000000001",
    keyId: "key-a",
    nonceHash: hash,
    expiresAt: "2026-11-21T12:00:00.000Z",
  });
  assertEquals(consumed, false);
});

Deno.test("launch token maps to claims and returns null when no token is consumable", async () => {
  const db = new MockPg();
  db.responder = () => [{
    partner_id: "partner-id",
    session_id: "session-id",
    partner_player_ref: "opaque-player",
    partner_session_ref: "operator-session",
    game_code: "ASIX_CARD",
    currency: "GEL",
    jurisdiction: "GE",
    locale: "ka-GE",
    session_status: "ACTIVE",
  }];
  const repo = new ProviderPostgresRepository(db);
  assertEquals((await repo.consumeLaunchToken(hash))?.partner_session_ref, "operator-session");
  db.responder = () => [];
  assertEquals(await repo.consumeLaunchToken(hash), null);
});

Deno.test("launch session uses partner-scoped config and one-use token hash", async () => {
  const db = new MockPg();
  db.responder = () => [{
    session_id: "session-launch-1",
    session_status: "CREATED",
    token_issued: true,
    token_expires_at: "2026-11-21T12:02:00.000Z",
  }];
  const repo = new ProviderPostgresRepository(db);
  const result = await repo.createLaunchSession({
    partnerId: "00000000-0000-4000-8000-000000000001",
    partnerPlayerRef: "opaque-player",
    partnerSessionRef: "operator-session",
    gameCode: "ASIX_CARD",
    jurisdiction: "GE",
    currency: "GEL",
    currencyExponent: 2,
    locale: "ka-GE",
    policyVersion: 1,
    tokenHash: hash,
    expiresAt: "2026-11-21T12:02:00.000Z",
  });
  assertEquals(result.sessionId, "session-launch-1");
  assertEquals(result.status, "CREATED");
  assertEquals(result.tokenIssued, true);
  assertEquals(db.calls[0].sql.includes("create_launch_session"), true);
  assertEquals(db.calls[0].parameters[0], "00000000-0000-4000-8000-000000000001");
  assertEquals(db.calls[0].parameters[9], hash);
});

Deno.test("launch session rejects invalid token hashes before database access", async () => {
  const db = new MockPg();
  const repo = new ProviderPostgresRepository(db);
  await assertRejects(
    () => repo.createLaunchSession({
      partnerId: "partner-1",
      partnerPlayerRef: "player-1",
      partnerSessionRef: "session-1",
      gameCode: "ASIX_CARD",
      jurisdiction: "GE",
      currency: "GEL",
      currencyExponent: 2,
      locale: "ka-GE",
      policyVersion: 1,
      tokenHash: new Uint8Array(16),
      expiresAt: "2026-11-21T12:02:00.000Z",
    }),
    ProviderDatabaseError,
    "INVALID_LAUNCH_TOKEN_HASH",
  );
  assertEquals(db.calls.length, 0);
});

Deno.test("wallet transaction sends integer minor units and request hash to DB function", async () => {
  const db = new MockPg();
  db.responder = () => [{
    transaction_id: "wallet-tx-id",
    transaction_status: "CREATED",
    was_created: true,
  }];
  const repo = new ProviderPostgresRepository(db);
  const result = await repo.createWalletTransaction({
    partnerId: "00000000-0000-4000-8000-000000000001",
    sessionId: "00000000-0000-4000-8000-000000000002",
    roundId: null,
    idempotencyKey: "partner-idem-1",
    requestHash: hash,
    operation: "BET",
    amountMinor: 125n,
    currency: "GEL",
    currencyExponent: 2,
  });
  assertEquals(result.transactionId, "wallet-tx-id");
  assertEquals(result.wasCreated, true);
  assertEquals(db.calls[0].parameters[6], "125");
  assertEquals(db.calls[0].parameters[4], hash);
});

Deno.test("refund requires original transaction before database call", async () => {
  const db = new MockPg();
  const repo = new ProviderPostgresRepository(db);
  await assertRejects(
    () => repo.createWalletTransaction({
      partnerId: "partner",
      sessionId: "session",
      roundId: null,
      idempotencyKey: "refund-1",
      requestHash: hash,
      operation: "REFUND",
      amountMinor: 100n,
      currency: "GEL",
      currencyExponent: 2,
    }),
    ProviderDatabaseError,
    "INVALID_WALLET_TRANSACTION_INPUT",
  );
  assertEquals(db.calls.length, 0);
});

Deno.test("outbox claim bounds lease inputs and returns claimed events", async () => {
  const db = new MockPg();
  db.responder = () => [{
    id: "event-id",
    partner_id: "partner-id",
    wallet_transaction_id: "tx-id",
    event_type: "WALLET_STATUS_QUERY",
    generation: 1,
    payload: { transaction_id: "tx-id" },
    attempts: 2,
    lease_until: "2026-11-21T12:00:30.000Z",
    lease_token: "00000000-0000-4000-8000-000000000099",
  }];
  const repo = new ProviderPostgresRepository(db);
  const events = await repo.claimOutboxEvents("00000000-0000-4000-8000-000000000003", 10, 45);
  assertEquals(events.length, 1);
  assertEquals(events[0].event_type, "WALLET_STATUS_QUERY");
  assertEquals(db.calls[0].parameters[1], 10);
  assertEquals(db.calls[0].parameters[2], 45);
});

Deno.test("ledger posting must be confirmed by DB function", async () => {
  const db = new MockPg();
  db.responder = () => [{ posted: true }];
  const repo = new ProviderPostgresRepository(db);
  assertEquals(
    await repo.postLedgerJournal("00000000-0000-4000-8000-000000000009", hash),
    true,
  );
});

Deno.test("partner response persistence binds the exact worker lease and response evidence", async () => {
  const db = new MockPg();
  db.responder = () => [{
    transaction_status: "CONFIRMED",
    status_query_generation: 0,
    was_recorded: true,
  }];
  const repo = new ProviderPostgresRepository(db);
  const result = await repo.recordWalletPartnerResponse({
    partnerId: "partner-1",
    workerId: "worker-9",
    leaseToken: "00000000-0000-4000-8000-000000000099",
    transactionId: "tx-9",
    attemptKind: "DISPATCH",
    generation: 0,
    attemptNumber: 1,
    requestHash: hash,
    responseHash: new Uint8Array(32).fill(8),
    targetStatus: "CONFIRMED",
    responseCode: "OK",
    partnerTransactionRef: "operator-tx-9",
  });
  assertEquals(result.transactionStatus, "CONFIRMED");
  assertEquals(result.wasRecorded, true);
  assertEquals(db.calls[0].sql.includes("record_wallet_partner_response"), true);
  assertEquals(db.calls[0].parameters[0], "partner-1");
  assertEquals(db.calls[0].parameters[1], "worker-9");
  assertEquals(db.calls[0].parameters[2], "00000000-0000-4000-8000-000000000099");
  assertEquals(db.calls[0].parameters[3], "tx-9");
  assertEquals(db.calls[0].parameters[7], hash);
});

Deno.test("PENDING response requires a next read-only status-query time", async () => {
  const db = new MockPg();
  const repo = new ProviderPostgresRepository(db);
  await assertRejects(
    () => repo.recordWalletPartnerResponse({
      partnerId: "partner-1",
      workerId: "worker-1",
      leaseToken: "lease-token-1",
      transactionId: "tx-1",
      attemptKind: "DISPATCH",
      generation: 0,
      attemptNumber: 1,
      requestHash: hash,
      responseHash: hash,
      targetStatus: "PENDING",
      responseCode: "PENDING",
    }),
    ProviderDatabaseError,
    "NEXT_STATUS_QUERY_TIME_REQUIRED",
  );
  assertEquals(db.calls.length, 0);
});

Deno.test("partner-scoped wallet status returns null when no record exists", async () => {
  const db = new MockPg();
  db.responder = () => [];
  const repo = new ProviderPostgresRepository(db);
  assertEquals(await repo.getWalletTransactionStatus("partner-1", "idem-1"), null);
  assertEquals(db.calls[0].sql.includes("get_wallet_transaction_status"), true);
  assertEquals(db.calls[0].parameters, ["partner-1", "idem-1"]);
});

Deno.test("expired read-only status-query leases use bounded recovery backoff", async () => {
  const db = new MockPg();
  db.responder = () => [{ recovered_count: 2 }];
  const repo = new ProviderPostgresRepository(db);
  const recovered = await repo.recoverExpiredStatusQueryLeases(15);
  assertEquals(recovered, 2);
  assertEquals(db.calls[0].sql.includes("recover_expired_wallet_status_query_leases"), true);
  assertEquals(db.calls[0].parameters, [15]);
});

Deno.test("status-query recovery rejects unbounded backoff before database access", async () => {
  const db = new MockPg();
  const repo = new ProviderPostgresRepository(db);
  await assertRejects(
    () => repo.recoverExpiredStatusQueryLeases(301),
    ProviderDatabaseError,
    "INVALID_STATUS_QUERY_BACKOFF",
  );
  assertEquals(db.calls.length, 0);
});

Deno.test("invalid hashes and currency are rejected before database access", async () => {
  const db = new MockPg();
  const repo = new ProviderPostgresRepository(db);
  await assertRejects(
    () => repo.consumeLaunchToken(new Uint8Array(12)),
    ProviderDatabaseError,
    "INVALID_LAUNCH_TOKEN_HASH",
  );
  await assertRejects(
    () => repo.createWalletTransaction({
      partnerId: "partner",
      sessionId: "session",
      roundId: null,
      idempotencyKey: "bet-1",
      requestHash: hash,
      operation: "BET",
      amountMinor: 100n,
      currency: "US",
      currencyExponent: 2,
    }),
    ProviderDatabaseError,
    "INVALID_CURRENCY_CONTEXT",
  );
  assertEquals(db.calls.length, 0);
});

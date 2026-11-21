import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  PostgresPartnerKeyResolver,
  PostgresReplayNonceStore,
  PostgresLaunchTokenStore,
  type ManagedHmacKeyProvider,
  type CurrencyExponentRegistry,
} from "./postgres_gateway_adapters.ts";
import {
  ProviderPostgresRepository,
  type ProviderPgExecutor,
  type PgQueryResult,
} from "./postgres_repository.ts";
import type { LaunchClaims, StoredLaunchToken } from "./launch_service.ts";

class FakePg implements ProviderPgExecutor {
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

const partnerId = "00000000-0000-4000-8000-000000000001";
const launchId = "00000000-0000-4000-8000-000000000110";
const sessionId = "00000000-0000-4000-8000-000000000109";
const secretReference = "kms://partners/operator-demo/hmac-v1";
const tokenHashBytes = new Uint8Array(32).fill(0xab);
const tokenHashHex = "sha256:" + Array.from(tokenHashBytes, (x) => x.toString(16).padStart(2, "0")).join("");

function partnerMetadata(overrides: Record<string, unknown> = {}) {
  return {
    partner_id: partnerId,
    partner_code: "operator-demo",
    key_id: "key-2026-01",
    auth_profile: "ASIX_HMAC_SHA256_V1",
    protocol_version: "provider-v1",
    secret_reference: secretReference,
    public_key_reference: null,
    ...overrides,
  };
}

function managedKeyProvider(key: CryptoKey): ManagedHmacKeyProvider {
  return {
    resolveHmacCryptoKey: async ({ secretReference: ref }) =>
      ref === secretReference ? key : null,
  };
}

function currencyRegistry(): CurrencyExponentRegistry {
  return {
    resolveExponent: (currency) => currency === "GEL" ? 2 : null,
  };
}

const signingKey = await crypto.subtle.importKey(
  "raw",
  new TextEncoder().encode("managed-test-hmac-key-only"),
  { name: "HMAC", hash: "SHA-256" },
  false,
  ["verify"],
);

Deno.test("Postgres HMAC key resolver scopes by partner and obtains non-exportable key from managed provider", async () => {
  const db = new FakePg();
  db.responder = () => [partnerMetadata()];
  const repository = new ProviderPostgresRepository(db);
  const resolver = new PostgresPartnerKeyResolver(repository, managedKeyProvider(signingKey));

  const resolved = await resolver.resolve("operator-demo", "key-2026-01");
  assertEquals(resolved?.partnerCode, "operator-demo");
  assertEquals(resolved?.keyId, "key-2026-01");
  assertEquals(resolved?.protocolVersion, "provider-v1");
  assertEquals(resolved?.active, true);
  assertEquals(resolved?.key, signingKey);
  assertEquals(db.calls.length, 1);
  assertEquals(db.calls[0].parameters, ["operator-demo", "key-2026-01"]);
});

Deno.test("Postgres HMAC key resolver fails closed for ECDSA profiles or unavailable KMS keys", async () => {
  const db = new FakePg();
  db.responder = () => [partnerMetadata({ auth_profile: "ECDSA_P256_SHA256_PAYLOAD_V1" })];
  const repository = new ProviderPostgresRepository(db);
  const resolver = new PostgresPartnerKeyResolver(repository, managedKeyProvider(signingKey));
  assertEquals(await resolver.resolve("operator-demo", "key-2026-01"), null);

  db.responder = () => [partnerMetadata()];
  const noKeyProvider: ManagedHmacKeyProvider = { resolveHmacCryptoKey: async () => null };
  const resolverWithoutKey = new PostgresPartnerKeyResolver(repository, noKeyProvider);
  assertEquals(await resolverWithoutKey.resolve("operator-demo", "key-2026-01"), null);
});

Deno.test("Postgres replay nonce store hashes nonce and consumes it in partner/key scope", async () => {
  const db = new FakePg();
  db.responder = (sql) => {
    if (sql.includes("resolve_partner_key")) return [partnerMetadata()];
    if (sql.includes("consume_partner_nonce")) return [{ consumed: true }];
    return [];
  };
  const repository = new ProviderPostgresRepository(db);
  const store = new PostgresReplayNonceStore(repository);
  const expires = 1_795_248_301;
  const accepted = await store.consume("operator-demo", "key-2026-01", "nonce_value_123456789", expires);

  assertEquals(accepted, true);
  assertEquals(db.calls.length, 2);
  assertEquals(db.calls[0].parameters, ["operator-demo", "key-2026-01"]);
  assertEquals(db.calls[1].parameters[0], partnerId);
  assertEquals(db.calls[1].parameters[1], "key-2026-01");
  const nonceHash = db.calls[1].parameters[2] as Uint8Array;
  assertEquals(nonceHash.length, 32);
  assertEquals(db.calls[1].parameters[3], new Date(expires * 1000).toISOString());
});

Deno.test("Postgres replay nonce store fails closed when key is no longer active", async () => {
  const db = new FakePg();
  db.responder = () => [];
  const repository = new ProviderPostgresRepository(db);
  const store = new PostgresReplayNonceStore(repository);
  assertEquals(await store.consume("operator-demo", "revoked-key", "nonce_value_123456789", 1_795_248_301), false);
  assertEquals(db.calls.length, 1);
});

const claims: LaunchClaims = {
  launchId,
  sessionId,
  partnerCode: "operator-demo",
  partnerPlayerRef: "opaque-player-77",
  partnerSessionRef: "casino-session-777",
  gameCode: "ASIX_CARD",
  currency: "GEL",
  jurisdiction: "GE",
  locale: "ka-GE",
  keyId: "key-2026-01",
  protocolVersion: "provider-v1",
  policyVersion: "policy-7",
  issuedAt: "2026-11-21T12:00:00.000Z",
  expiresAt: "2026-11-21T12:01:00.000Z",
};
const stored: StoredLaunchToken = { tokenHash: tokenHashHex, claims };

Deno.test("Postgres LaunchTokenStore creates token with key metadata and returns canonical DB session ID", async () => {
  const db = new FakePg();
  db.responder = (sql) => {
    if (sql.includes("resolve_partner_key")) return [partnerMetadata()];
    if (sql.includes("create_launch_session")) {
      return [{
        launch_id: launchId,
        session_id: "00000000-0000-4000-8000-000000000222",
        session_status: "CREATED",
        token_issued: true,
        token_expires_at: claims.expiresAt,
      }];
    }
    return [];
  };
  const repository = new ProviderPostgresRepository(db);
  const store = new PostgresLaunchTokenStore(repository, currencyRegistry());
  const persisted = await store.create(stored);

  assertEquals(persisted.launchId, launchId);
  assertEquals(persisted.sessionId, "00000000-0000-4000-8000-000000000222");
  assertEquals(db.calls.length, 2);
  assertEquals(db.calls[1].sql.includes("create_launch_session"), true);
  assertEquals(db.calls[1].parameters[1], "key-2026-01");
  assertEquals(db.calls[1].parameters[2], "provider-v1");
  assertEquals(db.calls[1].parameters[3], sessionId);
  assertEquals(db.calls[1].parameters[4], launchId);
  assertEquals(db.calls[1].parameters[10], 2);
  assertEquals(db.calls[1].parameters[12], "policy-7");
  assertEquals(db.calls[1].parameters[13] as Uint8Array, tokenHashBytes);
});

Deno.test("Postgres LaunchTokenStore rejects inactive key, unknown currency and non-issued session", async () => {
  const db = new FakePg();
  db.responder = () => [];
  const repository = new ProviderPostgresRepository(db);
  const store = new PostgresLaunchTokenStore(repository, currencyRegistry());
  await assertRejects(() => store.create(stored), Error, "PARTNER_KEY_NOT_ACTIVE");
  assertEquals(db.calls.length, 1);

  const db2 = new FakePg();
  db2.responder = () => [partnerMetadata()];
  const badCurrency = new PostgresLaunchTokenStore(
    new ProviderPostgresRepository(db2),
    { resolveExponent: () => null },
  );
  await assertRejects(
    () => badCurrency.create({ ...stored, claims: { ...claims, currency: "XYZ" } }),
    Error,
    "CURRENCY_EXPONENT_NOT_CONFIGURED",
  );
  assertEquals(db2.calls.length, 1);

  const db3 = new FakePg();
  db3.responder = (sql) => {
    if (sql.includes("resolve_partner_key")) return [partnerMetadata()];
    if (sql.includes("create_launch_session")) return [{
      launch_id: null,
      session_id: sessionId,
      session_status: "ACTIVE",
      token_issued: false,
      token_expires_at: null,
    }];
    return [];
  };
  const alreadyActive = new PostgresLaunchTokenStore(
    new ProviderPostgresRepository(db3),
    currencyRegistry(),
  );
  await assertRejects(() => alreadyActive.create(stored), Error, "PARTNER_SESSION_ALREADY_LAUNCHED");
});

Deno.test("Postgres LaunchTokenStore reconstructs complete claims from atomic token consumption", async () => {
  const db = new FakePg();
  db.responder = () => [{
    launch_id: launchId,
    session_id: sessionId,
    partner_id: partnerId,
    partner_code: "operator-demo",
    partner_player_ref: claims.partnerPlayerRef,
    partner_session_ref: claims.partnerSessionRef,
    game_code: claims.gameCode,
    currency: claims.currency,
    jurisdiction: claims.jurisdiction,
    locale: claims.locale,
    key_id: claims.keyId,
    protocol_version: claims.protocolVersion,
    policy_version: claims.policyVersion,
    issued_at: claims.issuedAt,
    expires_at: claims.expiresAt,
  }];
  const store = new PostgresLaunchTokenStore(
    new ProviderPostgresRepository(db),
    currencyRegistry(),
  );
  const consumed = await store.consumeOnce(tokenHashHex, "2026-11-21T12:00:01.000Z");
  assertEquals(consumed, claims);
  assertEquals(db.calls.length, 1);
  assertEquals(db.calls[0].sql.includes("consume_launch_token"), true);
});

Deno.test("Postgres LaunchTokenStore returns null on replay or expired token", async () => {
  const db = new FakePg();
  db.responder = () => [];
  const store = new PostgresLaunchTokenStore(
    new ProviderPostgresRepository(db),
    currencyRegistry(),
  );
  assertEquals(await store.consumeOnce(tokenHashHex, "2026-11-21T12:10:00.000Z"), null);
});

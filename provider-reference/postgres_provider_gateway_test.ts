import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { createPostgresProviderGateway } from "./postgres_provider_gateway.ts";
import { buildPartnerCanonicalPayload } from "./partner_auth.ts";
import type {
  ManagedHmacKeyProvider,
  CurrencyExponentRegistry,
} from "./postgres_gateway_adapters.ts";
import type {
  ProviderPgExecutor,
  PgQueryResult,
} from "./postgres_repository.ts";
import type { PartnerLaunchPolicyResolver } from "./launch_service.ts";

class FakePg implements ProviderPgExecutor {
  calls: Array<{ sql: string; parameters: readonly unknown[] }> = [];

  async query<T extends Record<string, unknown>>(
    sql: string,
    parameters: readonly unknown[],
  ): Promise<PgQueryResult<T>> {
    this.calls.push({ sql, parameters });
    let rows: Record<string, unknown>[] = [];

    if (sql.includes("resolve_partner_key")) {
      rows = [{
        partner_id: "00000000-0000-4000-8000-000000000001",
        partner_code: "operator-demo",
        key_id: "key-2026-01",
        auth_profile: "ASIX_HMAC_SHA256_V1",
        protocol_version: "provider-v1",
        secret_reference: "kms://partners/operator-demo/hmac-v1",
        public_key_reference: null,
      }];
    } else if (sql.includes("consume_partner_nonce")) {
      rows = [{ consumed: true }];
    } else if (sql.includes("create_launch_session")) {
      rows = [{
        launch_id: parameters[4],
        session_id: parameters[3],
        session_status: "CREATED",
        token_issued: true,
        token_expires_at: parameters[14],
      }];
    }

    return { rows: rows as T[], rowCount: rows.length };
  }
}

Deno.test("Postgres composition root issues a signed partner Launch through durable key, nonce and token adapters", async () => {
  const now = new Date("2026-11-21T14:30:00.000Z");
  const nowEpochSeconds = Math.floor(now.getTime() / 1000);
  const database = new FakePg();
  const hmacKey = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode("provider-gateway-composition-test-key"),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );

  const managedKeys: ManagedHmacKeyProvider = {
    resolveHmacCryptoKey: async ({ secretReference }) =>
      secretReference === "kms://partners/operator-demo/hmac-v1" ? hmacKey : null,
  };

  const currencies: CurrencyExponentRegistry = {
    resolveExponent: (currency) => currency === "GEL" ? 2 : null,
  };

  const policies: PartnerLaunchPolicyResolver = {
    resolve: async (partnerCode) => partnerCode === "operator-demo"
      ? {
        partnerCode,
        active: true,
        allowedGameCodes: ["ASIX_CARD"],
        allowedCurrencies: ["GEL"],
        allowedJurisdictions: ["GE"],
        allowedLocales: ["ka-GE"],
        launchBaseUrl: "https://games.asix.example.invalid/launch",
        tokenTtlSeconds: 60,
        policyVersion: "policy-7",
      }
      : null,
  };

  const handler = createPostgresProviderGateway({
    database,
    managedKeys,
    currencies,
    policies,
    rateLimiter: {
      consume: async () => ({ allowed: true }),
    },
    now: () => now,
    correlationId: () => "ci-provider-gateway-correlation",
  });

  const body = JSON.stringify({
    partner_player_ref: "opaque-player-77",
    partner_session_ref: "casino-session-777",
    game_code: "ASIX_CARD",
    currency: "GEL",
    jurisdiction: "GE",
    locale: "ka-GE",
  });
  const timestamp = String(nowEpochSeconds);
  const nonce = "ci-launch-nonce-20261121-0001";
  const request = new Request("https://gateway.asix.example.invalid/provider/v1/launches", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-asix-partner-code": "operator-demo",
    },
    body,
  });
  const canonical = await buildPartnerCanonicalPayload(
    request,
    timestamp,
    nonce,
    new TextEncoder().encode(body),
  );
  const signatureBytes = new Uint8Array(
    await crypto.subtle.sign("HMAC", hmacKey, new TextEncoder().encode(canonical)),
  );
  const headers = new Headers(request.headers);
  headers.set("x-asix-key-id", "key-2026-01");
  headers.set("x-asix-timestamp", timestamp);
  headers.set("x-asix-nonce", nonce);
  headers.set("x-asix-signature", btoa(String.fromCharCode(...signatureBytes)));

  const response = await handler(new Request(request, { headers }));
  const payload = await response.json();

  assertEquals(response.status, 201);
  assertEquals(payload.ok, true);
  assertEquals(payload.policy_version, "policy-7");
  assertEquals(typeof payload.launch_id, "string");
  assertEquals(typeof payload.session_id, "string");
  assertEquals(typeof payload.launch_token, "string");
  assertEquals(payload.launch_token.length >= 40, true);
  assertEquals(
    new URL(payload.launch_url).searchParams.get("session_id"),
    payload.session_id,
  );
  assertEquals(
    new URL(payload.launch_url).searchParams.get("game"),
    "ASIX_CARD",
  );

  const nonceCall = database.calls.find((x) => x.sql.includes("consume_partner_nonce"));
  const launchCall = database.calls.find((x) => x.sql.includes("create_launch_session"));
  assertEquals(!!nonceCall, true);
  assertEquals(!!launchCall, true);
  assertEquals(launchCall?.parameters[1], "key-2026-01");
  assertEquals(launchCall?.parameters[2], "provider-v1");
  assertEquals(launchCall?.parameters[10], 2);
  assertEquals(launchCall?.parameters[12], "policy-7");
  assertEquals(launchCall?.parameters[13] instanceof Uint8Array, true);
  assertEquals(launchCall?.parameters[13] === payload.launch_token, false);
  assertEquals(response.headers.get("access-control-allow-origin"), null);
});

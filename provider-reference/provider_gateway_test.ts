import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildPartnerCanonicalPayload,
  type PartnerKeyResolver,
  type ReplayNonceStore,
} from "./partner_auth.ts";
import { ProviderLaunchService, type PartnerLaunchPolicyResolver, type LaunchTokenStore, type StoredLaunchToken } from "./launch_service.ts";
import { createProviderGateway, type PartnerRequestRateLimiter } from "./provider_gateway.ts";

const secret = new TextEncoder().encode("local-gateway-test-secret-use-only");
const key = await crypto.subtle.importKey("raw", secret, { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
const now = new Date("2026-11-21T08:00:00.000Z");
const nowSec = Math.floor(now.getTime() / 1000);

const keyResolver: PartnerKeyResolver = {
  resolve: async (partnerCode, keyId) => partnerCode === "partner-1" && keyId === "key-1"
    ? { partnerCode, keyId, protocolVersion: "provider-v1", key, active: true }
    : null,
};

class NonceStore implements ReplayNonceStore {
  private used = new Set<string>();
  async consume(partner: string, keyId: string, nonce: string, _expiresAt: number): Promise<boolean> {
    const id = `${partner}:${keyId}:${nonce}`;
    if (this.used.has(id)) return false;
    this.used.add(id);
    return true;
  }
}

class LaunchStore implements LaunchTokenStore {
  rows = new Map<string, StoredLaunchToken>();
  async create(record: StoredLaunchToken): Promise<void> {
    const duplicateSession = [...this.rows.values()].some((row) =>
      row.claims.partnerCode === record.claims.partnerCode &&
      row.claims.partnerSessionRef === record.claims.partnerSessionRef
    );
    if (duplicateSession) throw new Error("PARTNER_SESSION_ALREADY_LAUNCHED");
    this.rows.set(record.tokenHash, record);
  }
  async consumeOnce(hash: string, at: string) {
    const row = this.rows.get(hash);
    if (!row || row.consumedAt || Date.parse(row.claims.expiresAt) <= Date.parse(at)) return null;
    row.consumedAt = at;
    return row.claims;
  }
}

const policyResolver: PartnerLaunchPolicyResolver = {
  resolve: async () => ({
    partnerCode: "partner-1",
    active: true,
    allowedGameCodes: ["ASIX_CARD"],
    allowedCurrencies: ["GEL"],
    allowedJurisdictions: ["GE"],
    allowedLocales: ["ka-GE"],
    launchBaseUrl: "https://games.asix.example.invalid/play",
    tokenTtlSeconds: 60,
    policyVersion: "policy-1",
  }),
};

const validInput = {
  partner_player_ref: "opaque-player",
  partner_session_ref: "operator-session",
  game_code: "ASIX_CARD",
  currency: "GEL",
  jurisdiction: "GE",
  locale: "ka-GE",
};

async function signedRequest(body: unknown, nonce: string): Promise<Request> {
  const text = JSON.stringify(body);
  const request = new Request("https://gateway.asix.example.invalid/provider/v1/launches", {
    method: "POST",
    headers: { "content-type": "application/json", "x-asix-partner-code": "partner-1" },
    body: text,
  });
  const timestamp = String(nowSec);
  const canonical = await buildPartnerCanonicalPayload(
    request, timestamp, nonce, new TextEncoder().encode(text),
  );
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(canonical)));
  const base64 = btoa(String.fromCharCode(...signature));
  const headers = new Headers(request.headers);
  headers.set("x-asix-partner-code", "partner-1");
  headers.set("x-asix-key-id", "key-1");
  headers.set("x-asix-timestamp", timestamp);
  headers.set("x-asix-nonce", nonce);
  headers.set("x-asix-signature", base64);
  return new Request(request, { headers });
}

function makeHandler(rateAllowed = true) {
  const launchStore = new LaunchStore();
  const launchService = new ProviderLaunchService(policyResolver, launchStore, { now: () => now });
  const rateLimiter: PartnerRequestRateLimiter = {
    consume: async () => ({ allowed: rateAllowed, retryAfterSeconds: 3 }),
  };
  return {
    handle: createProviderGateway({
      keyResolver,
      nonceStore: new NonceStore(),
      launchService,
      rateLimiter,
      now: () => now,
      correlationId: () => "corr-test-1",
    }),
    launchStore,
  };
}

Deno.test("valid signed launch returns one-time token and no permissive CORS", async () => {
  const { handle, launchStore } = makeHandler();
  const response = await handle(await signedRequest(validInput, "nonce_gateway_000001"));
  const body = await response.json();
  assertEquals(response.status, 201);
  assertEquals(body.ok, true);
  assertEquals(body.launch_token.length >= 40, true);
  assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(response.headers.get("access-control-allow-origin"), null);
  assertEquals(launchStore.rows.size, 1);
});

Deno.test("invalid signature is rejected before any launch is created", async () => {
  const { handle, launchStore } = makeHandler();
  const request = await signedRequest(validInput, "nonce_gateway_000002");
  const headers = new Headers(request.headers);
  headers.set("x-asix-signature", "A".repeat(44));
  const response = await handle(new Request(request, { headers }));
  assertEquals(response.status, 401);
  assertEquals(launchStore.rows.size, 0);
});

Deno.test("rate limit blocks launch issuance", async () => {
  const { handle, launchStore } = makeHandler(false);
  const response = await handle(await signedRequest(validInput, "nonce_gateway_000003"));
  assertEquals(response.status, 429);
  assertEquals(response.headers.get("retry-after"), "3");
  assertEquals(launchStore.rows.size, 0);
});

Deno.test("malformed JSON is rejected after signed nonce is validated", async () => {
  const { handle } = makeHandler();
  const text = "{bad json";
  const request = new Request("https://gateway.asix.example.invalid/provider/v1/launches", {
    method: "POST",
    body: text,
  });
  const timestamp = String(nowSec);
  const canonical = await buildPartnerCanonicalPayload(
    request, timestamp, "nonce_gateway_000004", new TextEncoder().encode(text),
  );
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(canonical)));
  const headers = new Headers(request.headers);
  headers.set("x-asix-key-id", "key-1");
  headers.set("x-asix-timestamp", timestamp);
  headers.set("x-asix-nonce", "nonce_gateway_000004");
  headers.set("x-asix-signature", btoa(String.fromCharCode(...signature)));
  const response = await handle(new Request(request, { headers }));
  assertEquals(response.status, 400);
});

Deno.test("unrecognized path is not exposed by partner gateway", async () => {
  const { handle } = makeHandler();
  const response = await handle(new Request("https://gateway.asix.example.invalid/provider/v1/unknown", {
    method: "POST",
  }));
  assertEquals(response.status, 404);
});

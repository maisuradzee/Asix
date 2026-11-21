import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildPartnerCanonicalPayload,
  verifyPartnerRequest,
  type PartnerKeyResolver,
  type ReplayNonceStore,
} from "./partner_auth.ts";

const testSecret = new TextEncoder().encode("local-test-secret-never-use-in-production");
const partnerKey = await crypto.subtle.importKey(
  "raw",
  testSecret,
  { name: "HMAC", hash: "SHA-256" },
  false,
  ["sign", "verify"],
);
const now = 1_795_248_000; // fixed test timestamp

function keyResolver(active = true): PartnerKeyResolver {
  return {
    resolve: async (keyId) => keyId === "sandbox-key-01"
      ? { partnerCode: "operator-sandbox", keyId, protocolVersion: "provider-v1", key: partnerKey, active }
      : null,
  };
}

class MemoryNonceStore implements ReplayNonceStore {
  private readonly used = new Set<string>();
  async consume(partnerCode: string, nonce: string): Promise<boolean> {
    const key = `${partnerCode}:${nonce}`;
    if (this.used.has(key)) return false;
    this.used.add(key);
    return true;
  }
}

async function signedRequest(options: {
  path?: string;
  body?: string;
  timestamp?: string;
  nonce?: string;
} = {}): Promise<Request> {
  const path = options.path ?? "/provider/v1/launches?game=ASIX_CARD";
  const body = options.body ?? JSON.stringify({ player: "opaque-1", currency: "GEL" });
  const timestamp = options.timestamp ?? String(now);
  const nonce = options.nonce ?? "nonce_value_123456789";
  const request = new Request(`https://provider-sandbox.example.invalid${path}`, {
    method: "POST",
    body,
  });
  const canonical = await buildPartnerCanonicalPayload(
    request,
    timestamp,
    nonce,
    new TextEncoder().encode(body),
  );
  const signature = new Uint8Array(await crypto.subtle.sign(
    "HMAC",
    partnerKey,
    new TextEncoder().encode(canonical),
  ));
  const base64 = btoa(String.fromCharCode(...signature));
  const headers = new Headers(request.headers);
  headers.set("x-asix-key-id", "sandbox-key-01");
  headers.set("x-asix-timestamp", timestamp);
  headers.set("x-asix-nonce", nonce);
  headers.set("x-asix-signature", base64);
  return new Request(request, { headers });
}

Deno.test("valid HMAC signature is accepted and resolves trusted partner identity", async () => {
  const request = await signedRequest();
  const result = await verifyPartnerRequest(
    request,
    keyResolver(),
    new MemoryNonceStore(),
    { nowEpochSeconds: now },
  );
  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.partnerCode, "operator-sandbox");
    assertEquals(result.protocolVersion, "provider-v1");
  }
});

Deno.test("replayed nonce is rejected", async () => {
  const store = new MemoryNonceStore();
  const request = await signedRequest();
  const replayRequest = await signedRequest();
  const first = await verifyPartnerRequest(request, keyResolver(), store, { nowEpochSeconds: now });
  const second = await verifyPartnerRequest(replayRequest, keyResolver(), store, { nowEpochSeconds: now });
  assertEquals(first.ok, true);
  assertEquals(second.ok, false);
  if (!second.ok) assertEquals(second.error, "REPLAY_DETECTED");
});

Deno.test("tampered request body fails signature verification", async () => {
  const original = await signedRequest();
  const altered = new Request(original.url, {
    method: "POST",
    headers: original.headers,
    body: JSON.stringify({ player: "opaque-1", currency: "USD" }),
  });
  const result = await verifyPartnerRequest(
    altered,
    keyResolver(),
    new MemoryNonceStore(),
    { nowEpochSeconds: now },
  );
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.error, "SIGNATURE_INVALID");
});

Deno.test("expired timestamp and revoked key are rejected", async () => {
  const expired = await signedRequest({ timestamp: String(now - 1_000) });
  const expiredResult = await verifyPartnerRequest(
    expired, keyResolver(), new MemoryNonceStore(), { nowEpochSeconds: now },
  );
  assertEquals(expiredResult.ok, false);
  if (!expiredResult.ok) assertEquals(expiredResult.error, "REQUEST_EXPIRED");

  const revoked = await signedRequest();
  const revokedResult = await verifyPartnerRequest(
    revoked, keyResolver(false), new MemoryNonceStore(), { nowEpochSeconds: now },
  );
  assertEquals(revokedResult.ok, false);
  if (!revokedResult.ok) assertEquals(revokedResult.error, "KEY_UNKNOWN_OR_REVOKED");
});

Deno.test("oversized body is rejected before signature processing", async () => {
  const request = await signedRequest({ body: "x".repeat(100) });
  const result = await verifyPartnerRequest(
    request,
    keyResolver(),
    new MemoryNonceStore(),
    { nowEpochSeconds: now, maxBodyBytes: 32 },
  );
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.error, "BODY_TOO_LARGE");
});

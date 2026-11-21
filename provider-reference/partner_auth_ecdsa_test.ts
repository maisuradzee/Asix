import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  ecdsaDerToP1363,
  verifyEcdsaPayloadRequest,
  type EcdsaPartnerKeyResolver,
} from "./partner_auth_ecdsa.ts";

const pair = await crypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);
const keyResolver: EcdsaPartnerKeyResolver = {
  resolve: async (partnerCode) => partnerCode === "st8-sandbox"
    ? {
      partnerCode,
      keyId: "st8-public-key-01",
      protocolVersion: "st8-operator-v1-reference",
      publicKey: pair.publicKey,
      active: true,
    }
    : null,
};

function lengthDer(length: number): number[] {
  if (length < 0x80) return [length];
  if (length < 0x100) return [0x81, length];
  return [0x82, (length >> 8) & 0xff, length & 0xff];
}

function integerDer(value: Uint8Array): number[] {
  let i = 0;
  while (i < value.length - 1 && value[i] === 0) i++;
  let bytes = Array.from(value.slice(i));
  if ((bytes[0] & 0x80) !== 0) bytes = [0, ...bytes];
  return [0x02, ...lengthDer(bytes.length), ...bytes];
}

function p1363ToDer(signature: Uint8Array): Uint8Array {
  const r = integerDer(signature.slice(0, 32));
  const s = integerDer(signature.slice(32, 64));
  const body = [...r, ...s];
  return new Uint8Array([0x30, ...lengthDer(body.length), ...body]);
}

async function signPayload(payload: Uint8Array): Promise<string> {
  const raw = new Uint8Array(await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    pair.privateKey,
    payload,
  ));
  const der = p1363ToDer(raw);
  return btoa(String.fromCharCode(...der));
}

Deno.test("valid ECDSA DER signature for POST raw body is accepted", async () => {
  const body = JSON.stringify({ transaction_id: "tx-1", amount: "1.25", currency: "GEL" });
  const payload = new TextEncoder().encode(body);
  const signature = await signPayload(payload);
  const request = new Request("https://asix.example.invalid/callback/st8/debit", {
    method: "POST",
    headers: { "content-type": "application/json", "x-st8-sign": signature },
    body,
  });
  const result = await verifyEcdsaPayloadRequest(request, "st8-sandbox", keyResolver);
  assertEquals(result.ok, true);
  if (result.ok) {
    assertEquals(result.partnerCode, "st8-sandbox");
    assertEquals(result.keyId, "st8-public-key-01");
    assertEquals(new TextDecoder().decode(result.body), body);
  }
});

Deno.test("valid ECDSA signature for encoded GET query is accepted", async () => {
  const query = "transaction_id=tx%2F1&site=demo";
  const signature = await signPayload(new TextEncoder().encode(query));
  const request = new Request(`https://asix.example.invalid/callback/st8/status?${query}`, {
    method: "GET",
    headers: { "x-st8-sign": signature },
  });
  const result = await verifyEcdsaPayloadRequest(request, "st8-sandbox", keyResolver);
  assertEquals(result.ok, true);
  if (result.ok) assertEquals(new TextDecoder().decode(result.signedPayload), query);
});

Deno.test("altered full request body is rejected", async () => {
  const original = JSON.stringify({ transaction_id: "tx-2", amount: "1.25" });
  const signature = await signPayload(new TextEncoder().encode(original));
  const tampered = JSON.stringify({ transaction_id: "tx-2", amount: "999.00" });
  const request = new Request("https://asix.example.invalid/callback/st8/debit", {
    method: "POST",
    headers: { "x-st8-sign": signature },
    body: tampered,
  });
  const result = await verifyEcdsaPayloadRequest(request, "st8-sandbox", keyResolver);
  assertEquals(result.ok, false);
  if (!result.ok) assertEquals(result.error, "SIGNATURE_INVALID");
});

Deno.test("unknown partner, inactive key and unsupported method are rejected", async () => {
  const signed = await signPayload(new TextEncoder().encode("test"));
  const unknown = await verifyEcdsaPayloadRequest(
    new Request("https://asix.example.invalid/x", { method: "POST", headers: { "x-st8-sign": signed }, body: "test" }),
    "unknown",
    keyResolver,
  );
  assertEquals(unknown.ok, false);
  if (!unknown.ok) assertEquals(unknown.error, "KEY_UNKNOWN_OR_REVOKED");

  const put = await verifyEcdsaPayloadRequest(
    new Request("https://asix.example.invalid/x", { method: "PUT", headers: { "x-st8-sign": signed }, body: "test" }),
    "st8-sandbox",
    keyResolver,
  );
  assertEquals(put.ok, false);
  if (!put.ok) assertEquals(put.error, "METHOD_NOT_SUPPORTED");
});

Deno.test("malformed DER signature and oversized body are rejected", async () => {
  const malformed = new Request("https://asix.example.invalid/x", {
    method: "POST",
    headers: { "x-st8-sign": btoa("bad-der-signature") },
    body: "test",
  });
  const malformedResult = await verifyEcdsaPayloadRequest(malformed, "st8-sandbox", keyResolver);
  assertEquals(malformedResult.ok, false);

  const signature = await signPayload(new TextEncoder().encode("123456"));
  const oversized = new Request("https://asix.example.invalid/x", {
    method: "POST",
    headers: { "x-st8-sign": signature },
    body: "123456",
  });
  const oversizedResult = await verifyEcdsaPayloadRequest(
    oversized,
    "st8-sandbox",
    keyResolver,
    { maxPayloadBytes: 4 },
  );
  assertEquals(oversizedResult.ok, false);
  if (!oversizedResult.ok) assertEquals(oversizedResult.error, "PAYLOAD_TOO_LARGE");
});

Deno.test("DER converter rejects malformed lengths and invalid integers", () => {
  assertEquals(ecdsaDerToP1363(new Uint8Array([0x30, 0x01, 0x00])), null);
  assertEquals(ecdsaDerToP1363(new Uint8Array([0x30, 0x06, 0x02, 0x01, 0x80, 0x02, 0x01, 0x01])), null);
});

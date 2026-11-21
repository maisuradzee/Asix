/**
 * ECDSA P-256 / SHA-256 payload-signature verifier reference.
 *
 * This profile is intended for partners whose official protocol signs the
 * exact POST body or encoded GET query string with ECDSA and sends a DER-encoded
 * Base64 signature (for example, the publicly documented ST8 Operator API).
 *
 * It is NOT the same as ASIX's own HMAC profile. It deliberately adds no
 * invented timestamp/nonce headers. Use partner-specific idempotency,
 * endpoint scoping, TLS and network controls required by the actual contract.
 */

export interface EcdsaPartnerKey {
  partnerCode: string;
  keyId: string;
  protocolVersion: string;
  publicKey: CryptoKey;
  active: boolean;
}

export interface EcdsaPartnerKeyResolver {
  resolve(partnerCode: string): Promise<EcdsaPartnerKey | null>;
}

export type EcdsaVerificationResult =
  | {
    ok: true;
    partnerCode: string;
    keyId: string;
    protocolVersion: string;
    body: Uint8Array;
    signedPayload: Uint8Array;
  }
  | {
    ok: false;
    error:
      | "PARTNER_SCOPE_MISSING"
      | "SIGNATURE_MISSING"
      | "KEY_UNKNOWN_OR_REVOKED"
      | "METHOD_NOT_SUPPORTED"
      | "PAYLOAD_TOO_LARGE"
      | "SIGNATURE_FORMAT_INVALID"
      | "SIGNATURE_INVALID"
      | "KEY_ALGORITHM_INVALID";
  };

export interface EcdsaVerifierOptions {
  signatureHeader?: string;
  maxPayloadBytes?: number;
}

function readDerLength(bytes: Uint8Array, offset: number): { length: number; next: number } | null {
  if (offset >= bytes.length) return null;
  const first = bytes[offset];
  if (first < 0x80) return { length: first, next: offset + 1 };

  const count = first & 0x7f;
  if (count < 1 || count > 2 || offset + 1 + count > bytes.length) return null;
  if (bytes[offset + 1] === 0) return null;

  let length = 0;
  for (let i = 0; i < count; i++) length = (length << 8) | bytes[offset + 1 + i];
  if (length < 0x80) return null; // DER must use the short form when possible.
  return { length, next: offset + 1 + count };
}

function readDerInteger(bytes: Uint8Array, offset: number): { value: Uint8Array; next: number } | null {
  if (offset >= bytes.length || bytes[offset] !== 0x02) return null;
  const size = readDerLength(bytes, offset + 1);
  if (!size || size.length < 1 || size.next + size.length > bytes.length) return null;

  let value = bytes.slice(size.next, size.next + size.length);
  // ASN.1 INTEGER is signed; ECDSA r/s must be positive. A leading zero is
  // only permitted to prevent the high bit from indicating a negative value.
  if ((value[0] & 0x80) !== 0) return null;
  if (value.length > 1 && value[0] === 0) {
    if ((value[1] & 0x80) === 0) return null; // non-minimal positive integer
    value = value.slice(1);
  }
  if (value.length < 1 || value.length > 32) return null;
  return { value, next: size.next + size.length };
}

export function ecdsaDerToP1363(signature: Uint8Array): Uint8Array | null {
  if (signature.length < 8 || signature[0] !== 0x30) return null;
  const sequence = readDerLength(signature, 1);
  if (!sequence || sequence.next + sequence.length !== signature.length) return null;

  const r = readDerInteger(signature, sequence.next);
  if (!r) return null;
  const s = readDerInteger(signature, r.next);
  if (!s || s.next !== signature.length) return null;

  const raw = new Uint8Array(64);
  raw.set(r.value, 32 - r.value.length);
  raw.set(s.value, 64 - s.value.length);
  return raw;
}

function decodeBase64(value: string): Uint8Array | null {
  try {
    const decoded = atob(value);
    return Uint8Array.from(decoded, (char) => char.charCodeAt(0));
  } catch {
    return null;
  }
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

async function readBoundedBody(request: Request, maximum: number): Promise<Uint8Array | null> {
  const declared = request.headers.get("content-length");
  if (declared && /^[0-9]+$/.test(declared) && Number(declared) > maximum) return null;

  const stream = request.body;
  if (!stream) return new Uint8Array(0);

  const reader = stream.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const item = await reader.read();
      if (item.done) break;
      total += item.value.byteLength;
      if (total > maximum) {
        await reader.cancel();
        return null;
      }
      chunks.push(item.value);
    }
  } finally {
    reader.releaseLock();
  }

  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

export async function verifyEcdsaPayloadRequest(
  request: Request,
  trustedPartnerCode: string,
  keyResolver: EcdsaPartnerKeyResolver,
  options: EcdsaVerifierOptions = {},
): Promise<EcdsaVerificationResult> {
  if (!trustedPartnerCode || trustedPartnerCode.length > 128) {
    return { ok: false, error: "PARTNER_SCOPE_MISSING" };
  }

  const signatureHeader = options.signatureHeader ?? "x-st8-sign";
  const signatureText = request.headers.get(signatureHeader) || "";
  if (!signatureText || signatureText.length > 256) {
    return { ok: false, error: "SIGNATURE_MISSING" };
  }

  const key = await keyResolver.resolve(trustedPartnerCode);
  if (!key || !key.active || key.partnerCode !== trustedPartnerCode) {
    return { ok: false, error: "KEY_UNKNOWN_OR_REVOKED" };
  }
  if (key.publicKey.algorithm.name !== "ECDSA" ||
      (key.publicKey.algorithm as EcKeyAlgorithm).namedCurve !== "P-256") {
    return { ok: false, error: "KEY_ALGORITHM_INVALID" };
  }

  let payload: Uint8Array;
  let body = new Uint8Array(0);
  const maxPayloadBytes = options.maxPayloadBytes ?? 512 * 1024;
  if (!Number.isInteger(maxPayloadBytes) || maxPayloadBytes < 1 || maxPayloadBytes > 2 * 1024 * 1024) {
    throw new Error("INVALID_ECDSA_PAYLOAD_LIMIT");
  }

  if (request.method.toUpperCase() === "POST") {
    const read = await readBoundedBody(request, maxPayloadBytes);
    if (read === null) return { ok: false, error: "PAYLOAD_TOO_LARGE" };
    body = new Uint8Array(read.byteLength);
    body.set(read);
    payload = body;
  } else if (request.method.toUpperCase() === "GET") {
    const query = new URL(request.url).search.slice(1);
    payload = new TextEncoder().encode(query);
    if (payload.byteLength > maxPayloadBytes) {
      return { ok: false, error: "PAYLOAD_TOO_LARGE" };
    }
  } else {
    return { ok: false, error: "METHOD_NOT_SUPPORTED" };
  }

  const derSignature = decodeBase64(signatureText);
  if (!derSignature) return { ok: false, error: "SIGNATURE_FORMAT_INVALID" };
  const p1363Signature = ecdsaDerToP1363(derSignature);
  if (!p1363Signature) return { ok: false, error: "SIGNATURE_FORMAT_INVALID" };

  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key.publicKey,
    toArrayBuffer(p1363Signature),
    toArrayBuffer(payload),
  );
  if (!valid) return { ok: false, error: "SIGNATURE_INVALID" };

  return {
    ok: true,
    partnerCode: key.partnerCode,
    keyId: key.keyId,
    protocolVersion: key.protocolVersion,
    body,
    signedPayload: payload,
  };
}

/**
 * ASIX partner request signature verification reference.
 *
 * Security boundary:
 * - key resolver supplies a managed CryptoKey and trusted partner identity;
 * - nonce store must enforce atomic uniqueness in durable shared storage;
 * - no secret is read from browser input or hard-coded in this module.
 *
 * Not connected to production routes.
 */

export interface ResolvedPartnerKey {
  partnerCode: string;
  keyId: string;
  key: CryptoKey;
  active: boolean;
}

export interface PartnerKeyResolver {
  resolve(keyId: string): Promise<ResolvedPartnerKey | null>;
}

export interface ReplayNonceStore {
  /**
   * Must atomically insert (partnerCode, nonce) with expiry.
   * Return false if the pair already exists.
   */
  consume(partnerCode: string, nonce: string, expiresAt: number): Promise<boolean>;
}

export interface PartnerSignatureOptions {
  nowEpochSeconds?: number;
  maxClockSkewSeconds?: number;
  maxBodyBytes?: number;
}

export type PartnerSignatureResult =
  | { ok: true; partnerCode: string; keyId: string; body: Uint8Array; nonce: string }
  | {
    ok: false;
    error:
      | "SIGNATURE_HEADERS_MISSING"
      | "KEY_UNKNOWN_OR_REVOKED"
      | "TIMESTAMP_INVALID"
      | "REQUEST_EXPIRED"
      | "NONCE_INVALID"
      | "BODY_TOO_LARGE"
      | "SIGNATURE_INVALID"
      | "REPLAY_DETECTED";
  };

const encoder = new TextEncoder();

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function decodeBase64(value: string): Uint8Array | null {
  try {
    const decoded = atob(value);
    return Uint8Array.from(decoded, (char) => char.charCodeAt(0));
  } catch {
    return null;
  }
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", toArrayBuffer(bytes));
  return toHex(new Uint8Array(digest));
}

async function readBodyBounded(request: Request, maxBodyBytes: number): Promise<Uint8Array | null> {
  const declaredLength = request.headers.get("content-length");
  if (declaredLength !== null && /^[0-9]+$/.test(declaredLength)) {
    if (Number(declaredLength) > maxBodyBytes) return null;
  }

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
      if (total > maxBodyBytes) {
        await reader.cancel();
        return null;
      }
      chunks.push(item.value);
    }
  } finally {
    reader.releaseLock();
  }

  const output = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return output;
}

/**
 * Canonical signed payload:
 * METHOD\nPATH_AND_QUERY\nTIMESTAMP_SECONDS\nNONCE\nSHA256_BODY_HEX
 *
 * The partner must use the exact raw HTTP body bytes and exact request path +
 * query string. Query parameter order is therefore part of the signature.
 */
export async function buildPartnerCanonicalPayload(
  request: Request,
  timestamp: string,
  nonce: string,
  body: Uint8Array,
): Promise<string> {
  const url = new URL(request.url);
  const digest = await sha256Hex(body);
  return [
    request.method.toUpperCase(),
    url.pathname + url.search,
    timestamp,
    nonce,
    digest,
  ].join("\n");
}

export async function verifyPartnerRequest(
  request: Request,
  keyResolver: PartnerKeyResolver,
  nonceStore: ReplayNonceStore,
  options: PartnerSignatureOptions = {},
): Promise<PartnerSignatureResult> {
  const keyId = request.headers.get("x-asix-key-id") || "";
  const timestamp = request.headers.get("x-asix-timestamp") || "";
  const nonce = request.headers.get("x-asix-nonce") || "";
  const signatureText = request.headers.get("x-asix-signature") || "";

  if (!keyId || keyId.length > 128 || !timestamp || !nonce || !signatureText) {
    return { ok: false, error: "SIGNATURE_HEADERS_MISSING" };
  }

  const resolved = await keyResolver.resolve(keyId);
  if (!resolved || !resolved.active || resolved.keyId !== keyId) {
    return { ok: false, error: "KEY_UNKNOWN_OR_REVOKED" };
  }

  if (!/^[0-9]{10}$/.test(timestamp)) {
    return { ok: false, error: "TIMESTAMP_INVALID" };
  }
  const timestampSeconds = Number(timestamp);
  const now = options.nowEpochSeconds ?? Math.floor(Date.now() / 1000);
  const maxClockSkew = options.maxClockSkewSeconds ?? 300;
  if (!Number.isInteger(maxClockSkew) || maxClockSkew < 1 || maxClockSkew > 900) {
    throw new Error("INVALID_CLOCK_SKEW_CONFIGURATION");
  }
  if (!Number.isSafeInteger(now) || Math.abs(now - timestampSeconds) > maxClockSkew) {
    return { ok: false, error: "REQUEST_EXPIRED" };
  }

  if (!/^[A-Za-z0-9_-]{16,128}$/.test(nonce)) {
    return { ok: false, error: "NONCE_INVALID" };
  }

  const maxBodyBytes = options.maxBodyBytes ?? 512 * 1024;
  if (!Number.isInteger(maxBodyBytes) || maxBodyBytes < 1 || maxBodyBytes > 2 * 1024 * 1024) {
    throw new Error("INVALID_BODY_LIMIT_CONFIGURATION");
  }
  const bodyBuffer = await readBodyBounded(request, maxBodyBytes);
  if (bodyBuffer === null) return { ok: false, error: "BODY_TOO_LARGE" };

  if (signatureText.length !== 44) {
    return { ok: false, error: "SIGNATURE_INVALID" };
  }
  const signature = decodeBase64(signatureText);
  if (!signature || signature.byteLength !== 32) {
    return { ok: false, error: "SIGNATURE_INVALID" };
  }

  const canonical = await buildPartnerCanonicalPayload(request, timestamp, nonce, bodyBuffer);
  const valid = await crypto.subtle.verify(
    "HMAC",
    resolved.key,
    toArrayBuffer(signature),
    toArrayBuffer(encoder.encode(canonical)),
  );
  if (!valid) return { ok: false, error: "SIGNATURE_INVALID" };

  // Consume nonce only after signature validation. The store must be shared
  // across all gateway instances and enforce unique(partner_code, nonce).
  const consumed = await nonceStore.consume(
    resolved.partnerCode,
    nonce,
    timestampSeconds + maxClockSkew + 1,
  );
  if (!consumed) return { ok: false, error: "REPLAY_DETECTED" };

  return {
    ok: true,
    partnerCode: resolved.partnerCode,
    keyId,
    body: bodyBuffer,
    nonce,
  };
}

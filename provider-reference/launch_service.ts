/**
 * ASIX provider launch/session issuance reference.
 *
 * Only call issueLaunch after partner HMAC authentication has produced a
 * VerifiedPartnerContext. The token store must be durable and atomic in
 * production. Only token hashes are persisted.
 */

export interface VerifiedPartnerContext {
  partnerCode: string;
  keyId: string;
  protocolVersion: string;
}

export interface LaunchRequestInput {
  partnerPlayerRef: string;
  partnerSessionRef: string;
  gameCode: string;
  currency: string;
  jurisdiction: string;
  locale: string;
}

export interface PartnerLaunchPolicy {
  partnerCode: string;
  active: boolean;
  allowedGameCodes: string[];
  allowedCurrencies: string[];
  allowedJurisdictions: string[];
  allowedLocales: string[];
  launchBaseUrl: string;
  tokenTtlSeconds: number;
  policyVersion: string;
}

export interface LaunchClaims {
  launchId: string;
  sessionId: string;
  partnerCode: string;
  partnerPlayerRef: string;
  partnerSessionRef: string;
  gameCode: string;
  currency: string;
  jurisdiction: string;
  locale: string;
  keyId: string;
  protocolVersion: string;
  policyVersion: string;
  issuedAt: string;
  expiresAt: string;
}

export interface StoredLaunchToken {
  tokenHash: string;
  claims: LaunchClaims;
  consumedAt?: string;
}

export class PartnerSessionConflictError extends Error {
  constructor() {
    super("PARTNER_SESSION_ALREADY_LAUNCHED");
    this.name = "PartnerSessionConflictError";
  }
}

export interface LaunchTokenStore {
  /**
   * Must be durable. Enforce unique token_hash and unique
   * (partner_code, partner_session_ref) for active/issued sessions.
   * Duplicate session references throw PartnerSessionConflictError.
   */
  create(record: StoredLaunchToken): Promise<LaunchClaims | void>;

  /**
   * Must atomically mark consumed and return claims only once when
   * consumed_at IS NULL and expires_at > now.
   */
  consumeOnce(tokenHash: string, now: string): Promise<LaunchClaims | null>;
}

export interface PartnerLaunchPolicyResolver {
  resolve(partnerCode: string): Promise<PartnerLaunchPolicy | null>;
}

export interface LaunchServiceOptions {
  now?: () => Date;
  tokenTtlSeconds?: number;
}

export interface LaunchIssueResult {
  launchId: string;
  sessionId: string;
  launchUrl: string;
  launchToken: string;
  expiresAt: string;
  policyVersion: string;
}

export class LaunchRejectedError extends Error {
  constructor(code: string) {
    super(code);
    this.name = "LaunchRejectedError";
  }
}

function isBoundedText(value: unknown, max: number): value is string {
  return typeof value === "string" && value.trim().length > 0 && value.length <= max;
}

function validateInput(input: LaunchRequestInput): void {
  if (!isBoundedText(input.partnerPlayerRef, 200) ||
      !isBoundedText(input.partnerSessionRef, 200) ||
      !isBoundedText(input.gameCode, 80) ||
      !/^[A-Z]{3}$/.test(input.currency) ||
      !/^[A-Z0-9_-]{2,8}$/.test(input.jurisdiction) ||
      !/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/.test(input.locale)) {
    throw new LaunchRejectedError("INVALID_LAUNCH_CONTEXT");
  }
}

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    toArrayBuffer(new TextEncoder().encode(token)),
  );
  const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `sha256:${hex}`;
}

function makeOpaqueToken(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64Url(bytes);
}

export class ProviderLaunchService {
  private readonly now: () => Date;
  private readonly configuredTtl?: number;

  constructor(
    private readonly policies: PartnerLaunchPolicyResolver,
    private readonly tokens: LaunchTokenStore,
    options: LaunchServiceOptions = {},
  ) {
    this.now = options.now ?? (() => new Date());
    this.configuredTtl = options.tokenTtlSeconds;
    if (this.configuredTtl !== undefined &&
        (!Number.isInteger(this.configuredTtl) || this.configuredTtl < 15 || this.configuredTtl > 300)) {
      throw new Error("INVALID_LAUNCH_TOKEN_TTL");
    }
  }

  async issueLaunch(
    partner: VerifiedPartnerContext,
    input: LaunchRequestInput,
  ): Promise<LaunchIssueResult> {
    if (!isBoundedText(partner.partnerCode, 128) ||
        !isBoundedText(partner.keyId, 128) ||
        !isBoundedText(partner.protocolVersion, 64)) {
      throw new LaunchRejectedError("INVALID_VERIFIED_PARTNER_CONTEXT");
    }
    validateInput(input);

    const policy = await this.policies.resolve(partner.partnerCode);
    if (!policy || !policy.active || policy.partnerCode !== partner.partnerCode) {
      throw new LaunchRejectedError("PARTNER_INACTIVE");
    }
    if (!policy.allowedGameCodes.includes(input.gameCode)) {
      throw new LaunchRejectedError("GAME_NOT_ENABLED");
    }
    if (!policy.allowedCurrencies.includes(input.currency)) {
      throw new LaunchRejectedError("CURRENCY_NOT_ALLOWED");
    }
    if (!policy.allowedJurisdictions.includes(input.jurisdiction)) {
      throw new LaunchRejectedError("JURISDICTION_NOT_ALLOWED");
    }
    if (!policy.allowedLocales.includes(input.locale)) {
      throw new LaunchRejectedError("LOCALE_NOT_ALLOWED");
    }

    const base = new URL(policy.launchBaseUrl);
    if (base.protocol !== "https:" || base.username || base.password ||
        base.search || base.hash) {
      throw new LaunchRejectedError("INVALID_TRUSTED_LAUNCH_BASE_URL");
    }

    const ttl = this.configuredTtl ?? policy.tokenTtlSeconds;
    if (!Number.isInteger(ttl) || ttl < 15 || ttl > 300) {
      throw new LaunchRejectedError("INVALID_PARTNER_LAUNCH_TTL");
    }

    const issued = this.now();
    if (!Number.isFinite(issued.getTime())) throw new Error("INVALID_SYSTEM_CLOCK");
    const expires = new Date(issued.getTime() + ttl * 1000);
    const launchId = crypto.randomUUID();
    const sessionId = crypto.randomUUID();
    const token = makeOpaqueToken();

    const claims: LaunchClaims = {
      launchId,
      sessionId,
      partnerCode: partner.partnerCode,
      partnerPlayerRef: input.partnerPlayerRef,
      partnerSessionRef: input.partnerSessionRef,
      gameCode: input.gameCode,
      currency: input.currency,
      jurisdiction: input.jurisdiction,
      locale: input.locale,
      keyId: partner.keyId,
      protocolVersion: partner.protocolVersion,
      policyVersion: policy.policyVersion,
      issuedAt: issued.toISOString(),
      expiresAt: expires.toISOString(),
    };

    const tokenHash = await hashToken(token);
    let persistedClaims: LaunchClaims | void;
    try {
      persistedClaims = await this.tokens.create({ tokenHash, claims });
    } catch (error) {
      if (error instanceof PartnerSessionConflictError ||
          (error instanceof Error && error.message === "PARTNER_SESSION_ALREADY_LAUNCHED")) {
        throw new LaunchRejectedError("PARTNER_SESSION_ALREADY_LAUNCHED");
      }
      throw error;
    }

    // A durable repository may return the canonical existing session ID when
    // an idempotent partner retry reissues a token for a CREATED session.
    const finalClaims = persistedClaims ?? claims;
    const launchUrl = new URL(base.toString());
    launchUrl.searchParams.set("session_id", finalClaims.sessionId);
    launchUrl.searchParams.set("game", input.gameCode);

    return {
      launchId: finalClaims.launchId,
      sessionId: finalClaims.sessionId,
      launchUrl: launchUrl.toString(),
      launchToken: token,
      expiresAt: finalClaims.expiresAt,
      policyVersion: finalClaims.policyVersion,
    };
  }

  async consumeLaunchToken(token: string): Promise<LaunchClaims> {
    if (!isBoundedText(token, 256) || token.length < 40) {
      throw new LaunchRejectedError("INVALID_LAUNCH_TOKEN");
    }
    const tokenHash = await hashToken(token);
    const claims = await this.tokens.consumeOnce(tokenHash, this.now().toISOString());
    if (!claims) throw new LaunchRejectedError("TOKEN_EXPIRED_OR_ALREADY_USED");
    return claims;
  }
}

/**
 * Durable gateway adapters for the proposed provider_internal PostgreSQL
 * functions. This module never opens a database connection or reads secrets.
 *
 * Composition supplies:
 * - a dedicated provider_runtime PostgreSQL executor;
 * - a managed HMAC key provider backed by KMS/Secrets Manager;
 * - a versioned currency exponent registry.
 *
 * Raw HMAC bytes and launch tokens are never stored by these adapters.
 */
import type {
  PartnerKeyResolver,
  ResolvedPartnerKey,
  ReplayNonceStore,
} from "./partner_auth.ts";
import type {
  LaunchClaims,
  LaunchTokenStore,
  StoredLaunchToken,
} from "./launch_service.ts";
import {
  LaunchRejectedError,
  PartnerSessionConflictError,
} from "./launch_service.ts";
import {
  ProviderDatabaseError,
  ProviderPostgresRepository,
  type PartnerKeyMetadata,
} from "./postgres_repository.ts";

export interface ManagedHmacKeyProvider {
  /**
   * Resolve a non-exportable WebCrypto HMAC key using the secret reference.
   * Implement this via the deployment's KMS/Secrets Manager adapter.
   */
  resolveHmacCryptoKey(input: {
    secretReference: string;
    partnerCode: string;
    keyId: string;
    protocolVersion: string;
  }): Promise<CryptoKey | null>;
}

export interface CurrencyExponentRegistry {
  /** Return the ISO/currency-registry minor-unit exponent, or null if unknown. */
  resolveExponent(currency: string): number | null | Promise<number | null>;
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function decodeSha256TokenHash(value: string): Uint8Array {
  const match = /^sha256:([0-9a-f]{64})$/.exec(value);
  if (!match) throw new ProviderDatabaseError("INVALID_STORED_LAUNCH_TOKEN_HASH");
  const hex = match[1];
  const bytes = new Uint8Array(32);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

function encodeSha256Bytes(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

/**
 * Resolves one partner's HMAC signing key by (partner_code, key_id).
 * Database metadata provides only a secret reference; the actual CryptoKey
 * is obtained from the injected secret provider and remains non-exportable.
 */
export class PostgresPartnerKeyResolver implements PartnerKeyResolver {
  constructor(
    private readonly repository: ProviderPostgresRepository,
    private readonly managedKeys: ManagedHmacKeyProvider,
  ) {}

  async resolve(partnerCode: string, keyId: string): Promise<ResolvedPartnerKey | null> {
    const metadata = await this.repository.resolvePartnerKey(partnerCode, keyId);
    if (!metadata || metadata.partner_code !== partnerCode || metadata.key_id !== keyId ||
        metadata.auth_profile !== "ASIX_HMAC_SHA256_V1" || !metadata.secret_reference) {
      return null;
    }

    const key = await this.managedKeys.resolveHmacCryptoKey({
      secretReference: metadata.secret_reference,
      partnerCode: metadata.partner_code,
      keyId: metadata.key_id,
      protocolVersion: metadata.protocol_version,
    });
    if (!key || key.type !== "secret" || key.algorithm.name !== "HMAC" ||
        !key.usages.includes("verify")) {
      return null;
    }

    return {
      partnerCode: metadata.partner_code,
      keyId: metadata.key_id,
      protocolVersion: metadata.protocol_version,
      key,
      active: true,
    };
  }
}

/**
 * Durable nonce replay guard. Nonces are hashed before reaching PostgreSQL
 * and are unique within the exact partner + signing-key scope.
 */
export class PostgresReplayNonceStore implements ReplayNonceStore {
  constructor(private readonly repository: ProviderPostgresRepository) {}

  async consume(
    partnerCode: string,
    keyId: string,
    nonce: string,
    expiresAtEpochSeconds: number,
  ): Promise<boolean> {
    if (!partnerCode || !keyId || !nonce ||
        !Number.isSafeInteger(expiresAtEpochSeconds) || expiresAtEpochSeconds <= 0) {
      return false;
    }
    const metadata = await this.repository.resolvePartnerKey(partnerCode, keyId);
    if (!metadata || metadata.partner_id.length === 0) return false;

    const digest = await crypto.subtle.digest("SHA-256", encodeSha256Bytes(nonce));
    const nonceHash = new Uint8Array(digest);
    const expiresAt = new Date(expiresAtEpochSeconds * 1000);
    if (!Number.isFinite(expiresAt.getTime())) return false;

    return this.repository.consumePartnerNonce({
      partnerId: metadata.partner_id,
      keyId: metadata.key_id,
      nonceHash,
      expiresAt: expiresAt.toISOString(),
    });
  }
}

/**
 * Durable LaunchTokenStore. LaunchService creates a random raw token in memory,
 * then passes only its SHA-256 digest and immutable claims into this adapter.
 * PostgreSQL generates/activates the canonical session state and reconstructs
 * all claims on consumption.
 */
export class PostgresLaunchTokenStore implements LaunchTokenStore {
  constructor(
    private readonly repository: ProviderPostgresRepository,
    private readonly currencies: CurrencyExponentRegistry,
  ) {}

  async create(record: StoredLaunchToken): Promise<LaunchClaims> {
    const { claims } = record;
    if (!isUuid(claims.launchId) || !isUuid(claims.sessionId)) {
      throw new LaunchRejectedError("INVALID_LAUNCH_IDENTITY");
    }

    const metadata: PartnerKeyMetadata | null = await this.repository.resolvePartnerKey(
      claims.partnerCode,
      claims.keyId,
    );
    if (!metadata || metadata.partner_code !== claims.partnerCode ||
        metadata.protocol_version !== claims.protocolVersion) {
      throw new LaunchRejectedError("PARTNER_KEY_NOT_ACTIVE");
    }

    const currencyExponent = await this.currencies.resolveExponent(claims.currency);
    if (currencyExponent === null || !Number.isInteger(currencyExponent) ||
        currencyExponent < 0 || currencyExponent > 6) {
      throw new LaunchRejectedError("CURRENCY_EXPONENT_NOT_CONFIGURED");
    }

    const tokenHash = decodeSha256TokenHash(record.tokenHash);
    const result = await this.repository.createLaunchSession({
      partnerId: metadata.partner_id,
      keyId: metadata.key_id,
      protocolVersion: metadata.protocol_version,
      sessionId: claims.sessionId,
      launchId: claims.launchId,
      partnerPlayerRef: claims.partnerPlayerRef,
      partnerSessionRef: claims.partnerSessionRef,
      gameCode: claims.gameCode,
      jurisdiction: claims.jurisdiction,
      currency: claims.currency,
      currencyExponent,
      locale: claims.locale,
      policyVersion: claims.policyVersion,
      tokenHash,
      expiresAt: claims.expiresAt,
    });

    if (!result.tokenIssued || !result.launchId || result.status !== "CREATED") {
      throw new PartnerSessionConflictError();
    }

    return {
      ...claims,
      launchId: result.launchId,
      sessionId: result.sessionId,
      expiresAt: result.tokenExpiresAt ?? claims.expiresAt,
    };
  }

  async consumeOnce(tokenHash: string, _now: string): Promise<LaunchClaims | null> {
    const digest = decodeSha256TokenHash(tokenHash);
    const row = await this.repository.consumeLaunchToken(digest);
    if (!row) return null;

    return {
      launchId: row.launch_id,
      sessionId: row.session_id,
      partnerCode: row.partner_code,
      partnerPlayerRef: row.partner_player_ref,
      partnerSessionRef: row.partner_session_ref,
      gameCode: row.game_code,
      currency: row.currency,
      jurisdiction: row.jurisdiction,
      locale: row.locale,
      keyId: row.key_id,
      protocolVersion: row.protocol_version,
      policyVersion: row.policy_version,
      issuedAt: new Date(row.issued_at).toISOString(),
      expiresAt: new Date(row.expires_at).toISOString(),
    };
  }
}

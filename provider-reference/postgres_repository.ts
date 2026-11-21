/**
 * Reference port for proposed provider_internal PostgreSQL routines.
 * No connection, secret lookup or live project access happens in this module.
 */
export interface PgQueryResult<T> {
  rows: T[];
  rowCount: number;
}

export interface ProviderPgExecutor {
  query<T extends Record<string, unknown>>(
    sql: string,
    parameters: readonly unknown[],
  ): Promise<PgQueryResult<T>>;
}

export interface PartnerKeyMetadata extends Record<string, unknown> {
  partner_id: string;
  partner_code: string;
  key_id: string;
  auth_profile: "ASIX_HMAC_SHA256_V1" | "ECDSA_P256_SHA256_PAYLOAD_V1" | "MTLS" | "OAUTH2_JWT";
  protocol_version: string;
  secret_reference: string | null;
  public_key_reference: string | null;
}

export interface NonceConsumption {
  partnerId: string;
  keyId: string;
  nonceHash: Uint8Array;
  expiresAt: string;
}

export interface LaunchSessionInput {
  partnerId: string;
  keyId: string;
  protocolVersion: string;
  sessionId: string;
  launchId: string;
  partnerPlayerRef: string;
  partnerSessionRef: string;
  gameCode: string;
  jurisdiction: string;
  currency: string;
  currencyExponent: number;
  locale: string;
  policyVersion: string;
  tokenHash: Uint8Array;
  expiresAt: string;
}

export interface LaunchSessionResult {
  launchId: string | null;
  sessionId: string;
  status: string;
  tokenIssued: boolean;
  tokenExpiresAt: string | null;
}

export interface LaunchClaimsRow extends Record<string, unknown> {
  launch_id: string;
  session_id: string;
  partner_id: string;
  partner_code: string;
  partner_player_ref: string;
  partner_session_ref: string;
  game_code: string;
  currency: string;
  jurisdiction: string;
  locale: string;
  key_id: string;
  protocol_version: string;
  policy_version: string;
  issued_at: string;
  expires_at: string;
}

export interface WalletTransactionInput {
  partnerId: string;
  sessionId: string;
  roundId: string | null;
  idempotencyKey: string;
  requestHash: Uint8Array;
  operation: "BET" | "WIN" | "REFUND";
  amountMinor: bigint;
  currency: string;
  currencyExponent: number;
  originalTransactionId?: string | null;
}

export interface WalletTransactionCreated {
  transactionId: string;
  status: string;
  wasCreated: boolean;
}

export interface WalletPartnerResponseInput {
  partnerId: string;
  workerId: string;
  leaseToken: string;
  transactionId: string;
  attemptKind: "DISPATCH" | "STATUS_QUERY";
  generation: number;
  attemptNumber: number;
  requestHash: Uint8Array;
  responseHash: Uint8Array;
  targetStatus: "CONFIRMED" | "DECLINED" | "PENDING" | "UNKNOWN";
  responseCode: string;
  partnerTransactionRef?: string | null;
  nextStatusAt?: string | null;
}

export interface WalletPartnerResponseResult {
  transactionStatus: string;
  statusQueryGeneration: number;
  wasRecorded: boolean;
}

export interface WalletTransactionStatus extends Record<string, unknown> {
  transaction_id: string;
  transaction_status: string;
  operation: "BET" | "WIN" | "REFUND";
  amount_minor: number | string;
  currency: string;
  partner_transaction_ref: string | null;
}

export interface ClaimedOutboxEvent {
  [key: string]: unknown;
  id: string;
  partner_id: string;
  wallet_transaction_id: string;
  event_type: "WALLET_DISPATCH" | "WALLET_STATUS_QUERY";
  generation: number;
  payload: Record<string, unknown>;
  attempts: number;
  lease_until: string;
  lease_token: string;
}

export class ProviderDatabaseError extends Error {
  constructor(code: string) {
    super(code);
    this.name = "ProviderDatabaseError";
  }
}

function validateHash(value: Uint8Array, field: string): void {
  if (!(value instanceof Uint8Array) || value.byteLength !== 32) {
    throw new ProviderDatabaseError("INVALID_" + field.toUpperCase() + "_HASH");
  }
}

function validateCurrency(currency: string, exponent: number): void {
  if (!/^[A-Z]{3}$/.test(currency) || !Number.isInteger(exponent) || exponent < 0 || exponent > 6) {
    throw new ProviderDatabaseError("INVALID_CURRENCY_CONTEXT");
  }
}

export class ProviderPostgresRepository {
  constructor(private readonly db: ProviderPgExecutor) {}

  async resolvePartnerKey(
    partnerCode: string,
    keyId: string,
  ): Promise<PartnerKeyMetadata | null> {
    if (!partnerCode || partnerCode.length > 64 || !/^[a-z0-9][a-z0-9_-]{1,63}$/.test(partnerCode) ||
        !keyId || keyId.length > 128) {
      throw new ProviderDatabaseError("INVALID_PARTNER_KEY_LOOKUP");
    }
    const result = await this.db.query<PartnerKeyMetadata>(
      "SELECT * FROM provider_internal.resolve_partner_key($1::text,$2::text)",
      [partnerCode, keyId],
    );
    if (result.rows.length > 1) {
      throw new ProviderDatabaseError("NON_UNIQUE_PARTNER_KEY_RESULT");
    }
    return result.rows[0] ?? null;
  }

  async consumePartnerNonce(input: NonceConsumption): Promise<boolean> {
    validateHash(input.nonceHash, "nonce");
    if (!input.partnerId || !input.keyId || !Number.isFinite(Date.parse(input.expiresAt))) {
      throw new ProviderDatabaseError("INVALID_NONCE_INPUT");
    }
    const result = await this.db.query<{ consumed: boolean }>(
      "SELECT provider_internal.consume_partner_nonce($1::uuid, $2::text, $3::bytea, $4::timestamptz) AS consumed",
      [input.partnerId, input.keyId, input.nonceHash, input.expiresAt],
    );
    if (result.rows.length !== 1 || typeof result.rows[0].consumed !== "boolean") {
      throw new ProviderDatabaseError("INVALID_NONCE_FUNCTION_RESPONSE");
    }
    return result.rows[0].consumed;
  }

  async createLaunchSession(input: LaunchSessionInput): Promise<LaunchSessionResult> {
    validateHash(input.tokenHash, "launch_token");
    validateCurrency(input.currency, input.currencyExponent);
    if (!input.partnerId || !input.keyId || input.keyId.length > 128 ||
        !input.protocolVersion || input.protocolVersion.length > 64 ||
        !/^[0-9a-f-]{36}$/i.test(input.sessionId) ||
        !/^[0-9a-f-]{36}$/i.test(input.launchId) ||
        !input.partnerPlayerRef || input.partnerPlayerRef.length > 200 ||
        !input.partnerSessionRef || input.partnerSessionRef.length > 200 ||
        !input.gameCode || input.gameCode.length > 80 ||
        !/^[A-Z0-9_-]{2,8}$/.test(input.jurisdiction) ||
        !input.locale || input.locale.length > 35 ||
        !input.policyVersion || input.policyVersion.length > 80 ||
        !Number.isFinite(Date.parse(input.expiresAt))) {
      throw new ProviderDatabaseError("INVALID_LAUNCH_SESSION_INPUT");
    }
    const result = await this.db.query<{
      launch_id: string | null;
      session_id: string;
      session_status: string;
      token_issued: boolean;
      token_expires_at: string | null;
    }>(
      "SELECT * FROM provider_internal.create_launch_session($1::uuid,$2::text,$3::text,$4::uuid,$5::uuid,$6::text,$7::text,$8::text,$9::text,$10::text,$11::smallint,$12::text,$13::text,$14::bytea,$15::timestamptz)",
      [
        input.partnerId,
        input.keyId,
        input.protocolVersion,
        input.sessionId,
        input.launchId,
        input.partnerPlayerRef,
        input.partnerSessionRef,
        input.gameCode,
        input.jurisdiction,
        input.currency,
        input.currencyExponent,
        input.locale,
        input.policyVersion,
        input.tokenHash,
        input.expiresAt,
      ],
    );
    if (result.rows.length !== 1 ||
        !result.rows[0].session_id ||
        !result.rows[0].session_status ||
        typeof result.rows[0].token_issued !== "boolean") {
      throw new ProviderDatabaseError("INVALID_LAUNCH_SESSION_FUNCTION_RESULT");
    }
    return {
      launchId: result.rows[0].launch_id ?? null,
      sessionId: result.rows[0].session_id,
      status: result.rows[0].session_status,
      tokenIssued: result.rows[0].token_issued,
      tokenExpiresAt: result.rows[0].token_expires_at ?? null,
    };
  }

  async consumeLaunchToken(tokenHash: Uint8Array): Promise<LaunchClaimsRow | null> {
    validateHash(tokenHash, "launch_token");
    const result = await this.db.query<LaunchClaimsRow>(
      "SELECT * FROM provider_internal.consume_launch_token($1::bytea)",
      [tokenHash],
    );
    if (result.rows.length > 1) throw new ProviderDatabaseError("NON_UNIQUE_LAUNCH_TOKEN_RESULT");
    return result.rows[0] ?? null;
  }

  async createWalletTransaction(input: WalletTransactionInput): Promise<WalletTransactionCreated> {
    validateHash(input.requestHash, "request");
    validateCurrency(input.currency, input.currencyExponent);
    if (!input.partnerId || !input.sessionId || !input.idempotencyKey ||
        input.amountMinor <= 0n ||
        (input.operation === "REFUND" && !input.originalTransactionId) ||
        (input.operation !== "REFUND" && input.originalTransactionId)) {
      throw new ProviderDatabaseError("INVALID_WALLET_TRANSACTION_INPUT");
    }
    const result = await this.db.query<{
      transaction_id: string;
      transaction_status: string;
      was_created: boolean;
    }>(
      "SELECT * FROM provider_internal.create_wallet_transaction($1::uuid,$2::uuid,$3::uuid,$4::text,$5::bytea,$6::text,$7::bigint,$8::text,$9::smallint,$10::uuid)",
      [
        input.partnerId,
        input.sessionId,
        input.roundId,
        input.idempotencyKey,
        input.requestHash,
        input.operation,
        input.amountMinor.toString(),
        input.currency,
        input.currencyExponent,
        input.originalTransactionId ?? null,
      ],
    );
    if (result.rows.length !== 1) throw new ProviderDatabaseError("INVALID_WALLET_FUNCTION_RESPONSE");
    const row = result.rows[0];
    if (!row.transaction_id || !row.transaction_status || typeof row.was_created !== "boolean") {
      throw new ProviderDatabaseError("INVALID_WALLET_FUNCTION_RESPONSE");
    }
    return {
      transactionId: row.transaction_id,
      status: row.transaction_status,
      wasCreated: row.was_created,
    };
  }

  async claimOutboxEvents(workerId: string, limit = 25, leaseSeconds = 30): Promise<ClaimedOutboxEvent[]> {
    if (!workerId || !Number.isInteger(limit) || limit < 1 || limit > 100 ||
        !Number.isInteger(leaseSeconds) || leaseSeconds < 5 || leaseSeconds > 300) {
      throw new ProviderDatabaseError("INVALID_OUTBOX_CLAIM_INPUT");
    }
    const result = await this.db.query<ClaimedOutboxEvent>(
      "SELECT * FROM provider_internal.claim_outbox_events($1::uuid,$2::integer,$3::integer)",
      [workerId, limit, leaseSeconds],
    );
    return result.rows;
  }

  async recordWalletPartnerResponse(input: WalletPartnerResponseInput): Promise<WalletPartnerResponseResult> {
    validateHash(input.requestHash, "request");
    validateHash(input.responseHash, "response");
    if (!input.partnerId || !input.workerId || !input.leaseToken || !input.transactionId ||
        (input.attemptKind !== "DISPATCH" && input.attemptKind !== "STATUS_QUERY") ||
        !Number.isInteger(input.generation) || input.generation < 0 ||
        !Number.isInteger(input.attemptNumber) || input.attemptNumber < 1 ||
        !["CONFIRMED", "DECLINED", "PENDING", "UNKNOWN"].includes(input.targetStatus) ||
        !input.responseCode || input.responseCode.length > 128 ||
        (input.partnerTransactionRef != null && input.partnerTransactionRef.length > 200) ||
        (input.targetStatus === "CONFIRMED" && !input.partnerTransactionRef) ||
        (input.nextStatusAt != null && !Number.isFinite(Date.parse(input.nextStatusAt)))) {
      throw new ProviderDatabaseError("INVALID_PARTNER_WALLET_RESPONSE");
    }
    if ((input.targetStatus === "PENDING" || input.targetStatus === "UNKNOWN") &&
        !input.nextStatusAt) {
      throw new ProviderDatabaseError("NEXT_STATUS_QUERY_TIME_REQUIRED");
    }
    const result = await this.db.query<{
      transaction_status: string;
      status_query_generation: number;
      was_recorded: boolean;
    }>(
      "SELECT * FROM provider_internal.record_wallet_partner_response($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::integer,$7::integer,$8::bytea,$9::bytea,$10::text,$11::text,$12::text,$13::timestamptz)",
      [
        input.partnerId,
        input.workerId,
        input.leaseToken,
        input.transactionId,
        input.attemptKind,
        input.generation,
        input.attemptNumber,
        input.requestHash,
        input.responseHash,
        input.targetStatus,
        input.responseCode,
        input.partnerTransactionRef ?? null,
        input.nextStatusAt ?? null,
      ],
    );
    if (result.rows.length !== 1 ||
        !result.rows[0].transaction_status ||
        !Number.isInteger(result.rows[0].status_query_generation) ||
        typeof result.rows[0].was_recorded !== "boolean") {
      throw new ProviderDatabaseError("INVALID_PARTNER_RESPONSE_FUNCTION_RESULT");
    }
    return {
      transactionStatus: result.rows[0].transaction_status,
      statusQueryGeneration: result.rows[0].status_query_generation,
      wasRecorded: result.rows[0].was_recorded,
    };
  }

  async getWalletTransactionStatus(
    partnerId: string,
    idempotencyKey: string,
  ): Promise<WalletTransactionStatus | null> {
    if (!partnerId || !idempotencyKey || idempotencyKey.length > 200) {
      throw new ProviderDatabaseError("INVALID_WALLET_STATUS_QUERY");
    }
    const result = await this.db.query<WalletTransactionStatus>(
      "SELECT * FROM provider_internal.get_wallet_transaction_status($1::uuid,$2::text)",
      [partnerId, idempotencyKey],
    );
    if (result.rows.length > 1) throw new ProviderDatabaseError("NON_UNIQUE_WALLET_STATUS_RESULT");
    return result.rows[0] ?? null;
  }

  async markExpiredDispatchesUnknown(): Promise<number> {
    const result = await this.db.query<{ recovered_count: number }>(
      "SELECT provider_internal.mark_expired_wallet_dispatches_unknown() AS recovered_count",
      [],
    );
    const count = result.rows[0]?.recovered_count;
    if (!Number.isInteger(count) || count < 0) {
      throw new ProviderDatabaseError("INVALID_DISPATCH_RECOVERY_RESPONSE");
    }
    return count;
  }

  async recoverExpiredStatusQueryLeases(backoffSeconds = 5): Promise<number> {
    if (!Number.isInteger(backoffSeconds) || backoffSeconds < 1 || backoffSeconds > 300) {
      throw new ProviderDatabaseError("INVALID_STATUS_QUERY_BACKOFF");
    }
    const result = await this.db.query<{ recovered_count: number }>(
      "SELECT provider_internal.recover_expired_wallet_status_query_leases($1::integer) AS recovered_count",
      [backoffSeconds],
    );
    const count = result.rows[0]?.recovered_count;
    if (!Number.isInteger(count) || count < 0) {
      throw new ProviderDatabaseError("INVALID_STATUS_QUERY_RECOVERY_RESPONSE");
    }
    return count;
  }

  async postLedgerJournal(journalId: string, journalHash: Uint8Array): Promise<boolean> {
    validateHash(journalHash, "journal");
    if (!journalId) throw new ProviderDatabaseError("INVALID_JOURNAL_ID");
    const result = await this.db.query<{ posted: boolean }>(
      "SELECT provider_internal.post_ledger_journal($1::uuid,$2::bytea) AS posted",
      [journalId, journalHash],
    );
    if (result.rows.length !== 1 || result.rows[0].posted !== true) {
      throw new ProviderDatabaseError("LEDGER_POST_NOT_CONFIRMED");
    }
    return true;
  }
}

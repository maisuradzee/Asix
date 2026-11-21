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

export interface NonceConsumption {
  partnerId: string;
  keyId: string;
  nonceHash: Uint8Array;
  expiresAt: string;
}

export interface LaunchClaimsRow {
  partner_id: string;
  session_id: string;
  partner_player_ref: string;
  partner_session_ref: string;
  game_code: string;
  currency: string;
  jurisdiction: string;
  locale: string;
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

export interface ClaimedOutboxEvent {
  id: string;
  partner_id: string;
  wallet_transaction_id: string;
  event_type: "WALLET_DISPATCH" | "WALLET_STATUS_QUERY";
  generation: number;
  payload: Record<string, unknown>;
  attempts: number;
  lease_until: string;
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

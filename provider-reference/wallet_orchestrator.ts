import type {
  PartnerCode,
  PartnerWalletAdapter,
  TransactionStatusQuery,
  WalletCommand,
  WalletResult,
  WalletState,
} from "./contracts.ts";

export interface WalletTransactionRecord {
  transactionId: string;
  partnerCode: PartnerCode;
  idempotencyKey: string;
  requestHash: string;
  command: WalletCommand;
  state: WalletState;
  result?: WalletResult;
  attemptCount: number;
  dispatchLeaseOwner?: string;
  dispatchLeaseUntil?: string;
  lastErrorCode?: string;
  createdAt: string;
  updatedAt: string;
}

export interface CreateOrGetResult {
  record: WalletTransactionRecord;
  created: boolean;
}

export interface WalletTransactionRepository {
  /**
   * Must be atomic in a durable implementation:
   * unique(partner_code, idempotency_key), compare requestHash on conflict.
   */
  createOrGet(command: WalletCommand, requestHash: string, now: string): Promise<CreateOrGetResult>;
  getById(transactionId: string): Promise<WalletTransactionRecord | null>;
  claimInitialDispatch(
    transactionId: string,
    workerId: string,
    leaseUntil: string,
    now: string,
  ): Promise<boolean>;
  updateFromStates(
    transactionId: string,
    expectedStates: readonly WalletState[],
    patch: Partial<Pick<WalletTransactionRecord, "state" | "result" | "lastErrorCode" | "updatedAt">>,
  ): Promise<boolean>;
  markExpiredDispatchUnknown(transactionId: string, now: string): Promise<boolean>;
}

export type AdapterResolver = (partnerCode: PartnerCode) => PartnerWalletAdapter;

export class IdempotencyConflictError extends Error {
  constructor() {
    super("IDEMPOTENCY_CONFLICT");
    this.name = "IdempotencyConflictError";
  }
}

export class TransactionNotFoundError extends Error {
  constructor() {
    super("TRANSACTION_NOT_FOUND");
    this.name = "TransactionNotFoundError";
  }
}

function validateCommand(command: WalletCommand): void {
  if (!command.transactionId || !command.idempotencyKey ||
      !command.partnerCode || !command.partnerPlayerRef || !command.partnerSessionRef ||
      !command.roundId || !command.currency || !Number.isInteger(command.currencyExponent) ||
      command.currencyExponent < 0 || command.currencyExponent > 6 ||
      command.amountMinor <= 0n || !/^[A-Z]{3}$/.test(command.currency) ||
      (command.operation === "REFUND" &&
        (!command.originalTransactionId || !command.originalPartnerTransactionRef))) {
    throw new Error("INVALID_WALLET_COMMAND");
  }
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

/**
 * The orchestrator computes this fingerprint itself. A caller-supplied hash
 * must never be trusted to establish idempotency.
 */
export async function computeWalletRequestHash(command: WalletCommand): Promise<string> {
  const canonical = JSON.stringify({
    partnerCode: command.partnerCode,
    transactionId: command.transactionId,
    idempotencyKey: command.idempotencyKey,
    operation: command.operation,
    partnerPlayerRef: command.partnerPlayerRef,
    partnerSessionRef: command.partnerSessionRef,
    roundId: command.roundId,
    originalTransactionId: command.originalTransactionId ?? null,
    originalPartnerTransactionRef: command.originalPartnerTransactionRef ?? null,
    amountMinor: command.amountMinor.toString(),
    currency: command.currency,
    currencyExponent: command.currencyExponent,
  });
  const digest = await crypto.subtle.digest(
    "SHA-256",
    toArrayBuffer(new TextEncoder().encode(canonical)),
  );
  const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `sha256:${hex}`;
}

function validatePartnerResult(
  command: WalletCommand,
  result: WalletResult,
  expectedPartnerTransactionRef?: string,
): void {
  if (result.transactionId !== command.transactionId ||
      result.partnerCode !== command.partnerCode ||
      result.currency !== command.currency ||
      result.correlationId !== command.correlationId ||
      result.adapterVersion !== command.adapterVersion ||
      result.protocolVersion !== command.protocolVersion) {
    throw new Error("PARTNER_RESPONSE_CONTEXT_MISMATCH");
  }
  if (result.amountMinor !== command.amountMinor) {
    throw new Error("PARTNER_RESPONSE_AMOUNT_MISMATCH");
  }
  if (expectedPartnerTransactionRef &&
      result.partnerTransactionRef !== expectedPartnerTransactionRef) {
    throw new Error("PARTNER_RESPONSE_REFERENCE_MISMATCH");
  }
  if (!result.responseCode || !result.responseHash || !Number.isFinite(Date.parse(result.responseAt))) {
    throw new Error("PARTNER_RESPONSE_EVIDENCE_INVALID");
  }
  if (result.state === "CONFIRMED" && !result.partnerTransactionRef?.trim()) {
    throw new Error("PARTNER_TRANSACTION_REFERENCE_MISSING");
  }
}

function toStatusQuery(command: WalletCommand, requestedAt: string, partnerTransactionRef?: string): TransactionStatusQuery {
  return {
    transactionId: command.transactionId,
    idempotencyKey: command.idempotencyKey,
    partnerTransactionRef,
    partnerCode: command.partnerCode,
    adapterVersion: command.adapterVersion,
    protocolVersion: command.protocolVersion,
    correlationId: command.correlationId,
    requestedAt,
  };
}

/**
 * Bounded wallet orchestrator reference.
 *
 * Safety properties:
 * - durable repository owns idempotency and dispatch claims;
 * - one initial send only;
 * - uncertain outcomes become UNKNOWN;
 * - UNKNOWN/PENDING are resolved by read-only status query;
 * - it never creates a fresh transaction to retry an uncertain operation.
 *
 * This class is not wired to production. A production repository must implement
 * the documented methods with transactional SQL and row-level concurrency control.
 */
export class WalletOrchestrator {
  constructor(
    private readonly repository: WalletTransactionRepository,
    private readonly resolveAdapter: AdapterResolver,
    private readonly now: () => Date = () => new Date(),
    private readonly dispatchLeaseMs = 30_000,
    private readonly operationTimeoutMs = 8_000,
  ) {
    if (!Number.isInteger(dispatchLeaseMs) || dispatchLeaseMs < 1_000 || dispatchLeaseMs > 120_000) {
      throw new Error("INVALID_DISPATCH_LEASE");
    }
    if (!Number.isInteger(operationTimeoutMs) || operationTimeoutMs < 50 || operationTimeoutMs > 60_000) {
      throw new Error("INVALID_OPERATION_TIMEOUT");
    }
    if (dispatchLeaseMs <= operationTimeoutMs) {
      throw new Error("DISPATCH_LEASE_MUST_EXCEED_OPERATION_TIMEOUT");
    }
  }

  async execute(command: WalletCommand, workerId: string): Promise<WalletTransactionRecord> {
    validateCommand(command);
    if (!workerId || workerId.length > 128) throw new Error("INVALID_WORKER_ID");

    const now = this.now();
    const requestHash = await computeWalletRequestHash(command);
    const created = await this.repository.createOrGet(command, requestHash, now.toISOString());
    if (created.record.requestHash !== requestHash ||
        created.record.transactionId !== command.transactionId) {
      throw new IdempotencyConflictError();
    }

    // Existing PENDING/UNKNOWN/DISPATCHING/terminal transactions are never
    // blindly dispatched again. They require status resolution or are returned.
    if (created.record.state !== "CREATED") return created.record;

    const leaseUntil = new Date(now.getTime() + this.dispatchLeaseMs).toISOString();
    const claimed = await this.repository.claimInitialDispatch(
      command.transactionId,
      workerId,
      leaseUntil,
      now.toISOString(),
    );
    if (!claimed) {
      const current = await this.repository.getById(command.transactionId);
      if (!current) throw new TransactionNotFoundError();
      return current;
    }

    try {
      const adapter = this.resolveAdapter(command.partnerCode);
      const result = await this.withTimeout(this.dispatch(adapter, command));
      validatePartnerResult(command, result);
      await this.repository.updateFromStates(command.transactionId, ["DISPATCHING"], {
        state: result.state,
        result,
        updatedAt: this.now().toISOString(),
        lastErrorCode: undefined,
      });
    } catch (error) {
      const errorCode = error instanceof Error && error.message.startsWith("PARTNER_")
        ? error.message.slice(0, 96)
        : "PARTNER_OUTCOME_UNCERTAIN";
      // A thrown transport error or malformed response after dispatch cannot
      // prove that the wallet effect did not happen.
      await this.repository.updateFromStates(command.transactionId, ["DISPATCHING"], {
        state: "UNKNOWN",
        lastErrorCode: errorCode,
        updatedAt: this.now().toISOString(),
      });
    }

    const current = await this.repository.getById(command.transactionId);
    if (!current) throw new TransactionNotFoundError();
    return current;
  }

  async resolveUnknown(transactionId: string): Promise<WalletTransactionRecord> {
    const current = await this.repository.getById(transactionId);
    if (!current) throw new TransactionNotFoundError();
    if (current.state !== "UNKNOWN" && current.state !== "PENDING") return current;

    try {
      const adapter = this.resolveAdapter(current.partnerCode);
      const result = await this.withTimeout(adapter.getTransactionStatus(toStatusQuery(
        current.command,
        this.now().toISOString(),
        current.result?.partnerTransactionRef,
      )));
      validatePartnerResult(current.command, result, current.result?.partnerTransactionRef);
      await this.repository.updateFromStates(transactionId, ["UNKNOWN", "PENDING"], {
        state: result.state,
        result,
        lastErrorCode: undefined,
        updatedAt: this.now().toISOString(),
      });
    } catch (error) {
      const errorCode = error instanceof Error && error.message.startsWith("PARTNER_")
        ? error.message.slice(0, 96)
        : "PARTNER_STATUS_QUERY_UNAVAILABLE";
      await this.repository.updateFromStates(transactionId, ["UNKNOWN", "PENDING"], {
        lastErrorCode: errorCode,
        updatedAt: this.now().toISOString(),
      });
    }

    const after = await this.repository.getById(transactionId);
    if (!after) throw new TransactionNotFoundError();
    return after;
  }

  async recoverExpiredDispatch(transactionId: string): Promise<WalletTransactionRecord> {
    const now = this.now().toISOString();
    await this.repository.markExpiredDispatchUnknown(transactionId, now);
    const current = await this.repository.getById(transactionId);
    if (!current) throw new TransactionNotFoundError();
    return current;
  }


  private async withTimeout<T>(operation: Promise<T>): Promise<T> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      return await Promise.race([
        operation,
        new Promise<T>((_, reject) => {
          timer = setTimeout(() => reject(new Error("PARTNER_REQUEST_TIMEOUT")), this.operationTimeoutMs);
        }),
      ]);
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  }

  private async dispatch(adapter: PartnerWalletAdapter, command: WalletCommand): Promise<WalletResult> {
    switch (command.operation) {
      case "BET":
        return await adapter.debitBet(command);
      case "WIN":
        return await adapter.creditWin(command);
      case "REFUND":
        return await adapter.refund(command);
    }
  }
}

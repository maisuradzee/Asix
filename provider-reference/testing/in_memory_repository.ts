import type { WalletState } from "../contracts.ts";
import type {
  CreateOrGetResult,
  WalletTransactionRecord,
  WalletTransactionRepository,
} from "../wallet_orchestrator.ts";
import type { WalletCommand } from "../contracts.ts";

/**
 * Test-only in-memory repository. Not durable and not suitable for production.
 * A production implementation must use PostgreSQL transactions, unique
 * constraints and conditional updates/leases.
 */
export class InMemoryWalletTransactionRepository implements WalletTransactionRepository {
  private readonly rows = new Map<string, WalletTransactionRecord>();
  private readonly idempotency = new Map<string, string>();

  private key(partner: string, idempotencyKey: string): string {
    return `${partner}:${idempotencyKey}`;
  }

  async createOrGet(command: WalletCommand, now: string): Promise<CreateOrGetResult> {
    const key = this.key(command.partnerCode, command.idempotencyKey);
    const existingId = this.idempotency.get(key);
    if (existingId) {
      const existing = this.rows.get(existingId)!;
      return { record: existing, created: false };
    }
    const row: WalletTransactionRecord = {
      transactionId: command.transactionId,
      partnerCode: command.partnerCode,
      idempotencyKey: command.idempotencyKey,
      requestHash: command.requestHash,
      command,
      state: "CREATED",
      attemptCount: 0,
      createdAt: now,
      updatedAt: now,
    };
    this.rows.set(row.transactionId, row);
    this.idempotency.set(key, row.transactionId);
    return { record: row, created: true };
  }

  async getById(transactionId: string): Promise<WalletTransactionRecord | null> {
    return this.rows.get(transactionId) ?? null;
  }

  async claimInitialDispatch(
    transactionId: string,
    workerId: string,
    leaseUntil: string,
    now: string,
  ): Promise<boolean> {
    const row = this.rows.get(transactionId);
    if (!row || row.state !== "CREATED") return false;
    row.state = "DISPATCHING";
    row.dispatchLeaseOwner = workerId;
    row.dispatchLeaseUntil = leaseUntil;
    row.attemptCount += 1;
    row.updatedAt = now;
    return true;
  }

  async updateFromStates(
    transactionId: string,
    expectedStates: readonly WalletState[],
    patch: Partial<Pick<WalletTransactionRecord, "state" | "result" | "lastErrorCode" | "updatedAt">>,
  ): Promise<boolean> {
    const row = this.rows.get(transactionId);
    if (!row || !expectedStates.includes(row.state)) return false;
    if (patch.state) row.state = patch.state;
    if ("result" in patch) row.result = patch.result;
    if ("lastErrorCode" in patch) row.lastErrorCode = patch.lastErrorCode;
    if (patch.updatedAt) row.updatedAt = patch.updatedAt;
    if (row.state !== "DISPATCHING") {
      delete row.dispatchLeaseOwner;
      delete row.dispatchLeaseUntil;
    }
    return true;
  }

  async markExpiredDispatchUnknown(transactionId: string, now: string): Promise<boolean> {
    const row = this.rows.get(transactionId);
    if (!row || row.state !== "DISPATCHING" || !row.dispatchLeaseUntil ||
        row.dispatchLeaseUntil > now) return false;
    row.state = "UNKNOWN";
    row.lastErrorCode = "DISPATCH_LEASE_EXPIRED";
    row.updatedAt = now;
    delete row.dispatchLeaseOwner;
    delete row.dispatchLeaseUntil;
    return true;
  }
}

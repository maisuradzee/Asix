/**
 * ASIX provider adapter contract reference.
 *
 * This file is deliberately framework-free and is NOT wired into the active
 * super-worker V25 or any production path. It defines the domain boundary for
 * future partner adapters. Compile and test it inside the chosen provider
 * service package before implementation.
 */

export type IsoCurrencyCode = string & { readonly __brand: "IsoCurrencyCode" };
export type MinorUnits = bigint & { readonly __brand: "MinorUnits" };
export type PartnerCode = string & { readonly __brand: "PartnerCode" };

export type WalletOperation = "BET" | "WIN" | "REFUND";
export type WalletState =
  | "CREATED"
  | "DISPATCHING"
  | "CONFIRMED"
  | "DECLINED"
  | "PENDING"
  | "UNKNOWN"
  | "RECONCILED"
  | "EXCEPTION";

export interface CorrelationContext {
  correlationId: string;
  partnerCode: PartnerCode;
  adapterVersion: string;
  protocolVersion: string;
}

export interface WalletCommand extends CorrelationContext {
  transactionId: string;
  idempotencyKey: string;
  operation: WalletOperation;
  partnerPlayerRef: string;
  partnerSessionRef: string;
  roundId: string;
  amountMinor: MinorUnits;
  currency: IsoCurrencyCode;
  currencyExponent: number;
  requestHash: string;
  createdAt: string;
}

export interface WalletResult extends CorrelationContext {
  state: "CONFIRMED" | "DECLINED" | "PENDING" | "UNKNOWN";
  transactionId: string;
  partnerTransactionRef?: string;
  amountMinor?: MinorUnits;
  currency: IsoCurrencyCode;
  partnerCode: PartnerCode;
  responseCode: string;
  responseAt: string;
  responseHash: string;
}

export interface TransactionStatusQuery extends CorrelationContext {
  transactionId: string;
  idempotencyKey: string;
  partnerTransactionRef?: string;
  requestedAt: string;
}

export interface PartnerHealth {
  partnerCode: PartnerCode;
  healthy: boolean;
  checkedAt: string;
  latencyMs?: number;
  failureCode?: string;
}

export interface PartnerWalletAdapter {
  debitBet(command: WalletCommand): Promise<WalletResult>;
  creditWin(command: WalletCommand): Promise<WalletResult>;
  refund(command: WalletCommand): Promise<WalletResult>;
  getTransactionStatus(query: TransactionStatusQuery): Promise<WalletResult>;
  healthCheck(context: CorrelationContext): Promise<PartnerHealth>;
}

export type PolicyAction =
  | "RESTART_STATELESS_WORKER"
  | "OPEN_PARTNER_CIRCUIT"
  | "SCALE_WITHIN_LIMIT"
  | "ROLLBACK_APPROVED_RELEASE"
  | "QUERY_TRANSACTION_STATUS";

export interface PolicyDecision {
  allowed: boolean;
  policyId: string;
  reason: string;
  requiresHumanApproval: boolean;
  expiresAt: string;
  maxAttempts?: number;
}

export interface AuditRecord {
  eventId: string;
  actorType: "SYSTEM" | "USER" | "SERVICE" | "AI";
  actorRef: string;
  action: string;
  targetType: string;
  targetRef: string;
  correlationId: string;
  reason: string;
  occurredAt: string;
  payloadHash: string;
}

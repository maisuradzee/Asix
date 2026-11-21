/**
 * Deterministic B2B settlement calculation reference.
 * Contract definition is explicit input; no default ASIX fee rate is assumed.
 * All money arithmetic uses bigint minor units.
 */

export type SettlementFeeModel = "REVENUE_SHARE" | "FIXED_FEE" | "HYBRID";
export type GgrEffect = "ADD_TO_GGR" | "DEDUCT_FROM_GGR";
export type RoundingMode = "FLOOR" | "HALF_UP";
export type NegativeGgrPolicy = "FLOOR_AT_ZERO" | "CARRY_FORWARD";

export interface GgrComponent {
  componentId: string;
  code: string;
  effect: GgrEffect;
  amountMinor: bigint;
  currency: string;
  sourceReference: string;
}

export interface SettlementContract {
  contractId: string;
  contractVersion: string;
  currency: string;
  allowedComponentCodes: string[];
  feeModel: SettlementFeeModel;
  revenueShareBps: number;
  fixedFeeMinor: bigint;
  roundingMode: RoundingMode;
  negativeGgrPolicy: NegativeGgrPolicy;
}

export interface SettlementInput {
  partnerCode: string;
  periodStart: string;
  periodEnd: string;
  components: GgrComponent[];
  priorLossCarryForwardMinor?: bigint;
}

export interface SettlementCalculation {
  partnerCode: string;
  contractId: string;
  contractVersion: string;
  currency: string;
  periodStart: string;
  periodEnd: string;
  rawGgrMinor: bigint;
  priorLossCarryForwardMinor: bigint;
  appliedLossCarryForwardMinor: bigint;
  closingLossCarryForwardMinor: bigint;
  effectiveGgrMinor: bigint;
  revenueShareFeeMinor: bigint;
  fixedFeeMinor: bigint;
  totalProviderFeeMinor: bigint;
  inputHash: string;
}

function assertDateRange(start: string, end: string): void {
  const a = Date.parse(start);
  const b = Date.parse(end);
  if (!Number.isFinite(a) || !Number.isFinite(b) || b <= a) {
    throw new Error("INVALID_SETTLEMENT_PERIOD");
  }
}

function validateContract(contract: SettlementContract): void {
  if (!contract.contractId || !contract.contractVersion ||
      !["REVENUE_SHARE", "FIXED_FEE", "HYBRID"].includes(contract.feeModel) ||
      !["FLOOR", "HALF_UP"].includes(contract.roundingMode) ||
      !["FLOOR_AT_ZERO", "CARRY_FORWARD"].includes(contract.negativeGgrPolicy) ||
      !/^[A-Z]{3}$/.test(contract.currency) ||
      !Array.isArray(contract.allowedComponentCodes) ||
      contract.allowedComponentCodes.length === 0 ||
      !Number.isInteger(contract.revenueShareBps) ||
      contract.revenueShareBps < 0 || contract.revenueShareBps > 10_000 ||
      contract.fixedFeeMinor < 0n) {
    throw new Error("INVALID_SETTLEMENT_CONTRACT");
  }
  if (contract.feeModel === "REVENUE_SHARE" &&
      (contract.revenueShareBps <= 0 || contract.fixedFeeMinor !== 0n)) {
    throw new Error("INVALID_REVENUE_SHARE_CONTRACT");
  }
  if (contract.feeModel === "FIXED_FEE" &&
      (contract.fixedFeeMinor <= 0n || contract.revenueShareBps !== 0)) {
    throw new Error("INVALID_FIXED_FEE_CONTRACT");
  }
  if (contract.feeModel === "HYBRID" &&
      (contract.revenueShareBps <= 0 || contract.fixedFeeMinor <= 0n)) {
    throw new Error("INVALID_HYBRID_CONTRACT");
  }
}

function roundBps(baseMinor: bigint, rateBps: number, mode: RoundingMode): bigint {
  const numerator = baseMinor * BigInt(rateBps);
  const denominator = 10_000n;
  if (mode === "FLOOR") return numerator / denominator;
  return (numerator + denominator / 2n) / denominator;
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy.buffer;
}

async function hashInput(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", toArrayBuffer(new TextEncoder().encode(value)));
  const hex = Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `sha256:${hex}`;
}

export async function calculateProviderSettlement(
  contract: SettlementContract,
  input: SettlementInput,
): Promise<SettlementCalculation> {
  validateContract(contract);
  assertDateRange(input.periodStart, input.periodEnd);
  if (!input.partnerCode || !Array.isArray(input.components) || input.components.length === 0) {
    throw new Error("INVALID_SETTLEMENT_INPUT");
  }

  const priorCarry = input.priorLossCarryForwardMinor ?? 0n;
  if (priorCarry < 0n) throw new Error("INVALID_LOSS_CARRY_FORWARD");

  const componentIds = new Set<string>();
  let rawGgr = 0n;
  for (const component of input.components) {
    if (!component.componentId || !component.sourceReference ||
        !contract.allowedComponentCodes.includes(component.code) ||
        component.amountMinor < 0n ||
        component.currency !== contract.currency ||
        !["ADD_TO_GGR", "DEDUCT_FROM_GGR"].includes(component.effect) ||
        componentIds.has(component.componentId)) {
      throw new Error("INVALID_OR_UNAPPROVED_GGR_COMPONENT");
    }
    componentIds.add(component.componentId);
    rawGgr += component.effect === "ADD_TO_GGR" ? component.amountMinor : -component.amountMinor;
  }

  let appliedCarry = 0n;
  let closingCarry = 0n;
  let effectiveGgr = rawGgr;

  if (contract.negativeGgrPolicy === "FLOOR_AT_ZERO") {
    effectiveGgr = rawGgr > 0n ? rawGgr : 0n;
  } else if (contract.negativeGgrPolicy === "CARRY_FORWARD") {
    if (rawGgr >= 0n) {
      appliedCarry = priorCarry < rawGgr ? priorCarry : rawGgr;
      effectiveGgr = rawGgr - appliedCarry;
      closingCarry = priorCarry - appliedCarry;
    } else {
      appliedCarry = 0n;
      effectiveGgr = 0n;
      closingCarry = priorCarry + (-rawGgr);
    }
  } else {
    throw new Error("INVALID_NEGATIVE_GGR_POLICY");
  }

  const revenueShareFee = contract.feeModel === "FIXED_FEE"
    ? 0n
    : roundBps(effectiveGgr, contract.revenueShareBps, contract.roundingMode);
  const fixedFee = contract.feeModel === "REVENUE_SHARE" ? 0n : contract.fixedFeeMinor;
  const totalFee = revenueShareFee + fixedFee;

  const canonical = JSON.stringify({
    contractId: contract.contractId,
    contractVersion: contract.contractVersion,
    partnerCode: input.partnerCode,
    periodStart: input.periodStart,
    periodEnd: input.periodEnd,
    priorLossCarryForwardMinor: priorCarry.toString(),
    components: [...input.components]
      .sort((a, b) => a.componentId.localeCompare(b.componentId))
      .map((item) => ({
        componentId: item.componentId,
        code: item.code,
        effect: item.effect,
        amountMinor: item.amountMinor.toString(),
        currency: item.currency,
        sourceReference: item.sourceReference,
      })),
  });

  return {
    partnerCode: input.partnerCode,
    contractId: contract.contractId,
    contractVersion: contract.contractVersion,
    currency: contract.currency,
    periodStart: input.periodStart,
    periodEnd: input.periodEnd,
    rawGgrMinor: rawGgr,
    priorLossCarryForwardMinor: priorCarry,
    appliedLossCarryForwardMinor: appliedCarry,
    closingLossCarryForwardMinor: closingCarry,
    effectiveGgrMinor: effectiveGgr,
    revenueShareFeeMinor: revenueShareFee,
    fixedFeeMinor: fixedFee,
    totalProviderFeeMinor: totalFee,
    inputHash: await hashInput(canonical),
  };
}

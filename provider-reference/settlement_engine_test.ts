import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { calculateProviderSettlement, type SettlementContract } from "./settlement_engine.ts";

const baseContract: SettlementContract = {
  contractId: "contract-operator-a",
  contractVersion: "2026-01",
  currency: "GEL",
  allowedComponentCodes: ["ELIGIBLE_STAKES", "PLAYER_WINS", "BONUS_DEDUCTIONS", "VOID_REFUNDS"],
  feeModel: "REVENUE_SHARE",
  revenueShareBps: 500,
  fixedFeeMinor: 0n,
  roundingMode: "FLOOR",
  negativeGgrPolicy: "FLOOR_AT_ZERO",
};

const baseInput = {
  partnerCode: "operator-a",
  periodStart: "2026-11-01T00:00:00Z",
  periodEnd: "2026-12-01T00:00:00Z",
  components: [
    { componentId: "c1", code: "ELIGIBLE_STAKES", effect: "ADD_TO_GGR" as const, amountMinor: 100_000n, currency: "GEL", sourceReference: "report-stakes-1" },
    { componentId: "c2", code: "PLAYER_WINS", effect: "DEDUCT_FROM_GGR" as const, amountMinor: 60_000n, currency: "GEL", sourceReference: "report-wins-1" },
    { componentId: "c3", code: "BONUS_DEDUCTIONS", effect: "DEDUCT_FROM_GGR" as const, amountMinor: 5_000n, currency: "GEL", sourceReference: "report-bonus-1" },
  ],
};

Deno.test("revenue share uses exact minor-unit GGR and contract bps", async () => {
  const result = await calculateProviderSettlement(baseContract, baseInput);
  assertEquals(result.rawGgrMinor, 35_000n);
  assertEquals(result.effectiveGgrMinor, 35_000n);
  assertEquals(result.revenueShareFeeMinor, 1_750n);
  assertEquals(result.totalProviderFeeMinor, 1_750n);
  assertEquals(result.contractVersion, "2026-01");
});

Deno.test("fixed and hybrid models follow explicit contract inputs", async () => {
  const fixed = await calculateProviderSettlement({
    ...baseContract,
    feeModel: "FIXED_FEE",
    revenueShareBps: 0,
    fixedFeeMinor: 2_500n,
  }, baseInput);
  assertEquals(fixed.revenueShareFeeMinor, 0n);
  assertEquals(fixed.fixedFeeMinor, 2_500n);
  assertEquals(fixed.totalProviderFeeMinor, 2_500n);

  const hybrid = await calculateProviderSettlement({
    ...baseContract,
    feeModel: "HYBRID",
    fixedFeeMinor: 1_000n,
  }, baseInput);
  assertEquals(hybrid.totalProviderFeeMinor, 2_750n);
});

Deno.test("negative GGR can be floored or carried forward only as contract defines", async () => {
  const lossInput = {
    ...baseInput,
    components: [
      { componentId: "loss1", code: "ELIGIBLE_STAKES", effect: "ADD_TO_GGR" as const, amountMinor: 10_000n, currency: "GEL", sourceReference: "stakes" },
      { componentId: "loss2", code: "PLAYER_WINS", effect: "DEDUCT_FROM_GGR" as const, amountMinor: 12_000n, currency: "GEL", sourceReference: "wins" },
    ],
  };
  const floored = await calculateProviderSettlement(baseContract, lossInput);
  assertEquals(floored.rawGgrMinor, -2_000n);
  assertEquals(floored.effectiveGgrMinor, 0n);

  const carried = await calculateProviderSettlement({
    ...baseContract,
    negativeGgrPolicy: "CARRY_FORWARD",
  }, baseInput,);
  assertEquals(carried.closingLossCarryForwardMinor, 0n);
});

Deno.test("carry-forward offsets positive GGR and preserves unused loss", async () => {
  const result = await calculateProviderSettlement({
    ...baseContract,
    negativeGgrPolicy: "CARRY_FORWARD",
  }, baseInput,);
  // This period has 35,000 GGR; 40,000 prior loss carry leaves no fee and 5,000 carry.
  const withLoss = await calculateProviderSettlement({
    ...baseContract,
    negativeGgrPolicy: "CARRY_FORWARD",
  }, { ...baseInput, priorLossCarryForwardMinor: 40_000n });
  assertEquals(withLoss.appliedLossCarryForwardMinor, 35_000n);
  assertEquals(withLoss.effectiveGgrMinor, 0n);
  assertEquals(withLoss.closingLossCarryForwardMinor, 5_000n);
  assertEquals(withLoss.totalProviderFeeMinor, 0n);
  assertEquals(result.effectiveGgrMinor, 35_000n);
});

Deno.test("unapproved component, duplicate component ID and currency mismatch are rejected", async () => {
  await assertRejects(
    () => calculateProviderSettlement(baseContract, {
      ...baseInput,
      components: [{ ...baseInput.components[0], code: "UNAPPROVED_FEE" }],
    }),
    Error,
    "INVALID_OR_UNAPPROVED_GGR_COMPONENT",
  );
  await assertRejects(
    () => calculateProviderSettlement(baseContract, {
      ...baseInput,
      components: [baseInput.components[0], { ...baseInput.components[1], componentId: "c1" }],
    }),
    Error,
    "INVALID_OR_UNAPPROVED_GGR_COMPONENT",
  );
  await assertRejects(
    () => calculateProviderSettlement(baseContract, {
      ...baseInput,
      components: [{ ...baseInput.components[0], currency: "USD" }],
    }),
    Error,
    "INVALID_OR_UNAPPROVED_GGR_COMPONENT",
  );
});

Deno.test("half-up rounding is exact without floating point", async () => {
  const result = await calculateProviderSettlement({
    ...baseContract,
    revenueShareBps: 5_000,
    roundingMode: "HALF_UP",
  }, {
    ...baseInput,
    components: [
      { componentId: "tiny", code: "ELIGIBLE_STAKES", effect: "ADD_TO_GGR", amountMinor: 1n, currency: "GEL", sourceReference: "tiny" },
    ],
  });
  assertEquals(result.revenueShareFeeMinor, 1n);
});

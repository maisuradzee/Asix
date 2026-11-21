import { assertEquals, assertRejects } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { PartnerCircuitRegistry, statusQueryBackoffMs } from "./resilience.ts";

Deno.test("circuit opens after partner-specific failure threshold", () => {
  const registry = new PartnerCircuitRegistry();
  registry.register("operator-a", { failureThreshold: 2, cooldownMs: 1_000 });

  const first = registry.acquire("operator-a", 100)!;
  registry.recordFailure(first, 100);
  assertEquals(registry.snapshot("operator-a").state, "CLOSED");

  const second = registry.acquire("operator-a", 200)!;
  registry.recordFailure(second, 200);
  const state = registry.snapshot("operator-a");
  assertEquals(state.state, "OPEN");
  assertEquals(state.retryAt, 1_200);
  assertEquals(registry.acquire("operator-a", 1_199), null);
});

Deno.test("one partner circuit does not affect another partner", () => {
  const registry = new PartnerCircuitRegistry();
  registry.register("operator-a", { failureThreshold: 1, cooldownMs: 1_000 });
  registry.register("operator-b", { failureThreshold: 2, cooldownMs: 1_000 });

  const permitA = registry.acquire("operator-a", 1)!;
  registry.recordFailure(permitA, 1);

  assertEquals(registry.snapshot("operator-a").state, "OPEN");
  assertEquals(registry.snapshot("operator-b").state, "CLOSED");
  assertEquals(registry.acquire("operator-b", 2) !== null, true);
});

Deno.test("only one half-open probe is allowed and success closes the circuit", () => {
  const registry = new PartnerCircuitRegistry();
  registry.register("operator-a", { failureThreshold: 1, cooldownMs: 100 });

  const initial = registry.acquire("operator-a", 10)!;
  registry.recordFailure(initial, 10);
  assertEquals(registry.acquire("operator-a", 109), null);

  const probe = registry.acquire("operator-a", 110)!;
  assertEquals(probe.probe, true);
  assertEquals(registry.acquire("operator-a", 111), null);

  registry.recordSuccess(probe);
  const state = registry.snapshot("operator-a");
  assertEquals(state.state, "CLOSED");
  assertEquals(state.consecutiveFailures, 0);
  assertEquals(state.probeInFlight, false);
  assertEquals(registry.acquire("operator-a", 112)?.probe, false);
});

Deno.test("failed half-open probe reopens circuit with a new cooldown", () => {
  const registry = new PartnerCircuitRegistry();
  registry.register("operator-a", { failureThreshold: 1, cooldownMs: 100 });

  const initial = registry.acquire("operator-a", 10)!;
  registry.recordFailure(initial, 10);
  const probe = registry.acquire("operator-a", 110)!;
  registry.recordFailure(probe, 120);

  const state = registry.snapshot("operator-a");
  assertEquals(state.state, "OPEN");
  assertEquals(state.openedAt, 120);
  assertEquals(state.retryAt, 220);
});

Deno.test("stale request completion cannot close a circuit opened after it started", () => {
  const registry = new PartnerCircuitRegistry();
  registry.register("operator-a", { failureThreshold: 1, cooldownMs: 100 });

  const inFlight = registry.acquire("operator-a", 10)!;
  const anotherFailure = registry.acquire("operator-a", 11)!;
  registry.recordFailure(anotherFailure, 11);
  registry.recordSuccess(inFlight);

  assertEquals(registry.snapshot("operator-a").state, "OPEN");
});

Deno.test("status query backoff is bounded and deterministic under injected random", () => {
  assertEquals(statusQueryBackoffMs(1, 500, 5_000, 0.2, () => 0.5), 500);
  assertEquals(statusQueryBackoffMs(3, 500, 5_000, 0.2, () => 0.5), 2_000);
  assertEquals(statusQueryBackoffMs(10, 500, 5_000, 0.2, () => 0.5), 5_000);
  assertEquals(statusQueryBackoffMs(1, 500, 5_000, 0.2, () => 0), 400);
});

Deno.test("invalid circuit and backoff configuration are rejected", async () => {
  const registry = new PartnerCircuitRegistry();
  await assertRejects(
    async () => registry.register("operator-a", { failureThreshold: 0, cooldownMs: 1_000 }),
    Error,
    "INVALID_CIRCUIT_POLICY",
  );
  await assertRejects(
    async () => statusQueryBackoffMs(0),
    Error,
    "INVALID_BACKOFF_CONFIGURATION",
  );
});

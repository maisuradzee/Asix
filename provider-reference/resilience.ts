/**
 * Partner-scoped circuit breaker reference.
 *
 * Deterministic and clock-injected: no timers or background loops.
 * Each partner has independent state. A production implementation should
 * persist or reconstruct state appropriately across worker restarts and
 * coordinate it across replicas (for example via Redis/atomic DB operations).
 */

export type CircuitState = "CLOSED" | "OPEN" | "HALF_OPEN";

export interface CircuitPolicy {
  failureThreshold: number;
  cooldownMs: number;
}

export interface CircuitPermit {
  partnerCode: string;
  generation: number;
  permitId: number;
  probe: boolean;
}

export interface CircuitSnapshot {
  partnerCode: string;
  state: CircuitState;
  consecutiveFailures: number;
  openedAt?: number;
  retryAt?: number;
  probeInFlight: boolean;
  generation: number;
}

interface InternalCircuit extends CircuitSnapshot {
  policy: CircuitPolicy;
  activeProbePermitId?: number;
}

export class PartnerCircuitRegistry {
  private readonly circuits = new Map<string, InternalCircuit>();
  private nextPermitId = 1;

  register(partnerCode: string, policy: CircuitPolicy): void {
    if (!partnerCode || partnerCode.length > 128 ||
        !Number.isInteger(policy.failureThreshold) ||
        policy.failureThreshold < 1 || policy.failureThreshold > 100 ||
        !Number.isInteger(policy.cooldownMs) ||
        policy.cooldownMs < 100 || policy.cooldownMs > 3_600_000) {
      throw new Error("INVALID_CIRCUIT_POLICY");
    }

    const existing = this.circuits.get(partnerCode);
    if (existing) {
      existing.policy = policy;
      return;
    }

    this.circuits.set(partnerCode, {
      partnerCode,
      state: "CLOSED",
      consecutiveFailures: 0,
      probeInFlight: false,
      generation: 0,
      policy,
    });
  }

  acquire(partnerCode: string, nowMs: number): CircuitPermit | null {
    const circuit = this.get(partnerCode);
    this.validateNow(nowMs);

    if (circuit.state === "CLOSED") {
      return {
        partnerCode,
        generation: circuit.generation,
        permitId: this.nextPermitId++,
        probe: false,
      };
    }

    if (circuit.state === "OPEN") {
      if (circuit.retryAt === undefined || nowMs < circuit.retryAt) return null;
      circuit.state = "HALF_OPEN";
      circuit.probeInFlight = false;
      circuit.activeProbePermitId = undefined;
      circuit.generation += 1;
    }

    if (circuit.probeInFlight) return null;

    const permitId = this.nextPermitId++;
    circuit.probeInFlight = true;
    circuit.activeProbePermitId = permitId;
    return {
      partnerCode,
      generation: circuit.generation,
      permitId,
      probe: true,
    };
  }

  recordSuccess(permit: CircuitPermit): void {
    const circuit = this.get(permit.partnerCode);
    if (permit.generation !== circuit.generation) return;

    if (permit.probe) {
      if (circuit.state !== "HALF_OPEN" ||
          circuit.activeProbePermitId !== permit.permitId) return;
      circuit.state = "CLOSED";
      circuit.consecutiveFailures = 0;
      circuit.openedAt = undefined;
      circuit.retryAt = undefined;
      circuit.probeInFlight = false;
      circuit.activeProbePermitId = undefined;
      circuit.generation += 1;
      return;
    }

    if (circuit.state === "CLOSED") circuit.consecutiveFailures = 0;
  }

  recordFailure(permit: CircuitPermit, nowMs: number): void {
    const circuit = this.get(permit.partnerCode);
    this.validateNow(nowMs);
    if (permit.generation !== circuit.generation) return;

    if (permit.probe) {
      if (circuit.state !== "HALF_OPEN" ||
          circuit.activeProbePermitId !== permit.permitId) return;
      this.open(circuit, nowMs);
      return;
    }

    if (circuit.state !== "CLOSED") return;
    circuit.consecutiveFailures += 1;
    if (circuit.consecutiveFailures >= circuit.policy.failureThreshold) {
      this.open(circuit, nowMs);
    }
  }

  snapshot(partnerCode: string): CircuitSnapshot {
    const circuit = this.get(partnerCode);
    return {
      partnerCode: circuit.partnerCode,
      state: circuit.state,
      consecutiveFailures: circuit.consecutiveFailures,
      openedAt: circuit.openedAt,
      retryAt: circuit.retryAt,
      probeInFlight: circuit.probeInFlight,
      generation: circuit.generation,
    };
  }

  private open(circuit: InternalCircuit, nowMs: number): void {
    circuit.state = "OPEN";
    circuit.openedAt = nowMs;
    circuit.retryAt = nowMs + circuit.policy.cooldownMs;
    circuit.probeInFlight = false;
    circuit.activeProbePermitId = undefined;
    circuit.generation += 1;
  }

  private get(partnerCode: string): InternalCircuit {
    const circuit = this.circuits.get(partnerCode);
    if (!circuit) throw new Error("PARTNER_CIRCUIT_NOT_REGISTERED");
    return circuit;
  }

  private validateNow(nowMs: number): void {
    if (!Number.isSafeInteger(nowMs) || nowMs < 0) throw new Error("INVALID_CIRCUIT_TIME");
  }
}

/**
 * Backoff for safe, read-only status inquiries only.
 * Financial debit/credit commands must not be blindly retried by this helper.
 */
export function statusQueryBackoffMs(
  attempt: number,
  baseMs = 500,
  maxMs = 30_000,
  jitterRatio = 0.2,
  random = Math.random,
): number {
  if (!Number.isInteger(attempt) || attempt < 1 || attempt > 20 ||
      !Number.isInteger(baseMs) || baseMs < 1 ||
      !Number.isInteger(maxMs) || maxMs < baseMs ||
      !Number.isFinite(jitterRatio) || jitterRatio < 0 || jitterRatio > 0.5) {
    throw new Error("INVALID_BACKOFF_CONFIGURATION");
  }
  const randomValue = random();
  if (!Number.isFinite(randomValue) || randomValue < 0 || randomValue >= 1) {
    throw new Error("INVALID_RANDOM_SOURCE");
  }
  const exponential = Math.min(maxMs, baseMs * (2 ** (attempt - 1)));
  const jitter = (randomValue * 2 - 1) * jitterRatio;
  return Math.max(1, Math.min(maxMs, Math.round(exponential * (1 + jitter))));
}

# Provider reference contracts

`contracts.ts` contains dependency-free TypeScript interfaces for the future B2B adapter boundary.

It is intentionally not imported by the current game frontend or the active `super-worker` V25 Edge Function. Do not interpret these types as a deployed API or complete implementation.

Before use:
1. Place the contracts in a separately owned provider service package.
2. Add runtime validation (for example, Zod or equivalent) at all trust boundaries.
3. Implement currency-exponent resolution from a versioned registry.
4. Implement durable persistence, idempotency, transactional outbox and status-query workers.
5. Add partner-specific adapter implementations and contract tests.
6. Ensure the database ledger posting procedure enforces per-currency balanced journals.

## Local operator-wallet simulator

A mock operator wallet is available under `provider-reference/simulator/`.

- Run instructions: `provider-reference/simulator/README.md`
- Server: `provider-reference/simulator/server.ts`
- Automated tests: `provider-reference/simulator/server_test.ts`

The simulator is local-only and in-memory. It exercises idempotency, delayed status resolution, simulated response loss after acceptance and refund caps. It is not deployable production code.

## Provider launch and resilience references

- `launch_service.ts`: verifies partner policy and issues short-lived, one-use launch tokens. Only token hashes are persisted through the injected store interface.
- `launch_service_test.ts`: launch policy, token expiry and replay tests.
- `resilience.ts`: partner-scoped circuit breaker and bounded read-only status-query backoff.
- `resilience_test.ts`: partner isolation, open/half-open/closed transitions and backoff tests.

The launch-token store and circuit state coordination must be implemented with durable shared infrastructure before multi-replica production use. Current tests use in-memory stores and do not prove distributed atomicity.

## Provider gateway handler

- `provider_gateway.ts`: server-to-server signed Launch endpoint handler that combines HMAC verification, partner rate limiting, policy-gated Launch Service and sanitized responses.
- `provider_gateway_test.ts`: valid signed launch, invalid signature, rate limit, malformed JSON and unknown route tests.

The handler has dependency-injected key, nonce, launch-token and rate-limit stores. Production use requires durable shared implementations, request metrics, network-level controls and deployment behind the approved provider API hostname. It is not attached to a Supabase Edge Function or public endpoint.

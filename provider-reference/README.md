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

## Partner signature profiles

- `partner_auth.ts`: ASIX's proposed host-bound HMAC-SHA256 partner API profile.
- `partner_auth_ecdsa.ts`: separate ECDSA P-256/SHA-256 raw-payload signature verifier reference for partners whose official protocol documents this form.
- `partner_auth_ecdsa_test.ts`: DER signature parsing, POST body, GET query, tamper and size-limit tests.

These profiles are not interchangeable. Choose a profile only from the partner's current signed technical specification. The ECDSA reference intentionally does not invent timestamp/nonce headers absent from the partner contract; replay prevention remains an application-level idempotency and token-lifecycle requirement where the protocol provides no signed freshness fields.

## ST8 reference

- [ST8 Aggregator Reference and API Direction](../docs/ST8_AGGREGATOR_REFERENCE_AND_DIRECTION.md)
- The reviewed public ST8 document is an Operator API; it is not assumed to be a provider/developer onboarding API for ASIX.

## Protocol-neutral HTTP Wallet Adapter

- `partner_http_adapter.ts`: shared HTTPS-only adapter wrapper for partner-specific protocol mappers/signers.
- `partner_http_adapter_test.ts`: URL scope, idempotency header, timeout, response size and read-only status-query tests.

The adapter does not invent operator endpoints or authentication. Each real partner requires an approved protocol mapper and signer based on that partner's current specification. The adapter itself does not retry wallet operations.


## Provider database foundation — design only

- sql/provider_schema_proposal.sql: isolated provider_internal schema, narrow database functions, function-only runtime grants and FORCE RLS. This is not a Supabase migration and has not been applied to the live project.
- sql/provider_schema_smoke_tests.sql: disposable PostgreSQL 17 security, nonce, launch, wallet, response lifecycle and ledger smoke suite.
- sql/provider_schema_concurrency_fixture.sql: seed data for concurrent exposure and refund-cap tests.
- sql/provider_schema_wallet_response_tests.sql: leased response persistence, idempotent replay and stale-worker rejection tests.
- sql/provider_schema_status_query_recovery_tests.sql: expired read-only status-query lease retry and dead-letter tests.
- postgres_repository.ts: dependency-injected typed port; no connection or secret lookup.
- postgres_repository_test.ts: mocked repository tests, including worker-bound response persistence and scoped status reads.

Latest verified GitHub Actions run 281:
- 78 Deno tests passed, 0 failed.
- Schema applied successfully to disposable PostgreSQL 17.
- Provider DB smoke, wallet response-persistence, concurrent Bet/Refund and expired STATUS_QUERY lease recovery tests passed.
- Response persistence requires the matching worker identity, one-time lease token and an unexpired lease.
- A timed-out read-only status query is re-queued with a new token; exhausted queries are moved to DEAD_LETTER.

This is not a clean V154 restore or a live Supabase staging test. No Provider schema, role, function, trigger or migration has been created in the live ASIX project.

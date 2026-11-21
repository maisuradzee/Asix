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


## Provider database foundation — design-only assets

- sql/provider_schema_proposal.sql: proposed provider_internal schema, function-only runtime boundary, wallet transaction/outbox routines and immutable ledger posting controls. It is NOT a Supabase migration and has NOT been executed.
- sql/README.md: provisioning, review and migration-generation status.
- postgres_repository.ts: typed reference port for the proposed database functions; it does not connect to production.
- postgres_repository_test.ts: mocked repository contract tests only.

No Provider schema or database role has been created in the live project. Production use requires a verified V154 staging restore, Supabase-generated migration, dedicated database LOGIN secret, SQL review, pgTAP/concurrency tests and security advisor review.


## PostgreSQL repository and disposable database validation

- `postgres_repository.ts`: injected, typed repository port for the proposed provider_internal functions. It does not connect to any project or fetch secrets.
- `postgres_repository_test.ts`: 8 mocked adapter-contract tests.
- `sql/provider_schema_proposal.sql`: design-only database schema and narrow server-side functions.
- `sql/provider_schema_smoke_tests.sql`: SQL integration smoke suite run inside disposable PostgreSQL 17 in CI, not against Supabase.
- Latest verified CI: 73 Deno tests passed with zero failures; the disposable PostgreSQL 17 schema and smoke suite both completed successfully.

Production blockers remain: clean V154 restore, Supabase-generated migration, dedicated runtime LOGIN/secret, Supabase Data API/exposed-schema check, pgTAP and concurrency/load/failover tests against the restored staging project, and independent security review.

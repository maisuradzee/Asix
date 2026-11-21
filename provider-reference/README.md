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

- \`sql/provider_schema_proposal.sql\`: one consolidated \`provider_internal\` schema, narrow database functions, function-only runtime grants and FORCE RLS. This is not a Supabase migration and has not been applied to the live project.
- \`sql/provider_schema_smoke_tests.sql\`: disposable PostgreSQL 17 security, nonce, launch, wallet, response lifecycle and ledger smoke suite.
- \`sql/provider_schema_concurrency_fixture.sql\`: separate launch and financial concurrency fixtures.
- \`sql/provider_schema_wallet_response_tests.sql\`: leased response persistence, idempotent replay and stale-worker rejection.
- \`sql/provider_schema_status_query_recovery_tests.sql\`: expired read-only status-query lease retry and dead-letter tests.
- \`postgres_repository.ts\`: dependency-injected typed PostgreSQL port; no connection or secret lookup.
- \`postgres_repository_test.ts\`: mocked repository tests for launch creation/consumption, wallet processing, worker lease response persistence and scoped status reads.

### Launch lifecycle

1. The verified partner Launch request calls \`create_launch_session\`. Partner, game, jurisdiction, currency and currency exponent are checked against the enabled configuration.
2. \`partner_session_ref\` is the partner-scoped idempotency key. A same-identity retry reuses the existing CREATED session and revokes any older unconsumed Launch Token before issuing the new token hash. Reuse with changed player/game/currency/policy identity is rejected.
3. The raw token is generated by the trusted ASIX service; only its SHA-256 hash is stored, with an expiry no more than five minutes ahead.
4. \`consume_launch_token\` locks the partner/session identity, consumes the token once and changes the session from CREATED to ACTIVE in the same database transaction.
5. Replaying, revoking or expiring a token returns no session. A session already ACTIVE is never relaunched by a retry.

The create/reissue and consume routines use the same partner/session advisory lock so two replicas cannot create split sessions or race a token reissue against token consumption.

### Latest verified validation

GitHub Actions run #307:
- 80 Deno tests passed, 0 failed.
- The consolidated SQL schema applied successfully to disposable PostgreSQL 17.
- Database smoke tests passed, including one-time nonce/Launch Token use, session activation, reissue, old-token revocation, post-activation no-relaunch and session-reference conflict.
- Concurrent Launch test passed with two independent PostgreSQL clients: one partner session was created, one new token remained usable, and the earlier token was revoked.
- Concurrent Bet exposure and partial Refund caps passed.
- Wallet response lifecycle, worker-lease binding and status-query lease recovery passed.

This is disposable vanilla PostgreSQL 17 CI, not a clean V154 restore or a live Supabase staging test. No Provider schema, role, function, trigger or migration has been created in the live ASIX project.

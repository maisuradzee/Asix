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

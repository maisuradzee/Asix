# Provider SQL proposal assets

These files are reference material only. Nothing under this directory is a Supabase migration.

- provider_schema_proposal.sql: draft-only schema and routines. Do not execute on the live ASIX project.
- The SQL has not been run through PostgreSQL and is not certified syntax or a completed migration.
- Supabase CLI is unavailable in the current authoring environment; therefore no migration filename has been generated and no file has been placed in supabase/migrations/.

Once V154 has been restored into isolated staging and the schema reviewed:
1. Install/verify Supabase CLI and inspect supabase --help.
2. Run supabase migration new provider_internal_foundation.
3. Move the reviewed SQL into the generated migration file.
4. Apply to isolated staging only.
5. Run pgTAP, role/grant/RLS tests, concurrency/failure-injection tests and advisors.
6. Re-run existing ASIX Q-CARD and wallet smoke tests before any production decision.

The role LOGIN password and database URL must be provisioned separately through the approved secret process, never embedded here.

## Disposable PostgreSQL CI

- `provider_schema_smoke_tests.sql` runs in the dedicated `provider-database-sql` CI job against a disposable `postgres:17` container only.
- Latest verified CI run: 73 Deno tests passed, 0 failed, and SQL smoke test emitted `PROVIDER_DATABASE_SMOKE_TESTS_PASSED`.
- The smoke run exercises role/schema grants, RLS FORCE, nonce uniqueness, one-use Launch Token, wallet idempotency, open exposure, dispatch lease expiry/UNKNOWN status-query queue, refund lineage/cap, cumulative win cap, balanced Ledger posting and posted journal/entry immutability.
- This is not a restore of the ASIX V154 project and does not establish Supabase-specific Data API configuration, current V154 compatibility, production throughput or migration readiness.


- `provider_schema_concurrency_fixture.sql`: disposable data fixture for parallel Bet-exposure and Refund-cap checks.
- The CI then launches two independent PostgreSQL clients at the same time for each pair. Exactly one of two 1,000-minor-unit Bets must be accepted with a 1,500 exposure cap, and exactly one of two 300-unit Refunds must be accepted against a 500-unit original Bet.
- Latest verified CI markers: `PROVIDER_DATABASE_SMOKE_TESTS_PASSED` and `PROVIDER_CONCURRENT_FINANCIAL_LIMIT_TESTS_PASSED`.

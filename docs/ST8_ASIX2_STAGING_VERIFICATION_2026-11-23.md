# ST8 Asix #2 staging verification — 23 November 2026

**Scope:** staging-only v0.6.0 verification record. This PR remains documentation-only: it does not contain the candidate Gateway source, does not deploy an Edge Function, and is not a Production rollout.

## Verified staging state

- Project: Asix #2, ref `liiowoclsddlywabvmcg`, PostgreSQL 17.12, `ACTIVE_HEALTHY`.
- Five applied migration history records:
  - `20261122132500` — `20261121000100_st8_seamless_wallet`
  - `20261122161805` — `20261121000200_st8_reconciliation_snapshot`
  - `20261122161819` — `20261121000300_st8_foreign_key_indexes`
  - `20261123065629` — `reconciliation_processed_time`
  - `20261123065640` — `cancel_tombstone_reconciliation`
- Ten private `provider_internal.st8_*` tables have RLS and FORCE RLS. `anon`, `authenticated`, and `service_role` have no direct schema USAGE or table grants. ST8 RPC execution remains service-role-only.
- ST8 wallet and append-only ledger remain isolated from ASIX demo/QCard. The blank Asix #2 staging project has no ASIX demo-wallet tables, and no cross-product triggers were installed.
- All ten ST8 tables have zero rows after rollback testing.
- Edge Functions list is empty; the ST8 Gateway is not deployed.

## v0.6.0 reconciliation corrections

- ST8 Query API `kind` is compared to local `action_kind`; the separate `provider_kind` field is compared to local `provider_kind`.
- Provider cancellation rows are matched by ST8 cancel `transaction_id` to local `cancel_id`, and `reference_transaction_id` is validated.
- Pending-reference cancels remain unresolved until the original arrives; the reconciler does not invent an amount and does not auto-adjust a wallet.
- The local read-only snapshot now uses ST8 `processed_at` windows, rather than local row creation timestamps.
- A metadata-only trigger enriches a cancel tombstone when its original transaction arrives later. It copies the original site/currency/amount/player/game metadata, preserves the original cancel `processed_at`, and does not perform a cash movement.

## Live staging test evidence

- Full post-migration SQL verifier: `ST8_STAGING_SCHEMA_VERIFICATION_PASSED`.
- Rollback-only late-cancel regression: `ST8_CANCEL_TOMBSTONE_RECONCILIATION_TEST_PASSED`. The original transaction remained `CANCELLED_BEFORE_ORIGINAL` with zero applied cash movement; the tombstone metadata was completed; the transaction ended with ROLLBACK.
- All ten ST8 tables were re-counted after rollback and remained empty.
- Security Advisor: 10 INFO `rls_enabled_no_policy` findings. These are intentional for the private schema because no application role has schema USAGE/table grants.
- Performance Advisor: 8 INFO `unused_index` findings, expected before any staging workload.
- Health Advisor: 0 findings.

## Local candidate verification

- Node.js 22.16 suite: 52/52 tests PASS.
- Static architecture/security contracts: 110/110 PASS.
- TypeScript 5.8.3 strict source compile: PASS.
- All 14 operational/test `.mjs` syntax checks: PASS.
- Inner SHA-256 manifest: 52 files verified.
- ZIP integrity: PASS. Exact extracted v0.6.0 ZIP re-ran verification with `VERIFY_SUMMARY: 18 PASS, 0 FAIL`.
- Deno CLI is not installed; Deno-native tests were skipped, not counted as passed.

## External release blockers

ST8 Operator Code, Site ID, sandbox API origin, ST8 public key, ASIX public-key registration confirmation and ST8 Testing Tool credentials are still unavailable. Supabase Edge Function secrets have not been configured. No live ST8 API request, callback acceptance test or real Transactions API reconciliation was run. Gateway deployment remains blocked until onboarding credentials, secure secret configuration and the staging acceptance gate are available.

KYC/AML, trusted age/geolocation, self-exclusion, PSP/settlement, jurisdiction/legal approval, independent penetration test, PostgreSQL multi-session concurrency/load tests, backup/restore rehearsal, persisted mismatch queue, alerting/scheduler and ledger-direction/accounting reconciliation remain outstanding.

## Production boundary

No Production migration, Edge Function deployment, secret change, user mapping, wallet movement or QCard change was performed. Existing ASIX Production and `super-worker V25` remain unchanged. This PR is documentation-only and must not be described as a deployed or ST8-certified integration.

The separately attached v0.6.0 candidate archive and Georgian staging report are provided with the ChatGPT response. ZIP SHA-256: `75bd4edc1e8d35c155afc73c42b099622d4a3e10299cb66190e922b8574b3469`.

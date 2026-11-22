# ST8 Asix #2 staging verification — 23 November 2026

**Scope:** staging-only verification record. The separately attached local candidate archive has advanced to v0.5.8; this GitHub PR remains documentation-only and does not contain the candidate Gateway source or deploy an Edge Function.

## Verified staging state

- Project: Asix #2, ref `liiowoclsddlywabvmcg`, PostgreSQL 17.12, ACTIVE_HEALTHY.
- Applied migrations: `20261121000100_st8_seamless_wallet`, `20261121000200_st8_st8_reconciliation_snapshot`, `20261121000300_st8_foreign_key_indexes`.
- Ten private `provider_internal.st8_*` tables have RLS and FORCE RLS. Client roles have no direct private schema/table access. ST8 RPC execution is restricted to `service_role`.
- ST8 wallet and ledger remain isolated from ASIX demo wallet and QCard.
- All ten ST8 tables have zero rows; no Edge Functions are currently deployed to this staging project.
- Health Advisor: 0 findings. Private-schema RLS INFO findings are intentional because direct grants are absent; unused-index INFO findings are expected on the empty staging database.

## v0.5.8 implementation and verification

- Current Supabase `sb_secret_*` keys are sent only in `apikey`, never as Bearer JWTs. Legacy `service_role` JWT fallback continues to use both headers.
- The current publishable key is sent in `apikey`; the real ASIX user access JWT remains a separate Bearer token for `/launch`.
- Candidate `supabase/config.toml` sets `verify_jwt = false` for `st8-gateway` only. The handler performs route-specific authorization: `/launch` validates the Supabase user JWT, callbacks validate the exact raw-body ST8 P-256 signature, and `sync-games` checks its independent constant-time secret. This config is not deployed; `super-worker` V25 remains unchanged with `verify_jwt=true`.
- Node.js 22.16 runtime/Gateway/export/reconciliation/preflight suite: 39/39 PASS.
- Static security and architecture contracts: 96/96 PASS.
- TypeScript 5.8.3 strict compile: PASS.
- All 12 operational/test `.mjs` syntax checks: PASS.
- Inner SHA-256 manifest: 47 files verified.
- Exact v0.5.8 ZIP extracted and verified in-place: `VERIFY_SUMMARY: 16 PASS, 0 FAIL`. ZIP integrity and external checksum also PASS.
- Full live catalog-sync transactional SQL regression suite: `ST8_CATALOG_SYNC_TRANSACTIONAL_TEST_PASSED`. Covered manual approval preservation, provider disablement/removal, normalized duplicate game IDs, case-insensitive duplicate developer IDs, empty snapshot rejection without partial disablement, stale snapshot rejection, and active multi-site guard. Entire transaction was rolled back.
- Live read-only blank-staging verifier: `ASIX2_ST8_BLANK_STAGING_VERIFICATION_PASSED`. It checks 10 forced-RLS tables, no direct private schema/table grants, service-role-only RPCs, fail-closed provider catalog default, zero-balance wallet, append-only ledger/audit guards, no cross-product triggers, no ASIX/QCard wallet references, and no fixture/user/wallet data.
- A separate read-only count after rollback confirmed that all ten ST8 tables remain at zero rows.
- Deployment preflight reports staging target PASS, Gateway credentials BLOCKED, ST8 acceptance BLOCKED, and Deno CLI NOT_INSTALLED. Secret values are not printed.
- A full wallet/callback E2E test requiring a temporary `auth.users` row was not executed: the database write was blocked by tool safety controls. No workaround was attempted and no synthetic user was created.
- Deno-native tests were not run because Deno CLI is not installed.

## Outstanding external release gates

No ST8 Operator Code, Site ID, sandbox API origin, ST8 public key, ASIX public-key registration confirmation, or ST8 Testing Tool credentials are available. Supabase Edge Function secrets are not configured. The `st8-gateway` function is therefore **not deployed**; the staging preflight gate is intentionally not bypassed.

KYC/AML, trusted age/geolocation checks, self-exclusion provider, PSP/settlement, jurisdiction/legal sign-off, independent penetration testing, database concurrency/load tests, backup/restore/rollback rehearsal, and official ST8 Testing Tool acceptance remain outstanding.

## Production boundary

No production migration, Edge Function deployment, secret change, wallet mutation, synthetic user, or funding transaction was performed. Existing ASIX Production and `super-worker V25` remain unchanged.

The v0.5.8 candidate ZIP, Georgian staging report, and SHA-256 checksum are attached separately in the ChatGPT response. ZIP SHA-256: `ab293260907f96256079a222648695181c3ad8b9253bef550bd8ac02cefebeb8`. This PR is documentation-only and does not represent a deployed ST8 integration.

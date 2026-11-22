# ST8 Asix #2 staging verification — 23 November 2026

**Scope:** staging-only verification record. The separately attached local candidate archive has advanced to v0.5.7; this GitHub PR remains documentation-only and does not contain the candidate Gateway source or deploy an Edge Function.

## Verified staging state

- Project: Asix #2, ref `liiowoclsddlywabvmcg`, PostgreSQL 17.12, ACTIVE_HEALTHY.
- Applied migrations: `20261121000100_st8_seamless_wallet`, `20261121000200_st8_reconciliation_snapshot`, `20261121000300_st8_foreign_key_indexes`.
- Ten private `provider_internal.st8_*` tables have RLS and FORCE RLS. Client roles have no direct private schema/table access. ST8 RPC execution is restricted to `service_role`.
- ST8 wallet and ledger remain isolated from ASIX demo wallet and QCard.
- All ten ST8 tables have zero rows; no Edge Functions are currently deployed to this staging project.
- Health Advisor: 0 findings. Private-schema RLS INFO findings are intentional because direct grants are absent; unused-index INFO findings are expected on the empty staging database.

## Executed verification

- v0.5.7 local Node.js 22.16 runtime/Gateway/export/reconciliation/preflight suite: 37/37 PASS.
- Static security and architecture contracts: 94/94 PASS.
- TypeScript 5.8.3 strict compile: PASS.
- All 12 operational/test `.mjs` syntax checks: PASS.
- Inner SHA-256 manifest: 46 files verified.
- ZIP integrity: PASS; outer SHA-256 is recorded in the separately attached artifact checksum file.
- Live catalog-sync RPC smoke test: PASS inside a transaction followed by ROLLBACK. It confirmed that new ST8 games remain disabled for ASIX manual approval, provider disablement is respected, and existing manual approval is preserved.
- Live read-only blank-staging verifier: `ASIX2_ST8_BLANK_STAGING_VERIFICATION_PASSED`. It checks 10 forced-RLS tables, no direct private schema/table grants, service-role-only RPCs, fail-closed provider catalog default, zero-balance wallet, append-only ledger/audit guards, no cross-product triggers, no ASIX/QCard wallet references, and no fixture/user/wallet data.
- v0.5.7 additionally prefers Supabase's platform-injected `SUPABASE_PUBLISHABLE_KEYS.default` and `SUPABASE_SECRET_KEYS.default` maps; legacy anon/service-role aliases are transition fallbacks only. Malformed key maps fail closed. Two preflight regression tests cover these cases.
- The deployment preflight with only the approved staging target variables reports target PASS, Gateway credentials BLOCKED, ST8 acceptance BLOCKED, and Deno CLI NOT_INSTALLED. Secret values are not printed.
- A full wallet/callback E2E test requiring a temporary `auth.users` row was not executed: the database write was blocked by tool safety controls. No workaround was attempted and no synthetic user was created.
- Deno-native tests were not run because Deno CLI is not installed.

## Outstanding external release gates

No ST8 Operator Code, Site ID, sandbox API origin, ST8 public key, ASIX public-key registration confirmation, or ST8 Testing Tool credentials are available. Supabase Edge Function secrets are not configured. The `st8-gateway` function is therefore **not deployed**; the staging preflight gate is intentionally not bypassed.

KYC/AML, trusted age/geolocation checks, self-exclusion provider, PSP/settlement, jurisdiction/legal sign-off, independent penetration testing, database concurrency/load tests, backup/restore/rollback rehearsal, and official ST8 Testing Tool acceptance remain outstanding.

## Production boundary

No production migration, Edge Function deployment, secret change, wallet mutation, synthetic user, or funding transaction was performed. Existing ASIX Production and `super-worker V25` remain unchanged.

The v0.5.7 candidate ZIP, Georgian staging report, and SHA-256 checksum are attached separately in the ChatGPT response. This PR is documentation-only and does not represent a deployed ST8 integration.

# ASIX × ST8 — Asix #2 v0.7.3 staging audit

**Date:** 23 November 2026  
**Candidate:** v0.7.3  
**Database schema:** v0.7.2 (unchanged)  
**Target:** Asix #2 / `liiowoclsddlywabvmcg`

## v0.7.3 changes

- Reconciliation comparison hashing sorts local transaction, cancel tombstone, ledger and accounting mismatch arrays by stable identity. Reordering an otherwise identical snapshot no longer produces a false distinct run.
- Canonical JSON hashing fails closed for `undefined`, non-finite numbers, cyclic values and non-plain objects.
- Alert delivery resolves the exact allowlisted hostname and rejects the entire DNS answer set if any IP is private, loopback, link-local, reserved or otherwise non-global.
- HTTPS transport pins the socket lookup to a vetted IP while retaining TLS hostname verification. Redirects are not followed; DNS is rechecked for each delivery.
- Added regression coverage for unordered snapshots, malformed hash inputs, public/private IPv4 and IPv6, mixed DNS answers and refusal before socket creation.

## Local verification

- Node runtime suite: **68/68 PASS**.
- Static security/architecture contracts: **130/130 PASS**.
- TypeScript strict compile: **PASS**.
- Operational/test script syntax checks: **18/18 PASS**.
- `npm run verify`: **22 PASS / 0 FAIL**.
- Inner package manifest: **65/65 SHA-256 files verified**.
- Deno-native tests: **SKIPPED** — Deno CLI is unavailable; not counted as passed.
- The exact extracted v0.7.3 archive was independently re-run through `npm run verify`: **22 PASS / 0 FAIL**.

## Read-only staging recheck

- Project status: `ACTIVE_HEALTHY`; PostgreSQL `17.12.0.000`.
- Migration history: **9 entries**; latest schema migration remains `20261123073723_st8_reconciliation_snapshot_idempotency`.
- Private schema: **14/14** tables with RLS and FORCE RLS.
- All 14 ST8 tables have **zero rows**.
- `anon`, `authenticated`, and `service_role` have no `USAGE` on `provider_internal`.
- Security Advisor: 14 INFO `rls_enabled_no_policy` findings (expected for the private schema); Performance Advisor: 11 INFO `unused_index` notices on empty staging; Health Advisor: **0 findings**.
- Edge Functions deployed: **0**.

No SQL migration, Supabase schema change or Edge Function deployment was made for v0.7.3. The staging checks were read-only.

## External gates

ST8 partner onboarding values, public-key registration confirmation, accepted game/developer/jurisdiction codes, Testing Tool credentials, approved alert receiver/secret, Deno runtime tests, load/concurrency/reversal tests, backup/restore rehearsal, independent penetration testing, and legal/PSP/KYC/AML approvals remain outstanding. This package is not ST8-certified or production-ready.

Production project `kxcuvagipqiqisowtgys`, `super-worker V25`, QCard and existing ASIX wallet data remain untouched.

**Complete source package SHA-256:** `73000a010e7037913a2e0cf62fc2dd4f38ef8a84feaaffd1f49adc15463de8d6`.

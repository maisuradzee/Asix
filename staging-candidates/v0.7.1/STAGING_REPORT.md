# ASIX × ST8 — Asix #2 v0.7.1 alert operations hardening report

**Date:** 23 November 2026  
**Project:** `Asix #2` (`liiowoclsddlywabvmcg`) / `dragon.nika`  
**Database state:** v0.7.0 operations migration remains applied; no new database migration was required by v0.7.1.  
**Release scope:** staging-only local operational tooling. No Edge Function deployment and no live ST8 call.

## Changes

1. Alert webhook destination now requires `ST8_ALERT_WEBHOOK_ALLOWED_HOSTS`, a comma-separated exact-host allowlist. Wildcards, IP literal destinations, localhost / `.local` / `.internal` hosts, credentials, fragments, custom ports and non-HTTPS protocols are rejected.
2. Alert delivery now claims one queue row per worker lease. The script completes the bounded webhook request and lease-finish RPC before it claims another row. This avoids pre-leasing later rows that might expire while a slow earlier delivery is in progress.
3. The receiver contract remains signed HMAC-SHA256 over the timestamp and exact raw JSON body, must enforce timestamp freshness, and must deduplicate `x-asix-alert-idempotency-key`. The dispatcher does not follow redirects and does not log response bodies or secrets.
4. No webhook URL, secret, scheduler, or notification provider was configured. Alert delivery remains manual and disabled until an approved receiver exists.

## Local verification

- Node runtime tests: **62/62 PASS**.
- Static architecture/security contracts: **124/124 PASS**.
- TypeScript strict compile: PASS (Gateway source unchanged).
- All packaged `.mjs` syntax checks: PASS.
- SHA-256 manifest: regenerated for this v0.7.1 candidate; full package verification passed with 22 PASS / 0 FAIL.
- Deno-native Edge tests: skipped because the Deno CLI is not installed; not counted as passed.

## Staging boundary

The existing Asix #2 database still has 14 forced-RLS private tables, no direct private schema/table grants, zero ST8 table rows, and eight migration history entries (including the duplicate idempotent FK-index migration entry) as documented in the v0.7.0 database report. The accounting snapshot on this empty environment previously returned zero wallet/debt/ledger mismatches. v0.7.1 makes no Supabase database changes.

**Production boundary:** legacy ASIX Production `kxcuvagipqiqisowtgys`, its `super-worker V25`, QCard and existing ASIX wallet data remain untouched.

## Still blocked by external onboarding

ST8 Operator Code, Site ID, sandbox API/launcher origin, ST8 public key, ASIX public-key registration confirmation, accepted game/developer codes, approved jurisdiction values and ST8 Testing Tool credentials remain unavailable. Supabase Gateway secrets are not configured; `st8-gateway` remains undeployed. No real callback acceptance, live Query API reconciliation, alert delivery or ST8 certification has occurred.

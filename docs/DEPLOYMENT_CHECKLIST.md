# ASIX deployment and casino handover checklist — Stage 20

## 1. Complete source export
1. Use the handover ZIP and install Supabase CLI plus Docker Desktop/Engine.
2. Authenticate with Supabase CLI and run `scripts/export_casino_handover.ps1` on Windows or `scripts/export_casino_handover.sh` on macOS/Linux.
3. Confirm the generated `database/schema.sql` and `database/database.types.ts` exist and are non-empty; run `scripts/verify_handover_export.sh <generated-export-folder>` on macOS/Linux.
4. Give the generated handover ZIP to the casino only after reviewing the SQL and confirming it contains no credentials or unapproved production data.

## 2. Financial rules (current and authoritative)
- 5% of gross Entry Fee is the ASIX commission.
- The entire remaining 95% is funded into the prize pool immediately at deal start.
- No staged prize growth, no four-cut/four-deal increase, and no additional 3% reserve.
- The existing commission settlement trigger is the only wallet-credit path for platform commission. The game-ledger commission allocation is audit-only; do not credit twice.
- Example: 6.00 ₾ gross Entry Fee = 0.30 ₾ ASIX commission + 5.70 ₾ immediate prize pool.

## 3. Frontend
1. In the generated export, replace the destination URL and publishable/anon key in `frontend/supabase-config.template.js`.
2. Never put `SERVICE_ROLE_KEY` in browser code or any file under `frontend/`.
3. Configure Auth Site URL and redirect URLs for the destination domain.
4. Confirm required tables are in the Realtime publication before enabling live play.

## 4. Edge Function
- The deployed source project has `super-worker` V25 active, `verify_jwt=true`.
- The local V26 candidate is a separate candidate and is not deployed.
- Downloaded Edge Function files are in the generated export's `edge-functions/` directory.
- Configure `PROJECT_URL`, `PUBLIC_KEY`, and `SERVICE_ROLE_KEY` through the recipient project's secure secret manager. Keep the service-role key server-only and keep JWT verification enabled.

## 5. Database restore and patches
1. Restore the generated current-state `database/schema.sql` into a clean, new casino-controlled Supabase project, never the source project.
2. Review extension availability, roles, grants, default privileges, RLS and Realtime membership before enabling users.
3. Create the casino commission-recipient Auth user and run `supabase/seeds/DESTINATION_BOOTSTRAP_5_PERCENT.sql` after replacing its UUID marker.
4. Confirm the commission setting is enabled, currency `GEL`, and rate `500` basis points.
5. Review V157 against the exported schema and apply it only to disposable staging after source guards are checked; V157 needs the commission recipient row configured first. It has static review only and has not been PostgreSQL-compiled or staging-tested.
6. Run `supabase/exports/read_only_stage19_validation.sql` against staging.
7. Test complete 2-, 3-, 4- and 5-player deals; early finish; normal finish; cancel/refund; side pots; uncalled-bet refunds; cashout; bot-session buy-in/cashout; and duplicate/retry idempotency.
8. Reconcile every completed deal to: gross Entry Fee = 5% ASIX commission + 95% full player prize pool. Confirm no per-cut prize increase, no growth-release row, no reserve allocation and no duplicate commission credit.

## 6. Platform settings outside the SQL schema
Auth users/passwords, Storage object bytes, project API keys, JWT signing keys, Edge secret values, SMTP/OAuth providers, redirect URLs and some Realtime/Storage configuration are not included in the default application-schema dump. Recreate them separately in the destination project using `docs/SECURITY_AND_DATA_HANDOVER.md`.

## 7. Production safety
- Do not apply recovered historical patches to an empty database as though they are the complete migration chain.
- Do not apply V157 to source production from this archive.
- Use the exact native dump as the current schema snapshot; the list of 128 migration versions is history metadata, not 128 recoverable SQL files.
- Before public launch, enable Auth leaked-password protection, review redirects/secrets, and complete the Auth/RLS/service-role review.

## Current source status
Read-only inspected 2026-11-19. Source project is ACTIVE_HEALTHY, PostgreSQL `17.11.0.019`, latest migration V154 (`20261118093932`), 128 migration records, 73 application SQL functions, 14 public base tables, 2 views, 16 public triggers, 10 public RLS policies. No source production modifications were made while preparing this package.

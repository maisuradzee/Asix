# ASIX casino handover — export and restore runbook

## 1. Source baseline (read-only inspected 2026-11-19)

| Item | Verified value |
|---|---|
| Supabase project | `Asix` (`kxcuvagipqiqisowtgys`) |
| Region | `ap-south-1` |
| PostgreSQL | `17.11.0.019` |
| Project status | `ACTIVE_HEALTHY` |
| Latest applied migration | `20261118093932` (V154) |
| Migration history rows | 128 |
| Application functions | 73 (`public` + `asix_internal`) |
| Public base tables | 14 |
| Public views | 2 |
| Public non-internal triggers | 16 |
| Public RLS policies | 10 |
| Active Edge Function | `super-worker`, V25, `verify_jwt=true` |

The 73 function definitions and 30,172-character type generation were inspected through the connected Supabase source workspace, but they have not been materialized as local standalone files in this kit. The local export command is the authoritative way to obtain these exact files.

## 2. Export from the existing source project

Use one of the following commands from the extracted Stage20 folder:

- Windows: `powershell -ExecutionPolicy Bypass -File .\scripts\export_casino_handover.ps1`
- macOS/Linux: `bash ./scripts/export_casino_handover.sh`

Prerequisites:

- Official Supabase CLI installed and authenticated (`supabase login`).
- Docker Desktop / Docker Engine available for the CLI's database dump container.
- An account that can access the existing ASIX Supabase project.
- The PostgreSQL database password, entered locally into the CLI prompt if needed. Never paste it into ChatGPT or a source file.

The exporter produces a timestamped directory and ZIP containing:

```text
casino-handover-export/
  README_HANDOVER.md
  database/
    schema.sql                 # authoritative current app schema, no live rows
    roles-and-privileges.txt   # source audit: no custom app roles; grants live in schema.sql
    database.types.ts         # exact current generated API types
    migration-history.txt     # applied migration version/name inventory
  edge-functions/
    ...                       # all deployed function source downloaded by CLI
  frontend/
    AsixgameV153.html
    supabase-config.template.js
  sql-reference/
    ...                       # recovered SQL patches and read-only checks
  metadata/
    source-project.json
    functions-list.txt
    cli-version.txt
  SHA256SUMS.txt
```

`schema.sql` is the clean current-state schema snapshot for the application schemas `public` and `asix_internal`. It is the practical baseline for rebuilding the current database state; it does not require the casino to replay 128 historical migrations. `migration-history.txt` records migration metadata, not every historical migration file body.

## 3. Restore into a new casino-controlled Supabase project

1. The casino creates a new Supabase project and provides its project ref to its own administrator. Use a destination project running PostgreSQL 17 or a verified compatible version.
2. The administrator reviews `schema.sql`, the extension inventory and the destination Supabase default privileges. The source audit found no custom application roles; destination Supabase-managed roles are supplied by the recipient project.
3. Restore the schema into a **clean destination database**. Example (PowerShell):

```powershell
# Set this only in the current shell session using the casino's own secure DB URI.
# Do not paste it into a source file, ChatGPT, or a ticket.
psql $env:CASINO_DATABASE_URL -v ON_ERROR_STOP=1 --single-transaction -f .\database\schema.sql
```

   Example (macOS/Linux):

```bash
psql "$CASINO_DATABASE_URL" -v ON_ERROR_STOP=1 --single-transaction -f ./database/schema.sql
```

   These commands target only the database URL explicitly supplied by the casino. Verify the host/project reference before running. Do not use the source ASIX database URL. If the casino uses the Supabase SQL Editor instead, its administrator must confirm the file fits the editor's limits and execute it against the new project only.

4. Supabase-managed roles and extensions are provided by the destination platform. The dump excludes managed `auth`, `storage` and extension-owned schemas; do not create duplicate platform schemas. Verify/enable the source extensions listed in `docs/DESTINATION_BOOTSTRAP_GUIDE.md` on the destination. Review the GRANT statements and destination default privileges before allowing client access.
5. Regenerate types from the destination after any schema adjustments:

```bash
supabase gen types --lang typescript --remote=<casino-project-ref> --schema public,asix_internal > database.types.ts
```

6. Create/map the designated casino platform-recipient Auth user. Then edit `sql-reference/DESTINATION_BOOTSTRAP_5_PERCENT.sql`, replacing its destination Auth UUID placeholder, and run it against the destination to insert the 500-bps commission setting and logic version 2. This seed must run only after the recipient exists and before V157 is considered. It writes the new destination UUID into `asix_platform_commission_settings.recipient_user_id`. The source UUID is not a portable identity.
7. Verify commission settings are enabled, currency is `GEL`, and `commission_rate_bps=500` using the final SELECTs from the bootstrap SQL.
8. Download/review/deploy Edge Functions. Configure their secrets in the destination project's secret manager; never include secret values in the export archive.
9. Fill `frontend/supabase-config.template.js` using the destination project's project URL and publishable/anon key only.
10. Recreate Auth redirect URLs, SMTP/OAuth providers, RLS settings, Storage buckets and CORS settings through the destination dashboard/API.
11. Run the read-only Stage19 financial/gameplay validation queries on staging, followed by functional game, refund, side-pot, cashout and commission-settlement tests.

## 4. Database data vs. schema source

A schema-only handover is the recommended first delivery to the casino. It contains the database design and executable application logic but no production rows. If the casino also needs operational data, run the optional data export only after verifying the legal basis, customer notice/consent requirements, data minimization, retention and secure transfer method. Do not include player emails, auth credentials, wallet balances or transaction history in a generic source-code handover unless they are explicitly required and authorized.

The optional application-data export covers data in `public` and `asix_internal`; it does not export Supabase-managed Auth users or Storage object bytes.

## 5. SQL schema scope and migration history

`database/schema.sql` is the **current-state application schema snapshot**, not a replay of all historical SQL migrations. It contains the live definitions for the exported application schemas. The migration list only records versions/names. The database's remote migration-history table does not retain the complete original SQL body of every migration; only a subset of historical migration files has been recovered separately.

Supabase CLI intentionally excludes the managed `auth`, `storage` and extension-owned schemas from `db dump`. This package therefore includes the ASIX application schema, not a byte-for-byte clone of Supabase's hosted platform. The recipient must recreate Auth providers, redirect URLs, SMTP, secrets, Storage buckets and object files, Realtime settings/publications and other platform configuration as described in the checklist.

## 6. Important compatibility notes

- This is a Supabase/PostgreSQL application; a generic casino database is not automatically compatible with its Auth, Realtime, Storage and Edge Function dependencies.
- The active source Edge Function remains V25; V26 is a non-deployed candidate only.
- `sql-reference/` contains selected V148/V149 reference files, not all 128 migration bodies. The current live schema dump is the restore baseline.
- V157 is a guarded optional candidate. It has only static review; PostgreSQL staging compilation and a clean restore/gameplay smoke test remain outstanding. Do not apply it automatically as part of the V154 current-state restore.
- No source production database changes were made for this handover kit.
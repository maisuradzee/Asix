# ASIX

ASIX is a Supabase-backed online multiplayer card game.

## Source baseline captured

- Frontend: `frontend/AsixgameV153.html` (V153, current available HTML source).
- Live database baseline: migration V154, PostgreSQL 17.11.0.019.
- Supabase Edge Function: `super-worker` V25 (active, JWT verification enabled).
- Migration history: 128 applied migration records; the inventory is metadata, not the original SQL bodies.
- Financial rule: 5% ASIX commission from gross Entry Fee; remaining 95% is the full prize pool from deal start. No staged prize growth or extra reserve.

## Repository map

- `frontend/AsixgameV153.html` — standalone frontend source snapshot.
- `frontend/supabase-config.template.js` — destination-safe browser configuration template; replace placeholders before launch.
- `supabase/functions/super-worker/index.ts` — exact source retrieved from deployed V25.
- `supabase/schema/schema.sql` — catalog-reconstructed current application schema snapshot (14 public tables, 73 functions, 2 views, 32 standalone indexes, 10 RLS policies, 16 triggers).
- `supabase/schema/functions_snapshot.sql` — function definitions separately exported.
- `supabase/schema/tables.json` — table metadata and relationships.
- `supabase/schema/database_objects.json` — view, policy, trigger and index metadata.
- `supabase/schema/grants.sql` and `grants_snapshot.json` — current object ACL grants / metadata.
- `supabase/types/database.types.ts` — generated TypeScript API types captured from the connected source.
- `supabase/MIGRATION_INVENTORY.md` — all 128 applied migration versions and names.
- `supabase/migrations_recovered/` — recovered V147/V148/V149 SQL references; this is not a complete historical migration chain.
- `supabase/seeds/DESTINATION_BOOTSTRAP_5_PERCENT.sql` — destination-only 5% commission and game-logic configuration seed; requires a new destination Auth recipient UUID.
- `supabase/candidates/V157_ENTRY_FEE_5_PERCENT_NO_PRIZE_GROWTH.sql` — guarded staging-only candidate; not applied to production and not PostgreSQL-compiled or smoke-tested.
- `scripts/` — Windows launcher, compatibility aliases and integrity verification scripts. The main `export_casino_handover.ps1` / `.sh` exporter source still needs to be added from the ZIP.
- `docs/` — restore, security, bootstrap, validation and blocker documentation.

## Financial rule

Gross Entry Fee: 100%. ASIX commission: 5%. Prize pool: 95%, fully funded at deal start. No 85/80/70/60% starting stages, no four-cut/four-deal growth, and no additional 3% reserve. Example: Entry Fee 6.00 ₾ → commission 0.30 ₾ → immediate prize pool 5.70 ₾.

## Exporting the current live source

The Stage21/22 handover kit includes a read-only Supabase CLI exporter. It generates a fresh current-state schema dump, exact TypeScript types, migration metadata, deployed Edge Function source, and checksums on a computer authorized to access the source project.

- Windows: install Node.js and Docker Desktop, authenticate with `npx.cmd --yes supabase@beta login`, then run `scripts\\START_EXPORT_WINDOWS.bat`.
- macOS/Linux: run `bash ./scripts/export_casino_handover.sh`.

The exporter does not push migrations, change production settings, deploy code or modify production data. Optional live application-data export requires a separate explicit confirmation and is excluded from the ordinary ZIP.

## Important restoration limits

This repository is a source handover, not a verified one-click restore:

1. The 128 migration names are known, but the remote migration history does not retain all 128 original SQL bodies. Only selected SQL references were recovered.
2. The checked-in `schema.sql` was reconstructed from live PostgreSQL catalog definitions through connected database tools. It has not been tested by restoring it into a clean isolated project; it is not a certified `pg_dump`.
3. Deployed Edge Function V25 is preserved separately at `supabase/archive/super-worker-v25/index.ts`. A non-deployed V26 candidate is included at `supabase/candidates/super-worker-v26/index.ts`; the archive shows it differs from V25 only by a TypeScript response type annotation. The uploaded candidate was reconstructed from the archived V25 source and that exact one-line change; its byte-for-byte SHA-256 parity with the archive's V26 file has not yet been verified.
4. Supabase-managed Auth users, OAuth/SMTP settings, Edge Function secret values, service-role keys, Storage object bytes and other platform-level settings are excluded.
5. No live player data, wallet balances or transaction history were exported.
6. Clean restore, PostgreSQL compilation of V157 and end-to-end gameplay/financial smoke tests remain outstanding.

## Restore safety

- Restore only into a new, isolated Supabase project belonging to the recipient; never restore over the current source project.
- Map the commission recipient to a new Auth user UUID in the destination. Never blindly reuse the source UUID.
- Run `supabase/seeds/DESTINATION_BOOTSTRAP_5_PERCENT.sql` only on the destination after creating its recipient user.
- Apply V157 only after review and isolated staging validation. Do not apply it to source production.
- Keep `verify_jwt=true` for `super-worker` unless a separately reviewed security decision changes it.

See `docs/DESTINATION_BOOTSTRAP_GUIDE.md`, `docs/SECURITY_AND_DATA_HANDOVER.md`, `docs/CASINO_HANDOVER_EXPORT_AND_RESTORE.md`, and `docs/RESTORE_BLOCKERS.md` before restore.

# ASIX

ASIX is a Supabase-backed online multiplayer card game.

## Source baseline captured

- Frontend: `frontend/AsixgameV153.html` (V153, current available HTML source).
- Live database baseline: migration V154, PostgreSQL 17.11.0.019.
- Supabase Edge Function: `super-worker` V25 (active, JWT verification enabled).
- Migration history: 128 applied migration records; the inventory is metadata, not the original SQL bodies.
- Financial rule documented for the current project: 5% ASIX commission from gross Entry Fee; the remaining 95% is the full prize pool from deal start. No staged prize growth or extra reserve.

## Repository map

- `frontend/AsixgameV153.html` — standalone frontend source snapshot.
- `supabase/functions/super-worker/index.ts` — exact source retrieved from the deployed V25 Edge Function.
- `supabase/schema/schema.sql` — catalog-reconstructed current application schema snapshot (14 public tables, 73 functions, 2 views, 32 standalone indexes, 10 RLS policies, 16 triggers).
- `supabase/schema/functions_snapshot.sql` — function definitions separately exported.
- `supabase/schema/tables.json` — table metadata and relationships.
- `supabase/schema/database_objects.json` — view, policy, trigger and index metadata.
- `supabase/schema/grants.sql` and `grants_snapshot.json` — current object ACL grants / metadata.
- `supabase/types/database.types.ts` — generated TypeScript API types.
- `supabase/MIGRATION_INVENTORY.md` — all 128 applied migration versions and names.
- `supabase/migrations_recovered/` — recovered V147/V148/V149 SQL references (not a complete historical migration chain).
- `supabase/candidates/V157_ENTRY_FEE_5_PERCENT_NO_PRIZE_GROWTH.sql` — guarded staging-only candidate; **not applied to production and not yet PostgreSQL-compiled or smoke-tested**.
- `supabase/metadata/source_project.json` — source project and installed extension / deployed function metadata.
- `docs/` — restore runbook, financial rule, validation status and known restore blockers.

## Important restoration limits

This repository is a substantially expanded source handover, but it is **not yet a verified one-click restore**:

1. The 128 migration names are known, but the remote migration history does not retain all 128 original SQL file bodies. Only selected V147–V149 references and the V157 candidate were recovered.
2. `schema.sql` was reconstructed from live PostgreSQL catalog definitions through the connected database tools. It has not yet been tested by restoring it into a clean isolated PostgreSQL/Supabase project. Treat it as a current-state schema snapshot requiring review, not as a certified pg_dump.
3. The deployed Edge Function V25 is included. A V26 candidate is mentioned in earlier validation records, but its source file was not retrievable in this session and is not included.
4. Supabase-managed Auth users, OAuth provider secrets, SMTP credentials, Edge Function secrets, service-role keys, Storage object bytes, and other platform-level settings are intentionally excluded.
5. No live player data, wallet balances, or transaction history were exported.
6. Full clean restore, PostgreSQL compilation of V157, and end-to-end gameplay smoke tests remain outstanding.

## Financial rule

Gross Entry Fee: 100%. ASIX commission: 5%. Prize pool: 95%, fully funded at deal start. No 85/80/70/60% starting stages, no four-cut/four-deal growth, and no additional 3% reserve.

## Running the frontend

Open `frontend/AsixgameV153.html` in a browser. Online functionality requires the configured Supabase project and valid client authentication. Never put a service-role key or other server secret in the frontend.

## Deployment caution

Do not apply `supabase/candidates/V157_ENTRY_FEE_5_PERCENT_NO_PRIZE_GROWTH.sql` to the live source project. It is a guarded staging candidate only. Restore and test against a disposable staging database first.

## Upload verification

See [docs/UPLOAD_AUDIT.md](docs/UPLOAD_AUDIT.md) for the fetched-back GitHub verification, security scan and remaining restore blockers.

# ASIX

ASIX online multiplayer card game.

## Repository contents

- `frontend/AsixgameV153.html` — the current frontend snapshot available in the project conversation (V153).
- `supabase/functions/super-worker/index.ts` — source retrieved from the active Supabase Edge Function deployment (v25).
- `supabase/MIGRATION_INVENTORY.md` — names and versions of migrations applied to the connected production database.

## Connected backend

- Supabase project: `kxcuvagipqiqisowtgys`
- Region: `ap-south-1`
- PostgreSQL: `17.11`
- Edge Function: `super-worker` v25, JWT verification enabled
- Applied migrations recorded: 128

## Important completeness note

This repository update preserves the source files that were directly retrievable at upload time. The original SQL migration files and any additional backend source files were not present in the repository or available from the migration-list endpoint; the migration inventory is metadata only, not a substitute for those SQL files. Secrets, API keys, and service-role credentials are intentionally not included. Do not treat this commit as a complete reproducible deployment package until the original migration SQL and any missing project configuration/assets are added.

## Frontend

Open `frontend/AsixgameV153.html` in a browser for the standalone frontend snapshot. The production game relies on the connected Supabase backend and configured environment secrets.

# Destination bootstrap configuration

The live source has two non-personal configuration rows that a schema-only dump intentionally does not copy:

- `asix_platform_commission_settings`: enabled, `GEL`, 500 bps (5%), fixed per-player fee 0, with a platform recipient Auth user.
- `qcard_game_logic_version`: singleton version `2`.

After restoring `database/schema.sql` into the casino's clean destination and creating the designated casino recipient through the destination Auth system, edit `sql-reference/DESTINATION_BOOTSTRAP_5_PERCENT.sql` and replace `REPLACE_WITH_CASINO_AUTH_USER_UUID` with that user's new destination Auth UUID. Run this seed script against the destination only.

The SQL checks that the UUID is valid and belongs to `auth.users`, then writes the 5% commission setting and logic version. It intentionally never copies the source recipient UUID, balances, wallet transaction rows or player identities.

Run this bootstrap **before** applying V157 because V157 checks for an enabled 5% GEL commission setting with a configured recipient. Verify the returned row is enabled, GEL and 500 bps.

## Required extensions

The live source catalog reported these installed extensions: `pg_stat_statements` 1.11, `pgcrypto` 1.3, `plpgsql` 1.0, `supabase_vault` 0.3.2 and `uuid-ossp` 1.1. The Supabase CLI schema dump excludes extension-owned schemas. On the destination, verify availability and enable the applicable extensions through the Supabase Dashboard's Database → Extensions page before testing functions that depend on them. Do not try to recreate `auth`, `storage`, `vault` or other managed schemas manually.

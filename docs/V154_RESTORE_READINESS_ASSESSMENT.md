# ASIX V154 Restore Readiness Assessment

**Assessment date:** 21 November 2026  
**Source project:** kxcuvagipqiqisowtgys  
**Status:** inventory verified; clean V154 restore not yet demonstrated.

## Executive result

The live ASIX Supabase project is healthy and runs PostgreSQL 17.11.0.019. Its migration history contains 128 applied migration records and ends at V154:

20261118093932_asix_v154_sync_settled_player_stacks_into_game_snapshot.

The Git repository does not contain the full historical supabase/migrations chain. It contains four recovered SQL files for V147, V148 and V149, plus reconstructed current-state schema/function/ACL snapshots. Those snapshots are useful for a destination restore exercise, but the schema file explicitly states that it is a catalog reconstruction, not the original migration source. It is therefore not yet a proven clean V154 restore package.

No Supabase staging branch currently exists for this project. No production database object or data was changed during this assessment.

## Verified source inventory

| Artifact | Observed content | Limitation |
|---|---|---|
| supabase/MIGRATION_INVENTORY.md | 128 migration versions/names; V154 is the latest | Metadata only; not SQL bodies |
| supabase/migrations_recovered/ | Four SQL files: V147, V148, V148 follow-up, V149 | Does not reproduce all 128 historical migrations |
| supabase/schema/schema.sql | 3,794 lines; current application schema reconstruction; 14 table definitions, 73 functions, 10 policies, 16 triggers | No table rows, Auth users, balances or wallet transactions; not original migration chain |
| supabase/schema/functions_snapshot.sql | 3,330 lines; 73 current function definitions | Current-state snapshot, not function migration history |
| supabase/schema/grants.sql | 568 GRANT statements for anon, authenticated, postgres and service_role | Review against default privileges and the destination project's managed roles |
| supabase/schema/database_objects.json | 2 views, 53 indexes, 10 policies, 16 triggers | Metadata export; must be checked against the SQL snapshot |
| supabase/schema/tables.json | Table/column/key metadata including managed Auth references | Metadata only; no row data |
| supabase/seeds/DESTINATION_BOOTSTRAP_5_PERCENT.sql | Destination-only 5% commission and game logic bootstrap | Requires a new destination Auth recipient UUID; not production data |

## Managed schemas and extensions

The current schema snapshot references Supabase Auth objects/functions such as auth.users, auth.uid() and auth.jwt(). A standard Supabase destination project supplies managed Auth and Storage schemas; they must not be recreated as ordinary application schemas from the reconstructed dump.

The connected source reports these installed extensions:

| Extension | Installed version | Schema |
|---|---:|---|
| pg_stat_statements | 1.11 | extensions |
| pgcrypto | 1.3 | extensions |
| plpgsql | 1.0 | pg_catalog |
| supabase_vault | 0.3.2 | vault |
| uuid-ossp | 1.1 | extensions |

Supabase CLI database dumps omit Supabase-managed schemas (including auth and storage) and extension-owned schemas. Reconcile the extension inventory on the destination before restoring dependent SQL. Vault configuration/secrets are not copied by the Provider export script.

## What can be safely exported next

The new scripts/export_asix_v154_baseline.ps1 exports only:

- roles.sql: custom role definitions using Supabase CLI --role-only.
- schema.sql: current schema using Supabase CLI dump defaults.

It does not use --data-only; no Auth user rows, player records, wallet balances, ledger entries, transaction rows, game history or other application rows are exported. Outputs go to supabase/private_exports/, which is added to .gitignore.

The script explicitly uses --remote=kxcuvagipqiqisowtgys on every dump command. This is required for deterministic targeting under Supabase CLI v3, where database commands otherwise use the local stack by default. The dump command is read-only. Supabase CLI v3 documents that schema dumps omit managed schemas and that role dumps are requested separately.

## Restore prerequisites

A staging restore still requires:

1. Run the private schema/roles export and retain its manifest/checksums outside Git.
2. Create or identify an isolated Supabase staging destination. There is currently no project branch; creating a new project/branch may incur usage charges and is not done by this assessment.
3. Ensure destination PostgreSQL and extension versions are compatible with source requirements.
4. Review managed-schema dependencies and roles/default privileges before applying files.
5. Restore schema/roles into staging only. Do not run reset, push, migration repair, or DDL against the source project.
6. Verify object counts, function signatures, policies, triggers, indexes and ACLs against the read-only source inventory.
7. Create synthetic destination Auth users/test identities and synthetic wallet/game fixtures; do not copy production financial data into GitHub or an unapproved environment.
8. Run consumer game, wallet, commission, Q-CARD and reconciliation smoke tests before any Provider schema migration.
9. Record all differences and keep the original source project unchanged.

## Stage 2A exit status

**NOT COMPLETE**

- [x] Confirm source project is active and PostgreSQL version is known.
- [x] Record V154 migration head and 128-entry migration inventory.
- [x] Inspect current schema/function/grant/object snapshots.
- [x] Identify the recovered historical migration subset.
- [x] Record installed extension versions.
- [ ] Execute private schema/roles dump using Supabase CLI v3.
- [ ] Restore to isolated staging.
- [ ] Verify full schema/roles/extensions against source.
- [ ] Run existing ASIX consumer-wallet/Q-CARD/gameplay and financial reconciliation tests.
- [ ] Capture a reproducible staging baseline.

**Decision:** do not convert the Provider SQL proposal into a Supabase migration, apply it to a live project, merge the Provider branch into production, or deploy Provider endpoints until Stage 2A has passed in isolated staging.

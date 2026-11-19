# GitHub upload audit

Audit date: 2026-11-20
Repository: https://github.com/maisuradzee/Asix
Default branch: main

## Uploaded and verified

| Component | GitHub path | Verification |
|---|---|---|
| Frontend | frontend/AsixgameV153.html | Fetched back; 278,018 characters; HTML closing tag present |
| Edge Function | supabase/functions/super-worker/index.ts | Fetched back; active deployed V25 source capture |
| Current schema | supabase/schema/schema.sql | Catalog-reconstructed; 14 tables, 73 functions, 2 views, 32 standalone indexes, 10 policies, 16 triggers |
| Function snapshot | supabase/schema/functions_snapshot.sql | 73 current function definitions |
| TypeScript types | supabase/types/database.types.ts | Generated from connected live project; 30,172 characters |
| Migration history | supabase/MIGRATION_INVENTORY.md | 128 applied version/name records |
| Grants | supabase/schema/grants.sql | 568 current object ACL grant statements; metadata also retained as JSON |
| Metadata | supabase/metadata/ | Project, installed extensions and Realtime publication inventory |
| Recovered SQL | supabase/migrations_recovered/ | V147 applied reference, V148 archive fix, V149 minimum buy-in |
| Candidate | supabase/candidates/V157_ENTRY_FEE_5_PERCENT_NO_PRIZE_GROWTH.sql | Stored as staging-only; not applied |

## Security scan

- Frontend source scanned for service-role references, sb_secret_ values, JWT-like embedded credentials and private-key blocks: no matches.
- Edge Function source scanned for literal JWT/private-key/secret values: no matches.
- Secret environment variable names remain in the Edge Function as expected; values are not present.
- No production player records, Auth users, wallet balances, or transaction history were exported.

## Not yet complete / hard blockers

1. The source migration history endpoint exposes 128 migration versions and names, not their complete historical SQL bodies. Only selected SQL files were available.
2. A V26 Edge Function candidate is mentioned in prior audit records, but its source file was not retrievable in this session. Active deployed V25 is included.
3. The current schema was reconstructed from PostgreSQL catalogs using connected database metadata. It has not been restored and tested against a clean isolated Supabase project; it is not represented as a certified CLI pg_dump.
4. Supabase-managed Auth/OAuth/SMTP settings, secrets, Storage binary objects, and other platform-level configuration are intentionally excluded.
5. No isolated staging restore or full end-to-end gameplay smoke test has been performed.

## Financial rule preserved in project docs

5% of gross Entry Fee is the ASIX commission; the remaining 95% is fully placed into the prize pool at deal start. No staged prize growth or extra reserve is used. V157 remains a guarded staging candidate and must not be applied to production without isolated testing.

## Conclusion

The GitHub repository now contains the available frontend, active backend function, current database schema snapshot, function source, generated API types, migration inventory, recovered SQL references and restore documentation. It is a substantial source handover, but not yet a fully reproducible, independently verified deployment package because of the blockers above.

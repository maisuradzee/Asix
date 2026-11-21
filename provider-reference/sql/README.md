# Provider SQL proposal assets

These files are reference material only. Nothing under this directory is a Supabase migration.

- provider_schema_proposal.sql: draft-only schema and routines. Do not execute on the live ASIX project.
- The SQL has not been run through PostgreSQL and is not certified syntax or a completed migration.
- Supabase CLI is unavailable in the current authoring environment; therefore no migration filename has been generated and no file has been placed in supabase/migrations/.

Once V154 has been restored into isolated staging and the schema reviewed:
1. Install/verify Supabase CLI and inspect supabase --help.
2. Run supabase migration new provider_internal_foundation.
3. Move the reviewed SQL into the generated migration file.
4. Apply to isolated staging only.
5. Run pgTAP, role/grant/RLS tests, concurrency/failure-injection tests and advisors.
6. Re-run existing ASIX Q-CARD and wallet smoke tests before any production decision.

The role LOGIN password and database URL must be provisioned separately through the approved secret process, never embedded here.
# Database TypeScript types export status

The connected source project generated an exact 30,172-character TypeScript type definition using PostgREST 14.18. The full output is preserved in the Supabase source-snapshot notebook (`ASIX Source Snapshots — Types, Edge Function, Migrations`).

The archive intentionally retains a clearly marked placeholder at `supabase/database.types.ts` rather than a manually reconstructed file that could silently differ from the live generator output. Re-run `supabase gen types --lang typescript --linked` after linking the intended destination/source schema, or materialize the exact notebook result into the bundle before calling the package restore-complete.

This remains one of the outstanding restore blockers listed in `docs/RESTORE_BLOCKERS.md`.

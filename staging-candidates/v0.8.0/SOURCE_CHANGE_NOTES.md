# ASIX × ST8 v0.8.0 — source change notes

## Gateway source

- `supabase/functions/st8-gateway/index.ts`
  - Adds `assertStagingProject()` to every request before route/method handling.
  - Accepts only `ST8_ENVIRONMENT=staging`, `ST8_STAGING_PROJECT_REF=liiowoclsddlywabvmcg`, and `https://liiowoclsddlywabvmcg.supabase.co`.
  - Rejects wrong project refs, other hosts, nonstandard ports, URL credentials, path, query and fragment.
  - Uses `redirect: "error"` and `cache: "no-store"` on Supabase Auth and privileged RPC fetches.

## Regression coverage

- Gateway runtime tests block Production project ref, Production Supabase URL and nonstandard port before any network call.
- Tests verify Auth/PostgREST requests reject redirects and disable caching.
- Callback retry test verifies byte-identical raw requests carry the same SHA-256 fingerprint and changed request facts carry a different fingerprint.
- Static architecture/security contracts now include universal staging pinning and transport restrictions.

## Deployment boundary

No schema migration or Supabase change is part of v0.8.0. Asix #2 remains on the previously verified v0.7.2 schema. The Gateway remains undeployed while ST8 partner onboarding and Deno/official acceptance gates are outstanding. Production and existing ASIX wallet/QCard systems remain untouched.

The complete source archive and reproducible verification evidence are supplied separately in the ChatGPT response.

# v0.8.0 — Gateway runtime staging boundary and transport hardening

- All Gateway routes now require `ST8_ENVIRONMENT=staging`, the exact approved Asix #2 project ref, and the matching HTTPS Supabase origin with no credentials, path, query, fragment or nonstandard port.
- Runtime guard rejects unsafe configuration before any Auth, PostgREST or ST8 network request.
- Supabase Auth user validation and privileged PostgREST RPC calls now use `redirect: "error"` and `cache: "no-store"`.
- Added regression coverage for Production ref/URL/port refusal, Auth/RPC redirect prevention, no-store behavior and callback request-hash retry semantics.
- This is a local source/test/documentation release. No SQL migration, staging secret change, Edge Function deployment, live ST8 request or Production change was made.

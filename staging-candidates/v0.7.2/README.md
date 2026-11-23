# ASIX × ST8 v0.7.2 — reconciliation snapshot idempotency

This is the database/runtime idempotency correction for the isolated Asix #2 staging candidate. See `STAGING_REPORT_KA.md` and `SOURCE_CHANGE_NOTES.md`. The full source ZIP is supplied separately.

Applied only to staging project `liiowoclsddlywabvmcg` with migration `20261123073723_st8_reconciliation_snapshot_idempotency`. Production and `super-worker V25` remain unchanged.

Archive SHA-256: `51257134f86dca3fd05ce593071518bfe7e899e0f3ca459991fb2b559a59995e`.

Local: 64/64 runtime, 128/128 static, strict TypeScript PASS, `npm run verify` 22 PASS / 0 FAIL. Deno tests are skipped because Deno CLI is unavailable.

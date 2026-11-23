# v0.7.3 — deterministic snapshot hashing and webhook DNS pinning

- Canonical comparison hashes now normalize local transaction, cancel, ledger and accounting mismatch arrays.
- Canonical JSON hashing rejects ambiguous or unsupported values instead of allowing unstable hashes.
- Alert webhook dispatch now checks every DNS answer for public unicast and pins HTTPS transport to vetted addresses while preserving hostname-based TLS verification.
- Added regression and static security contract tests.
- Local package changes only; no database migration or deployment.

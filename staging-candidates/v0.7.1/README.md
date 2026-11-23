# ASIX × ST8 staging candidate v0.7.1 — alert operations hardening

This folder contains the complete v0.7.1 alert-dispatcher hardening delta. It is a local/staging tooling update, not a database migration and not a deployed Edge Function.

Included:
- `dispatch-st8-reconciliation-alerts.mjs`: exact-host allowlist and IP/local destination rejection; one-alert-per-lease dispatch.
- `reconciliation_alerts.test.mjs`: host validation, exact-body HMAC, idempotency headers, retry responses and serial lease behavior.
- `STAGING_REPORT.md`: scope, verification and remaining release gates.

Full package archive SHA-256:
`5005f144cfe504fce2d347803d0781b2945eefd27b5e1021b979c3127fcc134b`

Local verification on Node.js 22.16:
- Runtime: 62/62 PASS.
- Static security/architecture contracts: 124/124 PASS.
- Strict TypeScript source compile: PASS.
- Syntax checks: all packaged .mjs files PASS.
- SHA-256 manifest: 62 files verified.
- Deno-native tests: skipped (Deno CLI unavailable).

The ST8 Gateway remains undeployed pending partner onboarding secrets and Testing Tool acceptance. Existing ASIX Production and `super-worker V25` are unchanged.

# v0.7.3 source change notes

This folder documents the v0.7.3 local-tooling delta. The complete reproducible source candidate is distributed as the versioned archive attached with the staging report.

## Updated runtime modules

- `scripts/st8-reconciliation-operations.mjs`
  - locale-independent stable ordering for provider transactions and local/accounting fact arrays;
  - explicit canonical JSON validation for non-finite values, undefined values, cycles and unsupported object types.
- `scripts/dispatch-st8-reconciliation-alerts.mjs`
  - DNS resolution for the exact allowlisted hostname;
  - full-answer public-unicast validation for IPv4 and IPv6;
  - HTTPS socket DNS pinning to the validated address list, while TLS verification remains bound to the hostname;
  - per-delivery DNS revalidation and no redirect following.

## Regression coverage

- `tests/reconciliation_operations.test.mjs`: identical hashes across row-order changes; fail-closed malformed JSON values.
- `tests/reconciliation_alerts.test.mjs`: IPv4/IPv6 address classification, mixed DNS rejection, and blocked private target before socket creation.
- `tests/static_contract_test.py`: static assertions for canonical row normalization and pinned public-DNS webhook transport.

## Deployment boundary

v0.7.3 is not a database migration. Asix #2 remains on the verified v0.7.2 schema; no Edge Function or alert webhook is deployed. The archive is the canonical complete source artifact; verify its SHA-256 against the accompanying checksum file before use.

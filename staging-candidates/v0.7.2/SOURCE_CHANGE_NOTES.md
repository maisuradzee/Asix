# v0.7.2 source change notes

The canonical full v0.7.2 source package is attached separately in the ChatGPT response. This PR adds the database migration and the operator-facing change/verification record.

Implementation delta in the package:
- `buildProviderExportSha256` hashes stable provider facts, excluding volatile `exported_at` and pagination `pages`, sorting transaction rows by transaction ID, and canonicalizing object keys.
- `buildComparisonSnapshotSha256` includes provider facts, local transaction/cancellation/ledger snapshot and accounting integrity snapshot. Volatile `generated_at` values are excluded.
- The reconciliation runner sends both `p_provider_export_sha256` and `p_comparison_snapshot_sha256` to the new service-role-only persistence RPC.
- The new uniqueness key preserves exact duplicate suppression while allowing a fresh run when local state changes under the same ST8 export.
- Runtime and SQL rollback tests cover stable export timestamps, changed local state, duplicate suppression, issue reopening and alert delivery.

Verification: Node 64/64 PASS; static contracts 128/128 PASS; TypeScript strict compile PASS; complete `npm run verify` 22 PASS / 0 FAIL; Deno tests skipped (Deno CLI unavailable). The staging migration is applied to Asix #2 only; no Edge Function is deployed.

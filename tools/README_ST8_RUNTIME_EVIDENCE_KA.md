# ASIX ST8 v0.9.0 runtime evidence import

This workflow does not run the C01-C12 database tests. It accepts a report created by the existing local runner, checks its structure and key safety invariants, stores only a sanitized public summary, and deploys the portal.

## 1. Run the actual local test first

Use the integration/st8-v0.7.1-alert-ops-hardening branch and follow:

- staging-candidates/v0.9.0/concurrency-runner/README_KA.md

The runner must finish with **12/12 PASS**. The submission helper revalidates that raw report locally before preparing the public summary. Its raw JSON report is written to:

staging-candidates/v0.9.0/concurrency-runner/concurrency-results/<runId>.json

A failed, incomplete, non-PostgreSQL-17, remote, Production, or primary Asix #2 staging report is rejected.

## 2. Submit the report from Windows PowerShell 7

Install GitHub CLI and authenticate once with gh auth login. Then use a checkout of the current main branch containing tools/Submit-ST8-Runtime-Evidence.ps1:

~~~powershell
gh auth status
pwsh -File .\tools\Submit-ST8-Runtime-Evidence.ps1 -ReportPath "C:\path\to\concurrency-results\<runId>.json"
~~~

The helper first runs the importer on your computer, producing the sanitized summary in a temporary file. It then gzip-compresses and submits only that summary to the portal workflow on main. The raw report never leaves your computer and is not printed.

## 3. What is published

Only the following sanitized fields are retained in docs/data/runtime-evidence.json inside the published Pages artifact. Later deployments restore this file from the previous public Pages deployment:

- run timestamp and opaque runner run ID;
- PostgreSQL major version and worker count;
- C01-C12 scenario names/statuses and durations;
- SHA-256 of the original raw report.

Raw fixture UUIDs, database name, project reference, wallet balances, ledger rows, transaction IDs, responses and error payloads are not published.

## Validation limits

The importer validates the expected runner schema, local target label, PostgreSQL 17.x version, worker range, all twelve unique scenario IDs, PASS status, and report digest. This is **structural and invariant validation**, not an independent re-execution or cryptographic signature. The digest identifies the imported raw file but does not prove who generated it.

A 12/12 local PostgreSQL pass is not ST8 partner certification, gateway integration acceptance, or Production approval. The public portal labels the result accordingly. Production and the primary Asix #2 staging project are explicitly rejected.

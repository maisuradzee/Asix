# ASIX ST8 v0.9.0 — Runtime evidence and publication rules

The official C01–C12 runtime result is produced only by the canonical GitHub Actions workflow:

- Workflow: `.github/workflows/asix-st8-autonomous-runtime.yml`
- Runtime environment: disposable GitHub-hosted PostgreSQL 17.12
- Candidate: the reviewed v0.8.0 archive with the pinned SHA-256 below
- Scenarios: C01–C12 using 20 independent workers
- Published output: one sanitized artifact, `asix-st8-public-runtime-summary`

## One-time prerequisite

The exact reviewed candidate archive must first be registered at:

`staging-candidates/v0.9.0/runtime-assets/ASIX_ST8_Integration_Candidate_v0.8.0_Asix2_Staging.zip`

Expected SHA-256:

`50f5fda49025048f7e8a0218178cfbba8fc060f1b820be6c7188a99700c17f08`

Use the maintained Georgian instructions in `tools/README_REGISTER_ST8_V080_ARCHIVE_KA.md` and the helper `tools/Register-ST8-V080-Archive.ps1`. The helper checks the exact size and SHA-256, refuses to overwrite a different existing archive, and commits the verified ZIP to the expected main-branch path.

## Automatic runtime pipeline

After the exact archive is registered, GitHub Actions automatically:

1. Verifies the full archive SHA-256 and all nine migration checksums in its manifest.
2. Runs the complete package verification suite, including Deno-native tests.
3. Starts an isolated, disposable PostgreSQL 17.12 service.
4. Applies only the nine reviewed candidate migrations to that disposable database.
5. Runs C01–C12 through the candidate's independent-session runner with 20 workers.
6. Builds a sanitized summary only after all twelve scenarios pass.
7. Uploads the sanitized summary artifact for the Portal workflow.

No Supabase Production or primary Asix #2 Staging project is used. No live ST8 request, wallet transfer, partner callback, or partner-side acceptance is performed by this workflow.

## Portal publication and trust boundary

The Portal accepts a runtime summary only from the artifact attached to the exact completed run of `ASIX ST8 Autonomous Progression`, and only when that run:

- completed successfully;
- belongs to this same GitHub repository; and
- ran from the `main` branch.

The Portal validates the artifact schema and accepts exactly one expected summary file. Caller-supplied JSON, the former `summary_gzip_base64` dispatch input, and the retired `Submit-ST8-Runtime-Evidence.ps1` helper are not accepted or supported.

The importer checks the schema, local disposable target label, PostgreSQL 17.x version, 20–100 worker range, all twelve unique scenario IDs, PASS status, per-scenario durations, and the source report digest. The importer performs structural and invariant validation of the trusted workflow artifact; it is not a cryptographic signature of the database server.

## Reading workflow results correctly

A successful workflow run does not automatically mean C01–C12 passed. If the exact archive is absent, the runtime job stops at the archive-registration gate, marks itself as waiting, and skips all database and concurrency-test steps. That is a successful gate check, not runtime acceptance and not a 12/12 PASS.

A public runtime PASS appears only after the full candidate suite and all twelve disposable-database scenarios have completed successfully and the sanitized artifact has been accepted by the Portal.

## Remaining external release gates

ST8 partner sandbox credentials, Testing Tool acceptance, commercial onboarding, legal/regulatory review, and any later production approval remain separate gates. This runtime pipeline does not certify or authorize a Production release.

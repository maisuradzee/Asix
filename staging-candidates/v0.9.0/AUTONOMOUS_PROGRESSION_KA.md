# ASIX ST8 Autonomous Progression

This workflow automatically advances through the available local validation stages:

1. Waits for the existing ST8 static-validation workflow to pass (or runs on its daily schedule / manual dispatch).
2. Verifies the exact v0.8.0 archive and all nine migration checksums.
3. Runs the candidate Node, Python, TypeScript, and Deno validation suite.
4. Creates a fresh disposable PostgreSQL 17.12 service in GitHub Actions.
5. Bootstraps only the minimal Supabase Auth compatibility objects required by the migrations.
6. Applies the nine reviewed migrations and runs C01-C12 with 20 independent connections.
7. If and only if all twelve scenarios pass, creates a sanitized summary and dispatches the public Pages workflow.
8. Keeps a synthetic raw report artifact for three days only if the run fails.

Production and the primary Asix #2 staging project are never contacted. The PostgreSQL service is created fresh for each run and destroyed by GitHub when the job ends. The workflow does not use ST8 partner credentials or make live financial calls.

## One-time bootstrap required

GitHub Actions cannot read a ChatGPT sandbox file directly. Upload the exact file below once to the repository at this path:

\`staging-candidates/v0.9.0/runtime-assets/ASIX_ST8_Integration_Candidate_v0.8.0_Asix2_Staging.zip\`

Expected SHA-256:
\`50f5fda49025048f7e8a0218178cfbba8fc060f1b820be6c7188a99700c17f08\`

The workflow deliberately waits without running tests if the archive is absent. Uploading it to \`main\` automatically starts the workflow. No repeated manual execution is required afterward.

## Automatic progression boundaries

This pipeline can complete local candidate validation and DB-level concurrency testing. It cannot autonomously complete:
- ST8-issued Operator Code, Site ID, sandbox URL, API keys and registered public-key exchange;
- ST8 Testing Tool / partner acceptance;
- legal, licensing, jurisdiction and operator approvals;
- deployment to a real Supabase project or Production.

Those are external approvals or credentials. The workflow never invents them and never enables live money movement.

## Monitoring

GitHub Actions: \`ASIX ST8 Autonomous Progression\`

Public status: https://maisuradzee.github.io/Asix/

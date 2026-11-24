# Runtime test assets

The ASIX ST8 Autonomous Progression workflow expects the reviewed v0.8.0 migration archive in this folder:

`ASIX_ST8_Integration_Candidate_v0.8.0_Asix2_Staging.zip`

Expected SHA-256:

`50f5fda49025048f7e8a0218178cfbba8fc060f1b820be6c7188a99700c17f08`

The workflow will not run PostgreSQL migrations or C01-C12 until this exact archive is present and the checksum matches. After it is committed to `main`, the automation starts automatically. Do not upload credentials, .env files, API keys, or real user/payment data here.

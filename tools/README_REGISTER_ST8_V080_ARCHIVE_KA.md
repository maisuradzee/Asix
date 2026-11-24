# One-time ASIX ST8 v0.8.0 archive registration

The canonical autonomous runtime workflow is already in main:

- Workflow: .github/workflows/asix-st8-autonomous-runtime.yml
- Trigger: the exact v0.8.0 archive is added under staging-candidates/v0.9.0/runtime-assets/
- Runtime: GitHub-hosted disposable PostgreSQL 17.12
- Tests: complete candidate validation followed by C01-C12 with 20 workers
- Public evidence: sanitized summary only; raw report is not uploaded on a successful run
- Portal: the Pages workflow consumes the sanitized artifact automatically after a successful progression run

## The only one-time local step

Download the supplied file ASIX_ST8_Integration_Candidate_v0.8.0_Asix2_Staging.zip to your computer. Its expected SHA-256 is:

50f5fda49025048f7e8a0218178cfbba8fc060f1b820be6c7188a99700c17f08

Install GitHub CLI, authenticate once, and run the following from a checkout of main:

~~~powershell
gh auth login
pwsh -File .\tools\Register-ST8-V080-Archive.ps1 -ArchivePath "$HOME\Downloads\ASIX_ST8_Integration_Candidate_v0.8.0_Asix2_Staging.zip"
~~~

The script:
- verifies the exact SHA-256 before upload;
- checks whether the exact archive is already present;
- refuses to overwrite a different existing file;
- uploads the ZIP to the path expected by the existing workflow;
- does not print the base64 payload.

Once the commit appears on main, GitHub Actions automatically starts the full pipeline. No Docker, psql, PowerShell runner setup, manual SQL migration, or manual C01-C12 invocation is needed after archive registration.

## Automatic gates and limits

The runtime workflow verifies the archive hash, verifies the nine migration-file checksums from the package manifest, runs the complete validation suite (including Deno), starts ephemeral PostgreSQL 17.12, applies the nine migrations, and runs C01-C12. Only a complete 12/12 PASS proceeds to sanitized evidence upload. A failed run does not produce public PASS evidence.

ST8 partner Testing Tool acceptance is a separate stage requiring genuine sandbox credentials and partner access. Production and the primary Asix #2 staging project are never used by this workflow. PR #3 remains Draft/Open and is not merged automatically.

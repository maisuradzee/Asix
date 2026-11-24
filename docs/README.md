# ASIX Development Portal

Public status portal for ASIX engineering progress and ST8 integration.

## Publish
The GitHub Actions workflow `.github/workflows/asix-development-portal-pages.yml` publishes the contents of `docs/` to GitHub Pages whenever `docs/**` changes on `main`.

Repository settings must have GitHub Pages configured with **Build and deployment → Source: GitHub Actions**. The first deployment starts after this branch is merged into `main` and Pages is enabled.

## Reporting rules
- Publish only results supported by logs, test output, or reviewed repository artifacts.
- Keep unexecuted runtime tests explicitly marked as not run.
- Never publish credentials, tokens, private partner configuration, player data, or wallet identifiers.
- Never imply production deployment or ST8 partner acceptance unless separately verified.
- Update the verification date and statuses when new evidence is available.

## Current snapshot
Last verified: 2026-11-24. C01–C12 runtime concurrency tests have not been executed. Static/package checks listed on the portal are passed; they are not partner acceptance.

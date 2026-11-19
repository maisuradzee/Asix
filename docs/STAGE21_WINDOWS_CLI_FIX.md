# Stage21 Windows CLI fix

Reported issue: `supabase : The term 'supabase' is not recognized...`

Cause: PowerShell cannot find a global `supabase` executable on PATH. This happens before any ASIX database connection is attempted.

Fix: the Stage21 Windows exporter now detects either a native `supabase` command or `npx.cmd`. If only `npx.cmd` is available, all CLI invocations use `npx.cmd --yes supabase@beta ...`. Run `npx.cmd --yes supabase@beta login` once from PowerShell to complete browser authentication.

Requirements: Node.js LTS (for npm/npx) and Docker Desktop running. Docker is required by the current `supabase db dump` workflow.

Static inspection confirms the PowerShell script no longer assumes `supabase` is globally installed. PowerShell execution was not available in the build runtime, so this change is not represented as a Windows end-to-end execution test. The real source export has not yet been run.

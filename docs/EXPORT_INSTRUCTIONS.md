# One-command complete ASIX source export

Use Supabase CLI. On Windows, the exporter can use either a global `supabase` command or `npx.cmd --yes supabase@beta`; see `STAGE21_WINDOWS_CLI_FIX.md` for setup. Database commands explicitly use `--linked` to target the linked project and `--lang typescript` to select the generated type language. The exporter does not apply migrations or modify the source.

## Windows

1. Install Node.js LTS and Docker Desktop, or install the Supabase CLI with Scoop.
2. If the `supabase` command is unavailable, run `npx.cmd --yes supabase@beta login`; otherwise run `supabase login`.
3. Extract this package and double-click `scripts\START_EXPORT_WINDOWS.bat`. The exporter uses the native CLI or its npx fallback automatically.

## macOS / Linux

1. Install Supabase CLI and Docker Engine/Desktop.
2. Run `supabase login`.
3. Extract this package and run:

```bash
bash ./scripts/export_casino_handover.sh
```

The CLI may ask for the source database password locally during linking/dump. Do not put that password in a file or send it to ChatGPT.

## Output

The script creates a timestamped folder and ZIP. The generated folder includes:
- `database/schema.sql`: native current-state app schema dump (no production rows).
- `database/database.types.ts`: exact generated API types.
- `database/migration-history.txt`: applied version/name inventory, not the original SQL body of every migration.
- `edge-functions/`: downloaded deployed Edge Function source.
- `frontend/`: V153 frontend and destination-safe config template.
- `sql-reference/`: selected recovered patches and read-only checks.
- `metadata/`: source project, Supabase CLI and deployed function inventory.
- `SHA256SUMS.txt`: SHA-256 integrity list.

Both export scripts run the matching integrity verifier automatically after creating the ZIP. You can also rerun the verifier manually.

## Optional application data

To export live `public` and `asix_internal` rows separately:
- Windows: `-IncludeLiveData`
- macOS/Linux: `--include-live-data`

The script requires typing `EXPORT ASIX LIVE DATA`. The resulting SQL file is sensitive and deliberately excluded from the ordinary ZIP. Encrypt it and transfer it separately only when explicitly required and authorized.

The default schema dump intentionally excludes Supabase-managed Auth, Storage and extension-owned schemas. Project secrets, Auth users, password material and Storage object bytes must be migrated through separate approved processes.

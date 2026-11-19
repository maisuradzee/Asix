# Legacy export command alias

This script set is retained for compatibility. `export_source_project.sh` and `export_source_project.ps1` now call the current Stage21 casino handover exporter.

For current instructions, read `docs/EXPORT_INSTRUCTIONS.md` and run:

- Windows: `scripts\START_EXPORT_WINDOWS.bat`
- macOS/Linux: `bash ./scripts/export_casino_handover.sh`

The timestamped output contains the live current-state schema dump, exact generated database types, migration metadata, deployed Edge Function source, frontend baseline and checksums. It is not a replay of all historical migration SQL bodies and does not include production application rows by default.

#!/usr/bin/env bash
set -Eeuo pipefail
DIR="${1:-}"
if [[ -z "$DIR" || ! -d "$DIR" ]]; then
  echo "Usage: bash scripts/verify_handover_export.sh <generated-export-directory>" >&2
  exit 2
fi
DIR="$(cd "$DIR" && pwd)"
required=(database/schema.sql database/database.types.ts database/migration-history.txt metadata/source-project.json metadata/functions-list.txt database/roles-and-privileges.txt)
for rel in "${required[@]}"; do
  [[ -s "$DIR/$rel" ]] || { echo "MISSING OR EMPTY: $rel" >&2; exit 1; }
done

python3 - "$DIR" <<'PY'
from pathlib import Path
import re,sys
root=Path(sys.argv[1])
schema=(root/'database/schema.sql').read_text(encoding='utf-8',errors='replace')
types=(root/'database/database.types.ts').read_text(encoding='utf-8',errors='replace')
migrations=(root/'database/migration-history.txt').read_text(encoding='utf-8',errors='replace')
checks={
  'schema.sql exceeds 50 KB':(root/'database/schema.sql').stat().st_size >= 50_000,
  'schema has at least 70 CREATE FUNCTION definitions':len(re.findall(r'(?im)^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\b',schema)) >= 70,
  'schema has application table DDL':'CREATE TABLE' in schema.upper(),
  'schema has qcard_process_action':'qcard_process_action' in schema,
  'schema has ASIX commission settlement':'asix_settle_platform_commission_after_deal' in schema,
  'schema has RLS policies':'CREATE POLICY' in schema.upper(),
  'database.types.ts exceeds 20 KB':(root/'database/database.types.ts').stat().st_size >= 20_000,
  'database.types.ts contains generated Database type':'export type Database' in types,
  'migration list contains at least 128 version rows':len(re.findall(r'(?m)^.*\b\d{14}\b.*$',migrations)) >= 128,
  'function list contains super-worker':'super-worker' in (root/'metadata/functions-list.txt').read_text(encoding='utf-8',errors='replace'),
}
for name,ok in checks.items():
    print(f'{name}: {"PASS" if ok else "FAIL"}')
    if not ok: raise SystemExit(1)
PY

EDGE_COUNT=0
while IFS= read -r -d '' file; do
  EDGE_COUNT=$((EDGE_COUNT+1))
  [[ $(wc -c < "$file") -ge 1000 ]] || { echo "Edge source file is unexpectedly small: $file" >&2; exit 1; }
  grep -q 'Deno.serve' "$file" || { echo "Deno.serve entrypoint missing: $file" >&2; exit 1; }
done < <(find "$DIR/edge-functions" -type f -name '*.ts' -print0)
[[ "$EDGE_COUNT" -ge 1 ]] || { echo "No downloaded Edge Function TypeScript source found." >&2; exit 1; }

[[ -s "$DIR/sql-reference/DESTINATION_BOOTSTRAP_5_PERCENT.sql" ]] || { echo "Destination bootstrap SQL missing." >&2; exit 1; }
if grep -q 'REPLACE_WITH_CASINO_AUTH_USER_UUID' "$DIR/sql-reference/DESTINATION_BOOTSTRAP_5_PERCENT.sql"; then
  echo "Destination bootstrap is still a template, as expected; replace its UUID before running it."
fi

[[ -s "$DIR/SHA256SUMS.txt" ]] || { echo "SHA256SUMS.txt missing." >&2; exit 1; }
(cd "$DIR" && sha256sum -c SHA256SUMS.txt)
ZIP_PATH="${DIR%/}.zip"
if [[ -f "$ZIP_PATH" ]] && command -v unzip >/dev/null 2>&1; then
  unzip -tq "$ZIP_PATH"
fi
printf '\nASIX generated handover export checks passed.\n'
printf 'Schema bytes: %s\n' "$(wc -c < "$DIR/database/schema.sql")"
printf 'Generated type bytes: %s\n' "$(wc -c < "$DIR/database/database.types.ts")"
printf 'Edge function files: %s\n' "$EDGE_COUNT"
printf 'Note: this validates export integrity and key object presence, not a clean destination restore.\n'

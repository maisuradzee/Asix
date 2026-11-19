param([Parameter(Mandatory=$true)][string]$ExportDirectory)
$ErrorActionPreference = "Stop"
$Dir = [System.IO.Path]::GetFullPath($ExportDirectory)
$Required = @(
  "database/schema.sql",
  "database/database.types.ts",
  "database/migration-history.txt",
  "metadata/source-project.json",
  "metadata/functions-list.txt",
  "database/roles-and-privileges.txt",
  "sql-reference/DESTINATION_BOOTSTRAP_5_PERCENT.sql"
)
foreach ($relative in $Required) {
  $path = Join-Path $Dir $relative
  if (-not (Test-Path $path) -or (Get-Item $path).Length -eq 0) { throw "Missing/empty required export file: $relative" }
}
$schema = Get-Content (Join-Path $Dir "database/schema.sql") -Raw
$types = Get-Content (Join-Path $Dir "database/database.types.ts") -Raw
$migrations = Get-Content (Join-Path $Dir "database/migration-history.txt") -Raw
$functionCount = [regex]::Matches($schema,'(?im)^CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\b').Count
$migrationCount = [regex]::Matches($migrations,'(?m)^.*\b\d{14}\b.*$').Count
if ((Get-Item (Join-Path $Dir "database/schema.sql")).Length -lt 50000) { throw "schema.sql is unexpectedly small." }
if ($functionCount -lt 70) { throw "Expected at least 70 function definitions, found $functionCount." }
if ($schema -notmatch 'qcard_process_action' -or $schema -notmatch 'asix_settle_platform_commission_after_deal') { throw "Core game/commission functions are missing." }
if ($schema -notmatch 'CREATE POLICY') { throw "RLS policies not found in schema.sql." }
if ((Get-Item (Join-Path $Dir "database/database.types.ts")).Length -lt 20000 -or $types -notmatch 'export type Database') { throw "Generated types file failed size/content check." }
if ($migrationCount -lt 128) { throw "Expected at least 128 migration rows, found $migrationCount." }
if ((Get-Content (Join-Path $Dir "metadata/functions-list.txt") -Raw) -notmatch 'super-worker') { throw "super-worker missing from function inventory." }
$edge = Get-ChildItem (Join-Path $Dir "edge-functions") -Recurse -Filter *.ts | Where-Object { $_.Length -ge 1000 } | Select-Object -First 1
if (-not $edge -or (Get-Content $edge.FullName -Raw) -notmatch 'Deno.serve') { throw "Downloaded Edge Function source failed validation." }
foreach ($line in Get-Content (Join-Path $Dir "SHA256SUMS.txt")) {
  if ($line -match '^([a-fA-F0-9]{64})  (.+)$') {
    $file = Join-Path $Dir ($Matches[2] -replace '/', [IO.Path]::DirectorySeparatorChar)
    $actual = (Get-FileHash $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Matches[1].ToLowerInvariant()) { throw "SHA-256 mismatch: $file" }
  }
}
Write-Host "ASIX generated handover export checks passed."
Write-Host "Schema bytes: $((Get-Item (Join-Path $Dir 'database/schema.sql')).Length); functions: $functionCount; migrations: $migrationCount"
Write-Host "This validates export integrity and key objects, not a clean destination restore."

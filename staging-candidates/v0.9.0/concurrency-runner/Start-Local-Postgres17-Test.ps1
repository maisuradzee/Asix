[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$MigrationZipPath,
  [int]$Workers = 20,
  [switch]$KeepContainer
)

$ErrorActionPreference = "Stop"
$containerName = "asix-st8-v090-pg"
$databasePassword = "LocalOnly-ST8-v090-Postgres17!"
$port = 55432
$ack = "YES_I_UNDERSTAND_THIS_IS_A_DISPOSABLE_ST8_TEST_DATABASE"
$completed = $false
$tempRoot = $null

function Write-Step([string]$Message) {
  Write-Host ""
  Write-Host ("==> " + $Message) -ForegroundColor Cyan
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker CLI not found. Install/start Docker Desktop, then retry."
}
if (-not (Get-Command node -ErrorAction SilentlyContinue) -or -not (Get-Command npm -ErrorAction SilentlyContinue)) {
  throw "Node.js 22.16+ and npm are required."
}
if (-not (Test-Path -LiteralPath $MigrationZipPath -PathType Leaf)) {
  throw "Migration ZIP not found: $MigrationZipPath"
}
if ($Workers -lt 2 -or $Workers -gt 100) {
  throw "Workers must be between 2 and 100."
}
$existing = docker ps -a --filter "name=^/$containerName$" --format "{{.Names}}"
if ($existing -eq $containerName) {
  throw "Container $containerName already exists. Inspect it, then remove it manually before retrying."
}

Write-Step "Pull PostgreSQL 17 image"
docker pull postgres:17
if ($LASTEXITCODE -ne 0) { throw "docker pull failed." }

Write-Step "Start isolated local-only PostgreSQL container"
docker run --name $containerName --detach --publish "127.0.0.1:$($port):5432" --env "POSTGRES_PASSWORD=$databasePassword" --env "POSTGRES_DB=postgres" postgres:17
if ($LASTEXITCODE -ne 0) { throw "Could not start the disposable PostgreSQL container." }

try {
  Write-Step "Wait for PostgreSQL readiness"
  $ready = $false
  for ($i = 0; $i -lt 60; $i++) {
    docker exec $containerName pg_isready -U postgres -d postgres *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 2
  }
  if (-not $ready) { throw "PostgreSQL did not become ready within 120 seconds." }

  Write-Step "Create Supabase Auth-compatible local test stubs"
  $bootstrapSql = @'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN; END IF;
END $$;
CREATE SCHEMA IF NOT EXISTS auth;
CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  aud text,
  role text,
  email text UNIQUE,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  is_anonymous boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE OR REPLACE FUNCTION auth.jwt()
RETURNS jsonb
LANGUAGE sql
STABLE
AS $function$
  SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$function$;
GRANT USAGE ON SCHEMA auth TO service_role;
GRANT EXECUTE ON FUNCTION auth.jwt() TO service_role;
'@
  $bootstrapSql | docker exec -i $containerName psql -v ON_ERROR_STOP=1 -U postgres -d postgres
  if ($LASTEXITCODE -ne 0) { throw "Auth bootstrap failed." }

  Write-Step "Extract exact ST8 candidate migrations from the v0.8.0 archive"
  $tempRoot = Join-Path $env:TEMP ("asix-st8-v090-" + [guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $tempRoot | Out-Null
  Expand-Archive -LiteralPath $MigrationZipPath -DestinationPath $tempRoot
  $migrationDir = Join-Path $tempRoot "asix-v080/supabase/migrations"
  if (-not (Test-Path -LiteralPath $migrationDir -PathType Container)) {
    throw "Expected migrations directory not found inside the v0.8.0 archive."
  }
  $migrations = @(Get-ChildItem -LiteralPath $migrationDir -Filter "*.sql" -File | Sort-Object Name)
  if ($migrations.Count -ne 9) {
    throw "Expected exactly 9 reviewed ST8 migrations; found $($migrations.Count)."
  }

  Write-Step "Apply the 9 reviewed ST8 migrations to disposable local PostgreSQL only"
  foreach ($migration in $migrations) {
    Write-Host ("Applying " + $migration.Name)
    Get-Content -LiteralPath $migration.FullName -Raw -Encoding UTF8 |
      docker exec -i $containerName psql -v ON_ERROR_STOP=1 -U postgres -d postgres
    if ($LASTEXITCODE -ne 0) {
      throw "Migration failed: $($migration.Name). Container retained for diagnosis."
    }
  }

  Write-Step "Install pinned Node.js dependency"
  Push-Location $PSScriptRoot
  try {
    npm install --ignore-scripts --no-package-lock
    if ($LASTEXITCODE -ne 0) { throw "npm install failed." }

    Write-Step "Run C01-C12 on independent PostgreSQL pool connections"
    $env:ST8_TEST_PROJECT_REF = "local-disposable-postgres17"
    $env:ST8_TEST_DATABASE_URL = "postgresql://postgres:$databasePassword@127.0.0.1:$port/postgres"
    $env:ST8_TEST_ALLOW_DISPOSABLE_DB = $ack
    $env:ST8_TEST_WORKERS = [string]$Workers
    $env:ST8_TEST_SSL = "disable"
    npm run test:concurrency
    if ($LASTEXITCODE -ne 0) { throw "Concurrency runner reported failure. Container retained for diagnosis." }
  }
  finally {
    Pop-Location
  }

  $completed = $true
  Write-Step "Concurrency run completed"
  Write-Host "The database is local-only and disposable. JSON evidence is in concurrency-results."
}
catch {
  Write-Error $_
  throw
}
finally {
  if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
  if (-not $KeepContainer -and $completed) {
    Write-Step "Remove disposable PostgreSQL container"
    docker rm -f $containerName
  } else {
    Write-Host "Container retained for diagnosis: $containerName" -ForegroundColor Yellow
  }
}

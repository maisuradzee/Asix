[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Fixed guard: this exporter is intentionally scoped to the known ASIX source.
$ExpectedProjectRef = "kxcuvagipqiqisowtgys"
$ProjectRef = $ExpectedProjectRef
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$SupabaseDirectory = Join-Path $RepositoryRoot "supabase"
$ConfigPath = Join-Path $SupabaseDirectory "config.toml"
$ExportRoot = Join-Path $SupabaseDirectory "private_exports"

function Stop-Export {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Invoke-SupabaseCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    Write-Host ""
    Write-Host "[ASIX V154 EXPORT] $Description"
    $output = & supabase @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($null -ne $output) {
        $output | ForEach-Object { Write-Host $_ }
    }

    if ($exitCode -ne 0) {
        throw "$Description failed (supabase exit code $exitCode)."
    }
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        Stop-Export "supabase/config.toml was not found. Run this script from an ASIX repository checkout."
    }

    $configText = Get-Content -LiteralPath $ConfigPath -Raw
    $projectMatch = [regex]::Match(
        $configText,
        '(?m)^\s*project_id\s*=\s*"([^"]+)"\s*$'
    )

    if (-not $projectMatch.Success) {
        Stop-Export "Could not read project_id from supabase/config.toml."
    }

    $ConfiguredProjectRef = $projectMatch.Groups[1].Value
    if ($ConfiguredProjectRef -ne $ExpectedProjectRef) {
        Stop-Export "Repository project_id is '$ConfiguredProjectRef', expected '$ExpectedProjectRef'. No export was started."
    }

    if (-not (Get-Command supabase -ErrorAction SilentlyContinue)) {
        Stop-Export "Supabase CLI was not found in PATH. Install the Supabase CLI v3, then rerun this script."
    }

    $versionOutput = & supabase --version 2>&1 | Out-String
    $versionExitCode = $LASTEXITCODE
    if ($versionExitCode -ne 0) {
        Stop-Export "Could not read the Supabase CLI version."
    }

    $versionMatch = [regex]::Match($versionOutput, '(?<!\d)(\d+)\.(\d+)\.(\d+)')
    if (-not $versionMatch.Success) {
        Stop-Export "Could not parse the Supabase CLI version output: $versionOutput"
    }

    $cliMajor = [int]$versionMatch.Groups[1].Value
    $cliVersion = $versionMatch.Value
    if ($cliMajor -lt 3) {
        Stop-Export "Supabase CLI v3 or newer is required so the explicit --remote target is unambiguous. Detected $cliVersion."
    }

    $dumpHelp = & supabase db dump --help 2>&1 | Out-String
    $helpExitCode = $LASTEXITCODE
    if ($helpExitCode -ne 0) {
        Stop-Export "Could not inspect 'supabase db dump --help'."
    }
    if ($dumpHelp -notmatch '--remote') {
        Stop-Export "This Supabase CLI does not advertise --remote for db dump. No export was started."
    }
    if ($dumpHelp -notmatch '--role-only') {
        Stop-Export "This Supabase CLI does not advertise --role-only for db dump. No export was started."
    }

    # CLI v3 uses the local stack by default. Pin the exact hosted target in
    # each read-only dump command; do not rely on whichever project is linked.
    $timestamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss'Z'")
    $exportDirectory = Join-Path $ExportRoot ("v154_" + $timestamp)
    New-Item -ItemType Directory -Path $exportDirectory -Force | Out-Null

    $rolesPath = Join-Path $exportDirectory "roles.sql"
    $schemaPath = Join-Path $exportDirectory "schema.sql"

    $rolesArguments = @("db", "dump", "--remote=$ProjectRef", "--role-only", "-f", $rolesPath)
    Invoke-SupabaseCapture -Arguments $rolesArguments -Description "Export custom database role definitions (no application rows)."

    $schemaArguments = @("db", "dump", "--remote=$ProjectRef", "-f", $schemaPath)
    Invoke-SupabaseCapture -Arguments $schemaArguments -Description "Export current application schema (no table data)."

    foreach ($file in @($rolesPath, $schemaPath)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
            throw "Expected dump output was not created: $file"
        }
        if ((Get-Item -LiteralPath $file).Length -le 0) {
            throw "Dump output is empty: $file"
        }
    }

    $rolesHash = (Get-FileHash -LiteralPath $rolesPath -Algorithm SHA256).Hash
    $schemaHash = (Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash
    $exportedAt = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $rolesBytes = (Get-Item -LiteralPath $rolesPath).Length
    $schemaBytes = (Get-Item -LiteralPath $schemaPath).Length

    $manifest = @(
        "ASIX V154 source schema/roles export",
        "Exported UTC: $exportedAt",
        "Project ref: $ProjectRef",
        "Source PostgreSQL baseline: 17.11.0.019 (verified separately from Supabase project metadata)",
        "Supabase CLI: $cliVersion",
        "",
        "Files:",
        "roles.sql | $rolesBytes bytes | SHA256 $rolesHash",
        "schema.sql | $schemaBytes bytes | SHA256 $schemaHash",
        "",
        "Safety scope:",
        "- This script invokes only supabase db dump read operations.",
        "- No --data-only option is used; application rows, Auth users, wallet balances and transaction records are not exported.",
        "- Supabase-managed schemas (including auth and storage) and extension-owned schemas are excluded by the Supabase CLI dump filter.",
        "- Custom role definitions are exported separately. Review role ownership, grants and target default privileges before restoring.",
        "- Keep this directory private. The dump may contain internal schema/function definitions and role metadata.",
        "- Do not commit, email or upload private_exports to GitHub or public storage.",
        "- This is a current-state schema/roles export, not the missing historical migration chain."
    )

    $manifestPath = Join-Path $exportDirectory "manifest.txt"
    $manifest | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Write-Host ""
    Write-Host "[ASIX V154 EXPORT] Completed successfully."
    Write-Host "Private export directory: $exportDirectory"
    Write-Host "No production table data was exported."
    Write-Host "Review the manifest and restore only into an isolated staging environment."
}
catch {
    Stop-Export $_.Exception.Message
}

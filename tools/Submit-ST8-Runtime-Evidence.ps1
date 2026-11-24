[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$ReportPath
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI (gh) is required. Install it and authenticate with: gh auth login"
}
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw "Node.js 22.16+ is required to validate and sanitize the raw runner report locally."
}
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
  throw "Runner report not found: $ReportPath"
}

$resolvedReport = (Resolve-Path -LiteralPath $ReportPath).Path
$tempSummary = Join-Path $env:TEMP ("asix-st8-public-summary-" + [guid]::NewGuid().ToString("N") + ".json")

try {
  node (Join-Path $PSScriptRoot "import-st8-runtime-evidence.mjs") $resolvedReport $tempSummary
  if ($LASTEXITCODE -ne 0) {
    throw "Local evidence validation failed. Nothing was submitted."
  }

  $bytes = [System.IO.File]::ReadAllBytes($tempSummary)
  if ($bytes.Length -eq 0 -or $bytes.Length -gt 1MB) {
    throw "Sanitized summary must be between 1 byte and 1 MiB."
  }

  $memory = [System.IO.MemoryStream]::new()
  try {
    $gzip = [System.IO.Compression.GZipStream]::new(
      $memory,
      [System.IO.Compression.CompressionMode]::Compress,
      $true
    )
    try { $gzip.Write($bytes, 0, $bytes.Length) }
    finally { $gzip.Dispose() }
    $encoded = [Convert]::ToBase64String($memory.ToArray())
  }
  finally { $memory.Dispose() }

  if ($encoded.Length -gt 30000) {
    throw "Sanitized summary is too large for workflow_dispatch (30,000-character safety limit)."
  }

  gh auth status --hostname github.com
  if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI authentication failed."
  }

  Write-Host "Submitting sanitized ST8 runtime summary. The raw report stays on this computer."
  gh workflow run asix-development-portal-pages.yml --repo maisuradzee/Asix --ref main --field "summary_gzip_base64=$encoded"
  if ($LASTEXITCODE -ne 0) {
    throw "GitHub workflow dispatch failed."
  }

  Write-Host "Workflow dispatched. GitHub will validate the sanitized summary and publish the C01-C12 result."
}
finally {
  if (Test-Path -LiteralPath $tempSummary) {
    Remove-Item -LiteralPath $tempSummary -Force
  }
}

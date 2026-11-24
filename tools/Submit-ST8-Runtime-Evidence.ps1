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
if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) {
  throw "Runner report not found: $ReportPath"
}
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $ReportPath).Path)
if ($bytes.Length -eq 0 -or $bytes.Length -gt 1MB) {
  throw "Runner report must be between 1 byte and 1 MiB."
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
  throw "Compressed evidence is too large for workflow_dispatch (30,000-character safety limit)."
}
gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) { throw "GitHub CLI authentication failed." }
Write-Host "Submitting compressed local PostgreSQL 17.12 runner evidence to ASIX portal workflow..."
gh workflow run asix-development-portal-pages.yml --repo maisuradzee/Asix --ref main --field "report_gzip_base64=$encoded"
if ($LASTEXITCODE -ne 0) { throw "GitHub workflow dispatch failed." }
Write-Host "Workflow dispatched. It will reject incomplete reports and publish only the sanitized C01-C12 summary."

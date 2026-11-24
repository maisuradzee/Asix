[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$ArchivePath
)

$ErrorActionPreference = "Stop"

$Repository = "maisuradzee/Asix"
$TargetPath = "staging-candidates/v0.9.0/runtime-assets/ASIX_ST8_Integration_Candidate_v0.8.0_Asix2_Staging.zip"
$ExpectedSha256 = "50f5fda49025048f7e8a0218178cfbba8fc060f1b820be6c7188a99700c17f08"
$MaximumArchiveBytes = 20MB

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  throw "GitHub CLI is required. Install gh, then run: gh auth login"
}
if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
  throw "Archive file not found: $ArchivePath"
}

$resolvedPath = (Resolve-Path -LiteralPath $ArchivePath).Path
$fileInfo = Get-Item -LiteralPath $resolvedPath
if ($fileInfo.Length -le 0 -or $fileInfo.Length -gt $MaximumArchiveBytes) {
  throw "Archive size is outside the allowed range (1 byte to 20 MiB)."
}

$actualSha256 = (Get-FileHash -LiteralPath $resolvedPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualSha256 -ne $ExpectedSha256) {
  throw "SHA-256 mismatch. Expected $ExpectedSha256; received $actualSha256. Nothing was uploaded."
}

gh auth status --hostname github.com
if ($LASTEXITCODE -ne 0) {
  throw "GitHub CLI is not authenticated. Run gh auth login and retry."
}

$endpoint = "repos/$Repository/contents/$TargetPath"
$lookupOutput = gh api $endpoint"?ref=main" 2>&1
$lookupExitCode = $LASTEXITCODE

if ($lookupExitCode -eq 0) {
  $remoteText = [string]::Join([Environment]::NewLine, $lookupOutput)
  try {
    $remote = $remoteText | ConvertFrom-Json
    $remoteBase64 = ($remote.content -replace '\s', '')
    if ([string]::IsNullOrWhiteSpace($remoteBase64)) {
      throw "Existing repository file has no readable base64 content."
    }
    $remoteBytes = [Convert]::FromBase64String($remoteBase64)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
      $remoteSha256 = [BitConverter]::ToString($hasher.ComputeHash($remoteBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
      $hasher.Dispose()
    }
    if ($remoteSha256 -eq $ExpectedSha256) {
      Write-Host "The exact verified v0.8.0 archive is already registered on main. No change needed."
      exit 0
    }
    throw "A different file already exists at the target path. Refusing to overwrite it."
  }
  catch {
    throw "Could not safely verify the existing repository archive: $($_.Exception.Message)"
  }
}

$lookupError = [string]::Join([Environment]::NewLine, $lookupOutput)
if ($lookupError -notmatch '(404|Not Found)') {
  throw "Could not check the target repository path. GitHub returned: $lookupError"
}

$archiveBytes = [System.IO.File]::ReadAllBytes($resolvedPath)
$encodedContent = [Convert]::ToBase64String($archiveBytes)
$payload = @{
  message = "chore: register verified ASIX ST8 v0.8.0 migration archive"
  content = $encodedContent
  branch = "main"
} | ConvertTo-Json -Compress -Depth 4

Write-Host "Uploading the verified archive to $Repository/$TargetPath ..."
$responseText = $payload | gh api --method PUT $endpoint --input -
$uploadExitCode = $LASTEXITCODE
if ($uploadExitCode -ne 0) {
  throw "GitHub archive registration failed. Exit code: $uploadExitCode"
}

try {
  $receipt = ([string]::Join([Environment]::NewLine, $responseText)) | ConvertFrom-Json
}
catch {
  throw "GitHub accepted the request but did not return a readable commit receipt."
}

if (-not $receipt.commit.sha) {
  throw "GitHub response did not contain the registration commit SHA."
}

Write-Host "Archive registration committed: $($receipt.commit.sha)"
Write-Host "SHA-256 verified: $ExpectedSha256"
Write-Host "The ASIX ST8 Autonomous Progression workflow will now start automatically from the main-branch push."

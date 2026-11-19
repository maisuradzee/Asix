param([string]$OutputDirectory = "", [switch]$IncludeLiveData)
$script = Join-Path $PSScriptRoot "export_casino_handover.ps1"
if ($IncludeLiveData) {
  & $script -OutputDirectory $OutputDirectory -IncludeLiveData
} elseif ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  & $script
} else {
  & $script -OutputDirectory $OutputDirectory
}
if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

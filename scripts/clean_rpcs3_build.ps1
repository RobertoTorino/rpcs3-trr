[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$Root,
    [string]$BuildDir = "build-windows-release"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

$Root = [System.IO.Path]::GetFullPath($Root)
$BuildDir = [System.IO.Path]::GetFullPath((Join-Path $Root $BuildDir))

if (-not (Test-Path $BuildDir)) {
    Write-Host "Nothing to clean. Build directory not found: $BuildDir"
    exit 0
}

if ($PSCmdlet.ShouldProcess($BuildDir, "Remove build directory")) {
    Remove-Item -Path $BuildDir -Recurse -Force
    Write-Host "Removed build directory: $BuildDir"
}
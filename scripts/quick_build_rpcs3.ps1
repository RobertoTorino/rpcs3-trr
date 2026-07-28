[CmdletBinding()]
param(
    [string]$Root = $(if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { (Get-Location).Path }),
    [string]$BuildDir,
    [string]$BuildConfig = "Release",
    [string]$Toolset = "v143,host=x64",
    [string]$QtRoot = "C:\Qt\6.11.1\msvc2022_64",
    [string]$Qt5Root = "",
    [string]$VulkanRoot = "C:\VulkanSDK",
    [string]$LLVMDir = $env:LLVM_DIR,
    [int]$MaxRetries = 3,
    [switch]$Clean,
    [switch]$DeployQt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-CMakeGenerator {
    if ((& cmake --help 2>&1) -match "Visual Studio 17 2022") {
        return "Visual Studio 17 2022"
    }

    if ((& cmake --help 2>&1) -match "Visual Studio 18 2026") {
        return "Visual Studio 18 2026"
    }

    throw "Could not find a supported Visual Studio generator (2022 or 2026)."
}

function Resolve-VsDevCmd {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $installDir = & $vswhere -latest -version "[17.0,18.0)" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installDir) {
            $candidate = Join-Path $installDir "Common7\Tools\VsDevCmd.bat"
            if (Test-Path $candidate) { return $candidate }
        }

        $installDir = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installDir) {
            $candidate = Join-Path $installDir "Common7\Tools\VsDevCmd.bat"
            if (Test-Path $candidate) { return $candidate }
        }
    }

    $fallbacks = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\VsDevCmd.bat",
        "C:\Program Files\Microsoft Visual Studio\2026\BuildTools\Common7\Tools\VsDevCmd.bat"
    )

    foreach ($candidate in $fallbacks) {
        if (Test-Path $candidate) { return $candidate }
    }

    throw "Could not find VsDevCmd.bat. Install Visual Studio 2022 with C++ tools."
}

function Import-VsEnvironment {
    param([Parameter(Mandatory = $true)][string]$VsDevCmd)

    $dump = & cmd.exe /d /c "call `"$VsDevCmd`" -arch=x64 -host_arch=x64 >nul && set"
    foreach ($line in $dump) {
        if ($line -match "^[^=]+=.*$") {
            $name, $value = $line -split "=", 2
            if ($name) {
                Set-Item -Path ("Env:" + $name) -Value $value
            }
        }
    }
}

function Resolve-VulkanSdk {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $dirs = Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    if (-not $dirs) {
        throw "Could not find a Vulkan SDK under '$RootPath'."
    }

    foreach ($d in $dirs) {
        $header = Join-Path $d.FullName "Include\vulkan\vulkan.h"
        if (Test-Path $header) {
            return $d.FullName
        }
    }

    throw "No Vulkan SDK with headers found under '$RootPath'."
}

function Resolve-LlvmSetup {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$Preferred
    )

    if ($Preferred) {
        if (Test-Path (Join-Path $Preferred "LLVMConfig.cmake")) {
            return [pscustomobject]@{ Mode = "prebuilt"; LLVMDir = $Preferred; BuildLlvmSubmodule = "OFF"; SourceRoot = "" }
        }

        $nested = Join-Path $Preferred "lib\cmake\llvm"
        if (Test-Path (Join-Path $nested "LLVMConfig.cmake")) {
            return [pscustomobject]@{ Mode = "prebuilt"; LLVMDir = $nested; BuildLlvmSubmodule = "OFF"; SourceRoot = "" }
        }

        throw "LLVM_DIR was set but LLVMConfig.cmake was not found under '$Preferred'."
    }

    $prebuiltCandidates = @(
        (Join-Path $RepoRoot "llvm11-build\Release\lib\cmake\llvm"),
        (Join-Path $RepoRoot "llvm11-build\lib\cmake\llvm"),
        (Join-Path $RepoRoot "llvm11_build\Release\lib\cmake\llvm"),
        (Join-Path $RepoRoot "llvm11_build\lib\cmake\llvm"),
        (Join-Path $RepoRoot "llvm_build\Release\lib\cmake\llvm"),
        (Join-Path $RepoRoot "llvm_build\lib\cmake\llvm")
    )

    foreach ($candidate in $prebuiltCandidates) {
        if (Test-Path (Join-Path $candidate "LLVMConfig.cmake")) {
            return [pscustomobject]@{ Mode = "prebuilt"; LLVMDir = $candidate; BuildLlvmSubmodule = "OFF"; SourceRoot = "" }
        }
    }

    $sourceCandidates = @(
        (Join-Path $RepoRoot "llvm11-project\llvm"),
        (Join-Path $RepoRoot "llvm-project-11\llvm"),
        (Join-Path $RepoRoot "llvm")
    )

    foreach ($candidate in $sourceCandidates) {
        if (Test-Path (Join-Path $candidate "CMakeLists.txt")) {
            return [pscustomobject]@{ Mode = "source"; LLVMDir = ""; BuildLlvmSubmodule = "ON"; SourceRoot = $candidate }
        }
    }

    throw "No valid LLVM 11 setup was found. Provide -LLVMDir pointing to LLVMConfig.cmake, or place LLVM 11 sources under '$RepoRoot\llvm11-project\llvm' or build output in '$RepoRoot\llvm11-build'."
}

function Resolve-Qt5Root {
    param(
        [string]$Preferred,
        [string]$QtRootCandidate
    )

    $candidates = @()

    if (-not [string]::IsNullOrWhiteSpace($Preferred)) {
        $candidates += $Preferred
    }

    if (-not [string]::IsNullOrWhiteSpace($env:QTDIR)) {
        $candidates += $env:QTDIR
    }

    $candidates += @(
        "C:\Qt\5.15.2\msvc2022_64",
        "C:\Qt\5.15.2\msvc2019_64"
    )

    if (Test-Path "C:\Qt") {
        $qtVersionDirs = Get-ChildItem -Path "C:\Qt" -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "5.*" } |
            Sort-Object Name -Descending

        foreach ($versionDir in $qtVersionDirs) {
            $kitDirs = Get-ChildItem -Path $versionDir.FullName -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like "msvc*_64" } |
                Sort-Object Name -Descending

            foreach ($kit in $kitDirs) {
                $candidates += $kit.FullName
            }
        }
    }

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if (Test-Path (Join-Path $candidate "lib\cmake\Qt5\Qt5Config.cmake")) {
            return $candidate
        }
    }

    return ""
}

$Root = [System.IO.Path]::GetFullPath($Root)
if (-not $BuildDir) {
    $BuildDir = Join-Path $Root "build-windows-release"
}
$BuildDir = [System.IO.Path]::GetFullPath($BuildDir)

if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host "Cleaning build directory: $BuildDir" -ForegroundColor Yellow
    Remove-Item -Path $BuildDir -Recurse -Force
}

if (-not (Test-Path (Join-Path $QtRoot "lib\cmake\Qt6\Qt6Config.cmake"))) {
    throw "Qt6Config.cmake not found under '$QtRoot'. Please ensure Qt is installed correctly."
}

$generator = Resolve-CMakeGenerator
$vsDevCmd = Resolve-VsDevCmd
Import-VsEnvironment -VsDevCmd $vsDevCmd
$vulkanSdk = Resolve-VulkanSdk -RootPath $VulkanRoot
$llvmSetup = Resolve-LlvmSetup -RepoRoot $Root -Preferred $LLVMDir
$helper = Join-Path $Root "scripts\build_windows_release.ps1"

if (-not (Test-Path $helper)) {
    throw "Missing helper script: $helper"
}

$env:QTDIR = $QtRoot
$env:Qt6_DIR = Join-Path $QtRoot "lib\cmake\Qt6"
$env:CMAKE_PREFIX_PATH = $QtRoot
$env:VULKAN_SDK = $vulkanSdk
$env:PATH = (Join-Path $QtRoot "bin") + ";" + (Join-Path $vulkanSdk "Bin") + ";" + $env:PATH

$qt5ConfigPath = Join-Path $Root "3rdparty\qt5.cmake"
$qt5DetectedRoot = ""
if (Test-Path $qt5ConfigPath) {
    $qt5DetectedRoot = Resolve-Qt5Root -Preferred $Qt5Root -QtRootCandidate $QtRoot

    if ([string]::IsNullOrWhiteSpace($qt5DetectedRoot)) {
        throw "This repository requires Qt5 (detected via '$qt5ConfigPath'), but no Qt5Config.cmake was found. Provide -Qt5Root (for example C:\Qt\5.15.2\msvc2019_64)."
    }

    $env:Qt5_DIR = Join-Path $qt5DetectedRoot "lib\cmake\Qt5"
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host " RPCS3 Build Configuration" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Generator   : $generator"
Write-Host "Build dir   : $BuildDir"
Write-Host "Toolset     : $Toolset"
Write-Host "Qt root     : $QtRoot"
if (-not [string]::IsNullOrWhiteSpace($qt5DetectedRoot)) {
    Write-Host "Qt5 root    : $qt5DetectedRoot"
}
Write-Host "Vulkan SDK  : $vulkanSdk"
Write-Host "LLVM mode   : $($llvmSetup.Mode)"

if ($llvmSetup.Mode -eq "prebuilt") {
    Write-Host "LLVM dir    : $($llvmSetup.LLVMDir)" -ForegroundColor Green
} else {
    Write-Host "LLVM source : $($llvmSetup.SourceRoot)" -ForegroundColor Yellow
}
Write-Host "=========================================`n" -ForegroundColor Cyan

$helperArgs = @{
    Root = $Root
    BuildDir = $BuildDir
    Generator = $generator
    Toolset = $Toolset
    BuildConfig = $BuildConfig
    QtRoot = $QtRoot
    Qt6Dir = (Join-Path $QtRoot "lib\cmake\Qt6")
    VulkanSdk = $vulkanSdk
    BuildLlvmSubmodule = $llvmSetup.BuildLlvmSubmodule
    MaxRetries = $MaxRetries
}

if (-not [string]::IsNullOrWhiteSpace($llvmSetup.LLVMDir)) {
    $helperArgs.LLVMDir = $llvmSetup.LLVMDir
}

if (-not [string]::IsNullOrWhiteSpace($qt5DetectedRoot)) {
    $helperArgs.Qt5Root = $qt5DetectedRoot
    $helperArgs.Qt5Dir = (Join-Path $qt5DetectedRoot "lib\cmake\Qt5")
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $helper @helperArgs

if ($LASTEXITCODE -ne 0) {
    throw "Build failed with exit code $LASTEXITCODE"
}

$exe = Join-Path $BuildDir "bin\rpcs3.exe"
if (-not (Test-Path $exe)) {
    throw "Build completed but artifact was not found: $exe"
}

if ($DeployQt) {
    $windeployqt = Join-Path $QtRoot "bin\windeployqt.exe"
    if (-not (Test-Path $windeployqt)) {
        throw "windeployqt.exe was not found under '$QtRoot\bin'."
    }

    Write-Host "Running windeployqt on $exe" -ForegroundColor Cyan
    & $windeployqt --release --compiler-runtime $exe
    if ($LASTEXITCODE -ne 0) {
        throw "windeployqt failed with exit code $LASTEXITCODE"
    }
}

$item = Get-Item $exe
Write-Host "`n=========================================" -ForegroundColor Green
Write-Host " Build complete: $($item.FullName)" -ForegroundColor Green
Write-Host " Size: $([math]::Round($item.Length / 1MB, 2)) MB" -ForegroundColor Green
Write-Host " Timestamp: $($item.LastWriteTime)" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
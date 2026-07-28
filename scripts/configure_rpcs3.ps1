[CmdletBinding()]
param(
    [string]$Root,
    [string]$BuildDir = "build-windows-release",
    [string]$BuildConfig = "Release",
    [string]$QtRoot = "C:\Qt\6.11.1\msvc2022_64",
    [string]$VulkanRoot = "C:\VulkanSDK",
    [string]$LLVMDir = $env:LLVM_DIR,
    [int]$MaxRetries = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $Root) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Resolve-VsSetup {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    $installDir = ""
    $generator = ""

    if (Test-Path $vswhere) {
        $installDir = & $vswhere -latest -version "[17.0,18.0)" -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installDir) {
            $generator = "Visual Studio 17 2022"
        }
    }

    if (-not $installDir -and (Test-Path $vswhere)) {
        $installDir = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($installDir) {
            if ($installDir -match "\\2022\\") {
                $generator = "Visual Studio 17 2022"
            }
            elseif ($installDir -match "\\2026\\") {
                $generator = "Visual Studio 18 2026"
            }
        }
    }

    if (-not $installDir) {
        $fallback = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools"
        if (Test-Path (Join-Path $fallback "Common7\Tools\VsDevCmd.bat")) {
            $installDir = $fallback
            $generator = "Visual Studio 17 2022"
        }
    }

    if (-not $installDir) {
        throw "Could not find a Visual Studio installation with C++ tools."
    }

    [pscustomobject]@{
        InstallDir = $installDir
        Generator = $generator
        VsDevCmd = (Join-Path $installDir "Common7\Tools\VsDevCmd.bat")
    }
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
    foreach ($dir in $dirs) {
        if (Test-Path (Join-Path $dir.FullName "Include\vulkan\vulkan.h")) {
            return $dir.FullName
        }
    }

    throw "Could not find a Vulkan SDK under '$RootPath'."
}

function Resolve-LlvmSetup {
    param(
        [Parameter(Mandatory = $true)][string]$RepoRoot,
        [string]$Preferred
    )

    if ($Preferred) {
        if (Test-Path (Join-Path $Preferred "LLVMConfig.cmake")) {
            return [pscustomobject]@{ LLVMDir = $Preferred; BuildLlvmSubmodule = "OFF" }
        }

        $nested = Join-Path $Preferred "lib\cmake\llvm"
        if (Test-Path (Join-Path $nested "LLVMConfig.cmake")) {
            return [pscustomobject]@{ LLVMDir = $nested; BuildLlvmSubmodule = "OFF" }
        }

        throw "LLVM_DIR was set, but no LLVMConfig.cmake was found under '$Preferred'."
    }

    $prebuiltCandidates = @(
        (Join-Path $RepoRoot "llvm11-build\Release\lib\cmake\llvm"),
        (Join-Path $RepoRoot "llvm11-build\lib\cmake\llvm"),
        (Join-Path $RepoRoot "llvm_build\Release\lib\cmake\llvm"),
        (Join-Path $RepoRoot "llvm_build\lib\cmake\llvm")
    )

    foreach ($candidate in $prebuiltCandidates) {
        if (Test-Path (Join-Path $candidate "LLVMConfig.cmake")) {
            return [pscustomobject]@{ LLVMDir = $candidate; BuildLlvmSubmodule = "OFF" }
        }
    }

    $sourceCandidates = @(
        (Join-Path $RepoRoot "llvm\CMakeLists.txt"),
        (Join-Path $RepoRoot "llvm-project-11\llvm\CMakeLists.txt")
    )

    foreach ($candidate in $sourceCandidates) {
        if (Test-Path $candidate) {
            return [pscustomobject]@{ LLVMDir = ""; BuildLlvmSubmodule = "ON" }
        }
    }

    throw "No valid LLVM 11 setup was found. Provide -LLVMDir pointing to LLVMConfig.cmake, or keep LLVM 11 sources under '$RepoRoot\llvm'."
}

$Root = [System.IO.Path]::GetFullPath($Root)
$BuildDir = [System.IO.Path]::GetFullPath((Join-Path $Root $BuildDir))

if (-not (Test-Path (Join-Path $QtRoot "lib\cmake\Qt6\Qt6Config.cmake"))) {
    throw "Qt6 was not found at '$QtRoot'."
}

$vsSetup = Resolve-VsSetup
Import-VsEnvironment -VsDevCmd $vsSetup.VsDevCmd
$vulkanSdk = Resolve-VulkanSdk -RootPath $VulkanRoot
$llvmSetup = Resolve-LlvmSetup -RepoRoot $Root -Preferred $LLVMDir
$helper = Join-Path $Root "scripts\build_windows_release.ps1"

if (-not (Test-Path $helper)) {
    throw "Missing helper script: $helper"
}

$env:QTDIR = $QtRoot
$env:Qt6_DIR = Join-Path $QtRoot "lib\cmake\Qt6"
$env:CMAKE_PREFIX_PATH = $QtRoot
$env:PATH = (Join-Path $QtRoot "bin") + ";" + (Join-Path $vulkanSdk "Bin") + ";" + $env:PATH

$helperArgs = @{
    Root = $Root
    BuildDir = $BuildDir
    Generator = $vsSetup.Generator
    BuildConfig = $BuildConfig
    QtRoot = $QtRoot
    Qt6Dir = (Join-Path $QtRoot "lib\cmake\Qt6")
    VulkanSdk = $vulkanSdk
    LLVMDir = $llvmSetup.LLVMDir
    BuildLlvmSubmodule = $llvmSetup.BuildLlvmSubmodule
    MaxRetries = $MaxRetries
    ConfigureOnly = $true
}

& $helper @helperArgs

exit $LASTEXITCODE
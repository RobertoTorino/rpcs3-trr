[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter(Mandatory = $true)]
    [string]$BuildDir,

    [Parameter(Mandatory = $true)]
    [string]$Generator,

    [string]$Toolset = "v143,host=x64",

    [Parameter(Mandatory = $true)]
    [string]$BuildConfig,

    [Parameter(Mandatory = $true)]
    [string]$QtRoot,

    [Parameter(Mandatory = $true)]
    [string]$Qt6Dir,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$Qt5Root,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$Qt5Dir,

    [Parameter(Mandatory = $true)]
    [string]$VulkanSdk,

    [Parameter(Mandatory = $false)]
    [AllowEmptyString()]
    [string]$LLVMDir,

    [Parameter(Mandatory = $true)]
    [ValidateSet("ON", "OFF")]
    [string]$BuildLlvmSubmodule,

    [int]$MaxRetries = 3,

    [switch]$ConfigureOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsInterruptedBuild {
    param(
        [int]$ExitCode,
        [string]$LogPath
    )

    if ($ExitCode -eq 130 -or $ExitCode -eq 3221225786 -or $ExitCode -eq -1073741510) {
        return $true
    }

    if (Test-Path $LogPath) {
        $logText = Get-Content -Path $LogPath -Raw
        if ($logText -match "\^C|Ctrl\+C|interrupted") {
            return $true
        }
    }

    return $false
}

function Invoke-CMakePhase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PhaseName,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$LogDir,

        [Parameter(Mandatory = $true)]
        [int]$Retries
    )

    $cmakeCmd = (Get-Command cmake.exe -ErrorAction Stop).Source

    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        $phaseLogPath = Join-Path $LogDir ("{0}.attempt{1}.log" -f $PhaseName, $attempt)
        $phaseErrPath = Join-Path $LogDir ("{0}.attempt{1}.stderr.log" -f $PhaseName, $attempt)
        $argumentString = ($Arguments | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + ($_ -replace '"', '\\"') + '"'
            }
            else {
                $_
            }
        }) -join ' '

        Write-Host ("[{0}] attempt {1}/{2}" -f $PhaseName, $attempt, $Retries)
        Write-Host ("[{0}] running cmake, writing logs to: {1}" -f $PhaseName, $phaseLogPath)

        $proc = Start-Process -FilePath $cmakeCmd `
            -ArgumentList $argumentString `
            -WorkingDirectory $Root `
            -RedirectStandardOutput $phaseLogPath `
            -RedirectStandardError $phaseErrPath `
            -PassThru `
            -Wait

        $exitCode = $proc.ExitCode
            Merge-PhaseStderrIntoLog -LogPath $phaseLogPath -ErrPath $phaseErrPath

        if ($exitCode -eq 0) {
            Write-Host ("[{0}] succeeded" -f $PhaseName)
            return
        }

        if ((Test-IsInterruptedBuild -ExitCode $exitCode -LogPath $phaseLogPath) -and $attempt -lt $Retries) {
            Write-Warning ("[{0}] was interrupted (exit code {1}). Retrying in a fresh process..." -f $PhaseName, $exitCode)
            continue
        }

        Write-Error ("[{0}] failed with exit code {1}" -f $PhaseName, $exitCode)
        Write-Host "---- Last log lines ----"
        if (Test-Path $phaseLogPath) {
            Get-Content -Path $phaseLogPath -Tail 120
        }
        exit $exitCode
    }
}

    function Merge-PhaseStderrIntoLog {
        param(
            [Parameter(Mandatory = $true)]
            [string]$LogPath,

            [Parameter(Mandatory = $true)]
            [string]$ErrPath
        )

        if (-not (Test-Path $ErrPath)) {
            return
        }

        $stderrText = Get-Content -Path $ErrPath -Raw
        if ([string]::IsNullOrEmpty($stderrText)) {
            return
        }

        for ($retry = 1; $retry -le 5; $retry++) {
            try {
                Add-Content -Path $LogPath -Value $stderrText
                return
            }
            catch [System.IO.IOException] {
                if ($retry -eq 5) {
                    Write-Warning ("Could not merge '{0}' into '{1}' because the log file is still locked. Keeping stderr separate." -f $ErrPath, $LogPath)
                    return
                }

                Start-Sleep -Milliseconds 200
            }
        }
    }

$BuildDir = [System.IO.Path]::GetFullPath($BuildDir)
$LogDir = Join-Path $BuildDir "build-logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$clPath = (Get-Command cl.exe -ErrorAction Stop).Source

# CMake 4 + Qt package files fail if this resolves to a major-only value like "3".
# Pin it to a valid major.minor and pass the same value in configure args.
$env:CMAKE_POLICY_VERSION_MINIMUM = "3.16"

$cmakePrefixPath = $QtRoot
if (-not [string]::IsNullOrWhiteSpace($Qt5Root)) {
    $cmakePrefixPath = $Qt5Root
}

$configureArgs = @(
    "--fresh",
    "-S", $Root,
    "-B", $BuildDir,
    "-G", $Generator,
    "-A", "x64",
    "-T", $Toolset,
    "-DCMAKE_C_COMPILER=$clPath",
    "-DCMAKE_CXX_COMPILER=$clPath",
    "-DCMAKE_CXX_STANDARD=20",
    "-DCMAKE_CXX_STANDARD_REQUIRED=ON",
    "-DABSL_PROPAGATE_CXX_STD=OFF",
    "-DCMAKE_PREFIX_PATH=$cmakePrefixPath",
    "-DCMAKE_POLICY_VERSION_MINIMUM:STRING=3.16",
    "-DQt6_DIR=$Qt6Dir",
    "-DQTDIR=$QtRoot",
    "-DVULKAN_SDK=$VulkanSdk",
    "-DUSE_SYSTEM_ZLIB=OFF",
    "-DUSE_SYSTEM_SDL=OFF",
    "-DUSE_SYSTEM_CURL=OFF",
    "-DUSE_SYSTEM_OPENCV=OFF",
    "-DALSOFT_ENABLE_MODULES=OFF",
    "-DWITH_LLVM=ON",
    "-DBUILD_LLVM_SUBMODULE=$BuildLlvmSubmodule",
    "-DLLVM_ENABLE_DIA_SDK=OFF"
)

if (-not [string]::IsNullOrWhiteSpace($Qt5Dir)) {
    $configureArgs += "-DQt5_DIR=$Qt5Dir"
}

if (-not [string]::IsNullOrWhiteSpace($LLVMDir)) {
    $configureArgs += "-DLLVM_DIR=$LLVMDir"
}

$buildArgs = @(
    "--build", $BuildDir,
    "--config", $BuildConfig,
    "--target", "rpcs3",
    "--parallel"
)

Invoke-CMakePhase -PhaseName "configure" -Arguments $configureArgs -LogDir $LogDir -Retries $MaxRetries

if ($ConfigureOnly) {
    Write-Host "Configure completed successfully. Logs: $LogDir"
    exit 0
}

Invoke-CMakePhase -PhaseName "build" -Arguments $buildArgs -LogDir $LogDir -Retries $MaxRetries

Write-Host "Build completed successfully. Logs: $LogDir"

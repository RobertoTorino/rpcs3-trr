param(
    [string]$BuildDir = "build-windows-release",
    [string]$BuildConfig = "Release",
    [int]$MaxRetries = 3,
    [int]$RetryDelaySec = 5,
    [int]$Parallel = 0,
    [switch]$VerboseLogs
)

$ErrorActionPreference = "Stop"

function Invoke-BuildAttempt {
    param(
        [int]$Attempt,
        [string]$BuildDir,
        [string]$BuildConfig,
        [int]$Parallel,
        [string]$LogDir
    )

    $logPath = Join-Path $LogDir ("binary-build.attempt{0}.log" -f $Attempt)
    $errPath = Join-Path $LogDir ("binary-build.attempt{0}.stderr.log" -f $Attempt)

    $args = @("--build", $BuildDir, "--config", $BuildConfig, "--target", "rpcs3", "--parallel")
    if ($Parallel -gt 0) {
        $args += "$Parallel"
    }

    Write-Host ("[binary-build] attempt {0}/{1}" -f $Attempt, $MaxRetries)
    Write-Host ("[binary-build] running cmake, writing logs to: {0}" -f $logPath)

    if (Test-Path $logPath) { Remove-Item $logPath -Force }
    if (Test-Path $errPath) { Remove-Item $errPath -Force }

    $process = Start-Process -FilePath "cmake" -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $logPath -RedirectStandardError $errPath
    $process.WaitForExit()

    return @($process.ExitCode, $logPath, $errPath)
}

function Test-BuildLogsForErrors {
    param(
        [string]$LogPath,
        [string]$ErrPath
    )

    $patterns = @(
        '(?im)\bfatal error\s+[A-Z]+\d+\b',
        '(?im)\berror\s+[A-Z]+\d+\b',
        '(?im):\s+error\s+[A-Z]+\d+\b',
        '(?im)\bMSB\d+\s*:\s*error\b',
        '(?im)^\s*FAILED:\s*',
        '(?im)^\s*Build FAILED\.'
    )

    foreach ($path in @($LogPath, $ErrPath)) {
        if (-not (Test-Path $path)) {
            continue
        }

        $content = Get-Content -Path $path -Raw -ErrorAction SilentlyContinue
        if ([string]::IsNullOrWhiteSpace($content)) {
            continue
        }

        foreach ($pattern in $patterns) {
            if ($content -match $pattern) {
                return $true
            }
        }
    }

    return $false
}

$BuildDir = [System.IO.Path]::GetFullPath($BuildDir)
if (-not (Test-Path $BuildDir)) {
    throw "Build directory not found: $BuildDir`nRun configure first (e.g. build_windows_release.bat)"
}

$cachePath = Join-Path $BuildDir "CMakeCache.txt"
if (-not (Test-Path $cachePath)) {
    throw "Build directory is not configured: $BuildDir`nMissing: $cachePath`nRun configure first (e.g. build_windows_release.bat)"
}

$LogDir = Join-Path $BuildDir "build-logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$BinaryPath = Join-Path $BuildDir "bin\rpcs3.exe"

for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
    $result = Invoke-BuildAttempt -Attempt $attempt -BuildDir $BuildDir -BuildConfig $BuildConfig -Parallel $Parallel -LogDir $LogDir
    $exitCode = [int]$result[0]
    $logPath = [string]$result[1]
    $errPath = [string]$result[2]

    $logHasErrors = Test-BuildLogsForErrors -LogPath $logPath -ErrPath $errPath
    $binaryExists = Test-Path $BinaryPath

    if ($exitCode -eq 0 -and -not $logHasErrors -and $binaryExists) {
        Write-Host "Binary build completed successfully."
        Write-Host "Binary: $BinaryPath"
        Write-Host "Logs: $LogDir"
        exit 0
    }

    $tail = @()
    if (Test-Path $logPath) {
        $tail += Get-Content -Path $logPath -Tail 120
    }
    if (Test-Path $errPath) {
        $tail += Get-Content -Path $errPath -Tail 120
    }

    if ($VerboseLogs -and $tail.Count -gt 0) {
        Write-Host "---- Last log lines ----"
        $tail | ForEach-Object { Write-Host $_ }
    }

    $isLikelyTransientLinkerIssue = $false
    if ($tail.Count -gt 0) {
        $tailText = ($tail -join "`n")
        if ($tailText -match "LNK1104" -and $tailText -match "LLVMAnalysis\.dir") {
            $isLikelyTransientLinkerIssue = $true
        }
    }

    if ($attempt -lt $MaxRetries) {
        if ($isLikelyTransientLinkerIssue) {
            Write-Host "[binary-build] transient LLVM linker file-open issue detected; retrying..."
        }
        else {
            if ($exitCode -eq 0 -and $logHasErrors) {
                Write-Host "[binary-build] compiler/linker errors were detected in the log despite exit code 0; retrying..."
            }
            elseif ($exitCode -eq 0 -and -not $binaryExists) {
                Write-Host ("[binary-build] build returned exit code 0 but binary was not produced at '{0}'; retrying..." -f $BinaryPath)
            }
            else {
                Write-Host ("[binary-build] build failed with exit code {0}; retrying..." -f $exitCode)
            }
        }
        Start-Sleep -Seconds $RetryDelaySec
        continue
    }

    if ($exitCode -eq 0 -and $logHasErrors) {
        Write-Error "[binary-build] build log contains compiler/linker errors even though cmake returned exit code 0"
    }
    elseif ($exitCode -eq 0 -and -not $binaryExists) {
        Write-Error ("[binary-build] build returned success but expected binary was not found: {0}" -f $BinaryPath)
    }
    else {
        Write-Error ("[binary-build] failed with exit code {0}" -f $exitCode)
    }
    if ($tail.Count -gt 0 -and -not $VerboseLogs) {
        Write-Host "---- Last log lines ----"
        $tail | ForEach-Object { Write-Host $_ }
    }
    if ($exitCode -eq 0) {
        exit 1
    }
    exit $exitCode
}

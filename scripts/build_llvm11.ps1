param(
    [string]$Root = $(if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { (Get-Location).Path }),
    [string]$SourceDir,
    [string]$BuildDir,
    [string]$Generator = "Visual Studio 17 2022"
)

$Root = [System.IO.Path]::GetFullPath($Root)
if (-not $SourceDir) {
    $SourceDir = Join-Path $Root "llvm"
}
if (-not $BuildDir) {
    $BuildDir = Join-Path $Root "llvm11-build"
}

$RequiredRpcs3LlvmLibs = @(
    "LLVMMCJIT.lib",
    "LLVMX86CodeGen.lib",
    "LLVMX86AsmParser.lib"
)

function Get-MissingRequiredLlvmLibs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BuildDir,

        [Parameter(Mandatory = $true)]
        [string[]]$RequiredLibs
    )

    $releaseLibDir = Join-Path $BuildDir "Release\lib"
    return @($RequiredLibs | Where-Object {
        -not (Test-Path (Join-Path $releaseLibDir $_))
    })
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host " Configuring LLVM with CMake..."           -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Configure step (Arguments quoted to prevent PowerShell parsing errors)
cmake -S $SourceDir -B $BuildDir -G $Generator -A x64 -T host=x64 `
    "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" `
    "-DLLVM_TARGETS_TO_BUILD=X86" `
    "-DLLVM_BUILD_RUNTIME=OFF" `
    "-DLLVM_BUILD_TOOLS=OFF" `
    "-DLLVM_INCLUDE_BENCHMARKS=OFF" `
    "-DLLVM_INCLUDE_DOCS=OFF" `
    "-DLLVM_INCLUDE_EXAMPLES=OFF" `
    "-DLLVM_INCLUDE_TESTS=OFF" `
    "-DLLVM_INCLUDE_TOOLS=OFF" `
    "-DLLVM_INCLUDE_UTILS=OFF"

# Check if configuration was successful
if ($LASTEXITCODE -ne 0) {
    Write-Error "CMake configuration failed. Check the errors above."
    exit $LASTEXITCODE
}

Write-Host "`n=========================================" -ForegroundColor Cyan
Write-Host " Building LLVM Release Target..."            -ForegroundColor Cyan
Write-Host "===========================================" -ForegroundColor Cyan

# Default ALL_BUILD target
cmake --build $BuildDir --config Release

# Check if build was successful
if ($LASTEXITCODE -ne 0) {
    Write-Error "LLVM build failed. Check the compiler errors above."
    exit $LASTEXITCODE
}

$missing = Get-MissingRequiredLlvmLibs -BuildDir $BuildDir -RequiredLibs $RequiredRpcs3LlvmLibs
if ($missing.Count -gt 0) {
    Write-Warning "LLVM build completed but required libraries are missing. Attempting targeted recovery build..."
    Write-Host ("Missing: {0}" -f ($missing -join ", ")) -ForegroundColor Yellow

    foreach ($libName in $missing) {
        $target = [System.IO.Path]::GetFileNameWithoutExtension($libName)
        Write-Host ("Building missing LLVM target: {0}" -f $target) -ForegroundColor Cyan
        cmake --build $BuildDir --config Release --target $target
        if ($LASTEXITCODE -ne 0) {
            Write-Error ("Targeted build failed for LLVM target '{0}'." -f $target)
            exit $LASTEXITCODE
        }
    }

    $missingAfterRecovery = Get-MissingRequiredLlvmLibs -BuildDir $BuildDir -RequiredLibs $RequiredRpcs3LlvmLibs
    if ($missingAfterRecovery.Count -gt 0) {
        Write-Error ("Required LLVM libraries are still missing after recovery: {0}" -f ($missingAfterRecovery -join ", "))
        exit 1
    }
}

Write-Host "`n=========================================" -ForegroundColor Green
Write-Host " LLVM build completed successfully!"         -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green
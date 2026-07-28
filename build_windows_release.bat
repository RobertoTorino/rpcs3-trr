@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "PS1=%ROOT%scripts\quick_build_rpcs3.ps1"

if not exist "%PS1%" (
    echo ERROR: Missing build helper script: "%PS1%"
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
if errorlevel 1 (
    pause
    exit /b 1
)

echo Build completed.
pause

@echo off
setlocal EnableExtensions

set "ROOT=%~dp0"
set "PS1=%ROOT%configure_rpcs3.ps1"

if not exist "%PS1%" (
    echo ERROR: Missing configure helper script: "%PS1%"
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
if errorlevel 1 (
    pause
    exit /b 1
)

echo Configure completed.
pause
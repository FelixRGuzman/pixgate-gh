@echo off
cd /d "%~dp0"
echo [LAUNCHER] BRIDGE ACTIVE.
echo [LAUNCHER] RAW ARGUMENT: %1

:: Adding quotes around %~1 prevents the '&' from breaking the string
"Pixgate.console.exe" -- "%~1"

if %ERRORLEVEL% NEQ 0 pause
@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting admin privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList @('/c','%~f0') -Verb RunAs"
    exit /b
)

echo Compiling mine-key...
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\compile.ps1"

pause
exit /b

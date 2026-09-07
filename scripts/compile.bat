@echo off
setlocal enabledelayedexpansion

cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting admin privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList @('/c','%~f0') -Verb RunAs"
    exit /b
)

echo Compiling keyon...
powershell -NoProfile -ExecutionPolicy Bypass -File "compile.ps1"
set COMPILE_EXIT_CODE=%errorlevel%

echo.
if %COMPILE_EXIT_CODE% equ 0 (
    echo Compile workflow completed successfully.
) else (
    echo Compile workflow failed with exit code %COMPILE_EXIT_CODE%.
)
pause
exit /b %COMPILE_EXIT_CODE%

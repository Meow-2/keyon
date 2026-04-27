@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting admin privileges...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList @('/c','%~f0') -Verb RunAs"
    exit /b
)

set TASK_FOLDER=\keyon
set TASK_NAME=keyon

echo.
echo ===== Uninstalling keyon Task =====

schtasks /delete /tn "%TASK_FOLDER%\%TASK_NAME%" /f

if %errorlevel%==0 (
    echo keyon removed successfully from folder %TASK_FOLDER%!
) else (
    echo Task not found or failed to remove!
)

pause

# Compile keyon.ahk, stop old process before compiling, then restart.

$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $principal = [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

function Resolve-FirstExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Paths
    )

    foreach ($path in $Paths) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }

    return $null
}

if (-not (Test-IsAdmin)) {
    Write-Host "Admin privileges required, requesting elevation..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

$projectDir = Split-Path -Parent $PSScriptRoot
$sourceFile = Join-Path $projectDir "keyon.ahk"
$outputFile = Join-Path $projectDir "keyon.exe"
$watchdogFile = Join-Path $PSScriptRoot "watchdog.ps1"
$dataDirectory = Join-Path $env:LOCALAPPDATA "keyon"
$maintenancePath = Join-Path $dataDirectory "maintenance-requested"
$stopRequestPath = Join-Path $dataDirectory "stop-requested"
$taskName = "\keyon\keyon"
$processNames = @("keyon", "MuxKey", "mine-key", "mineKey")

$scoopRoot = Join-Path $env:USERPROFILE "scoop"
$ahkCompiler = Join-Path $scoopRoot "apps\autohotkey\current\Compiler\Ahk2Exe.exe"
$ahkBase = Join-Path $scoopRoot "apps\autohotkey\current\v2\AutoHotkey64.exe"

if (-not (Test-Path $ahkCompiler)) {
    Write-Host "Error: Ahk2Exe.exe not found at $ahkCompiler." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ahkBase)) {
    Write-Host "Error: AutoHotkey64.exe base file not found at $ahkBase." -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $sourceFile)) {
    Write-Host "Error: source file not found: $sourceFile" -ForegroundColor Red
    exit 1
}

Write-Host "Compiler: $ahkCompiler" -ForegroundColor Green
Write-Host "Base file: $ahkBase" -ForegroundColor Green
Write-Host "Source file: $sourceFile" -ForegroundColor Green
Write-Host "Output file: $outputFile" -ForegroundColor Green

Write-Host "Preparing maintenance mode..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path $dataDirectory -Force | Out-Null
Remove-Item $stopRequestPath -Force -ErrorAction SilentlyContinue
Set-Content -Path $maintenancePath -Value "compile" -Encoding utf8

Write-Host "Checking scheduled task..." -ForegroundColor Cyan
$taskXmlText = & schtasks.exe /query /tn $taskName /xml ONE 2>$null
$scheduledTaskExists = $LASTEXITCODE -eq 0
$scheduledTaskUsesWatchdog = $false
if ($scheduledTaskExists) {
    try {
        [xml] $taskXml = $taskXmlText -join [Environment]::NewLine
        $taskAction = $taskXml.Task.Actions.Exec
        $scheduledTaskUsesWatchdog = $taskAction.Command -match '(?i)powershell(?:\.exe)?$' -and $taskAction.Arguments -match '(?i)watchdog\.ps1'
    }
    catch {
        Write-Host "Warning: failed to inspect scheduled task action; it will be treated as an old task." -ForegroundColor Yellow
    }
}

if ($scheduledTaskExists) {
    Write-Host "Stopping scheduled watchdog..." -ForegroundColor Cyan
    & schtasks.exe /end /tn $taskName *> $null
}

$watchdogProcesses = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'watchdog\.ps1' }
foreach ($watchdogProcess in $watchdogProcesses) {
    Stop-Process -Id $watchdogProcess.ProcessId -Force -ErrorAction SilentlyContinue
}

foreach ($processName in $processNames) {
    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "Stopping old process: $processName" -ForegroundColor Cyan
        $processes | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }
}

Write-Host "Compiling keyon.ahk..." -ForegroundColor Cyan
try {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $ahkCompiler
    $processInfo.Arguments = "/in `"$sourceFile`" /out `"$outputFile`" /base `"$ahkBase`""
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    if ($process.ExitCode -ne 0) {
        Write-Host "Compilation failed. Exit code: $($process.ExitCode)" -ForegroundColor Red
        if ($stdout) { Write-Host $stdout -ForegroundColor Yellow }
        if ($stderr) { Write-Host $stderr -ForegroundColor Red }
        exit 1
    }

    Write-Host "Compilation successful: $outputFile" -ForegroundColor Green
}
catch {
    Write-Host "Compilation error: $_" -ForegroundColor Red
    exit 1
}

Write-Host "Starting keyon.exe..." -ForegroundColor Cyan
try {
    Remove-Item $maintenancePath -Force -ErrorAction SilentlyContinue
    if ($scheduledTaskExists -and $scheduledTaskUsesWatchdog) {
        & schtasks.exe /run /tn $taskName *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to start scheduled task $taskName."
        }
    }
    else {
        if ($scheduledTaskExists) {
            Write-Host "Warning: the scheduled task still starts keyon.exe directly." -ForegroundColor Yellow
            Write-Host "Run scripts\enableAutoStartup.bat once to migrate it to watchdog.ps1." -ForegroundColor Yellow
        }
        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile",
            "-NonInteractive",
            "-WindowStyle", "Hidden",
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$watchdogFile`""
        ) -WorkingDirectory $projectDir
    }
    Start-Sleep -Milliseconds 500
    Write-Host "keyon watchdog started." -ForegroundColor Green
}
catch {
    Remove-Item $maintenancePath -Force -ErrorAction SilentlyContinue
    Write-Host "Warning: failed to start watchdog. Please run manually: $watchdogFile" -ForegroundColor Yellow
}

Write-Host "Done." -ForegroundColor Green

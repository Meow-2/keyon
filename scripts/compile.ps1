# Compile mineKey.ahk, stop old process before compiling, then restart.

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
$sourceFile = Join-Path $projectDir "mineKey.ahk"
$outputFile = Join-Path $projectDir "mine-key.exe"
$processNames = @("mine-key", "mineKey")

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

foreach ($processName in $processNames) {
    $processes = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "Stopping old process: $processName" -ForegroundColor Cyan
        $processes | Stop-Process -Force
        Start-Sleep -Milliseconds 500
    }
}

Write-Host "Compiling mineKey.ahk..." -ForegroundColor Cyan
try {
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $ahkCompiler
    $processInfo.Arguments = "/in `"$sourceFile`" /out `"$outputFile`" /base `"$ahkBase`""
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true

    $process = [System.Diagnostics.Process]::Start($processInfo)
    $process.WaitForExit()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()

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

Write-Host "Starting mine-key.exe..." -ForegroundColor Cyan
try {
    Start-Process -FilePath $outputFile -WorkingDirectory $projectDir
    Start-Sleep -Milliseconds 500
    Write-Host "mine-key started." -ForegroundColor Green
}
catch {
    Write-Host "Warning: failed to start. Please run manually: $outputFile" -ForegroundColor Yellow
}

Write-Host "Done." -ForegroundColor Green

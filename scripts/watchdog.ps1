param(
    [switch] $DiagnosticCheck
)

$ErrorActionPreference = "Stop"

$projectDir = Split-Path -Parent $PSScriptRoot
$executablePath = Join-Path $projectDir "keyon.exe"
$dataDirectory = Join-Path $env:LOCALAPPDATA "keyon"
$logDirectory = Join-Path $dataDirectory "logs"
$logPath = Join-Path $logDirectory "watchdog.log"
$stopRequestPath = Join-Path $dataDirectory "stop-requested"
$maintenancePath = Join-Path $dataDirectory "maintenance-requested"
$maxLogSize = 1MB
$maxHistoryCount = 5
$restartWindow = [TimeSpan]::FromMinutes(10)
$maxRestarts = 5
$restartDelays = @(2, 10, 30, 60)
$restartTimes = [System.Collections.Generic.List[datetime]]::new()

function Rotate-Log {
    if (-not (Test-Path $logPath) -or (Get-Item $logPath).Length -lt $maxLogSize) {
        return
    }

    $oldestPath = "$logPath.$maxHistoryCount"
    if (Test-Path $oldestPath) {
        Remove-Item $oldestPath -Force
    }

    for ($index = $maxHistoryCount - 1; $index -ge 1; $index--) {
        $sourcePath = "$logPath.$index"
        if (Test-Path $sourcePath) {
            Move-Item $sourcePath "$logPath.$($index + 1)" -Force
        }
    }

    Move-Item $logPath "$logPath.1" -Force
}

function Write-WatchdogLog {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Level,
        [Parameter(Mandatory = $true)]
        [string] $EventName,
        [string] $Details = ""
    )

    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    Rotate-Log
    $line = "{0}`tlevel={1}`tevent={2}`tpid={3}" -f (Get-Date -Format "yyyy-MM-dd'T'HH:mm:ss"), $Level, $EventName, $PID
    if ($Details) {
        $line += "`t$Details"
    }
    Add-Content -Path $logPath -Value $line -Encoding utf8
}

function Test-AndRemoveMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,
        [int] $MaxAgeSeconds = 120
    )

    if (-not (Test-Path $Path)) {
        return $false
    }

    $markerAge = (Get-Date) - (Get-Item $Path).LastWriteTime
    Remove-Item $Path -Force -ErrorAction SilentlyContinue
    return $markerAge.TotalSeconds -le $MaxAgeSeconds
}

Write-WatchdogLog -Level "INFO" -EventName "watchdog_start" -Details "diagnosticCheck=$DiagnosticCheck"

if ($DiagnosticCheck) {
    Write-WatchdogLog -Level "INFO" -EventName "diagnostic_check"
    exit 0
}

if (-not (Test-Path $executablePath)) {
    Write-WatchdogLog -Level "ERROR" -EventName "executable_missing"
    exit 2
}

while ($true) {
    if (Test-AndRemoveMarker -Path $maintenancePath) {
        Write-WatchdogLog -Level "INFO" -EventName "maintenance_stop"
        exit 0
    }

    if (Test-AndRemoveMarker -Path $stopRequestPath) {
        Write-WatchdogLog -Level "INFO" -EventName "user_stop_before_start"
        exit 0
    }

    $startedAt = Get-Date
    try {
        $process = Start-Process -FilePath $executablePath -WorkingDirectory $projectDir -PassThru
        Write-WatchdogLog -Level "INFO" -EventName "child_start" -Details "childPid=$($process.Id)"
        $process.WaitForExit()
        $exitCode = $process.ExitCode
    }
    catch {
        Write-WatchdogLog -Level "ERROR" -EventName "child_start_failed" -Details "message=$($_.Exception.Message.Replace("`r", " ").Replace("`n", " "))"
        $exitCode = -1
    }

    $runtimeSeconds = [Math]::Floor(((Get-Date) - $startedAt).TotalSeconds)
    Write-WatchdogLog -Level "WARN" -EventName "child_exit" -Details "code=$exitCode runtimeSeconds=$runtimeSeconds"

    if (Test-AndRemoveMarker -Path $stopRequestPath) {
        Write-WatchdogLog -Level "INFO" -EventName "user_stop"
        exit 0
    }

    if (Test-AndRemoveMarker -Path $maintenancePath) {
        Write-WatchdogLog -Level "INFO" -EventName "maintenance_stop"
        exit 0
    }

    $cutoff = (Get-Date) - $restartWindow
    while ($restartTimes.Count -gt 0 -and $restartTimes[0] -lt $cutoff) {
        $restartTimes.RemoveAt(0)
    }

    if ($restartTimes.Count -ge $maxRestarts) {
        Write-WatchdogLog -Level "ERROR" -EventName "restart_limit_reached" -Details "windowMinutes=$($restartWindow.TotalMinutes) maxRestarts=$maxRestarts"
        exit 3
    }

    $restartTimes.Add((Get-Date))
    $delayIndex = [Math]::Min($restartTimes.Count - 1, $restartDelays.Count - 1)
    $delaySeconds = $restartDelays[$delayIndex]
    Write-WatchdogLog -Level "INFO" -EventName "restart_scheduled" -Details "delaySeconds=$delaySeconds attempt=$($restartTimes.Count)"
    Start-Sleep -Seconds $delaySeconds
}
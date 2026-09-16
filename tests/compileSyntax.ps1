# 编译入口由 Windows PowerShell 5.1 执行；检查编码和语法，不触发编译或进程重启。
$ErrorActionPreference = "Stop"
$projectDir = Split-Path -Parent $PSScriptRoot
$compilePath = Join-Path $projectDir "scripts\compile.ps1"
$scriptBytes = [IO.File]::ReadAllBytes($compilePath)

# 中文注释要求 UTF-8 BOM，防止 Windows PowerShell 按系统 ANSI 编码误读。
if ($scriptBytes.Length -lt 3 -or $scriptBytes[0] -ne 0xEF -or $scriptBytes[1] -ne 0xBB -or $scriptBytes[2] -ne 0xBF) {
    throw "compile.ps1 must use UTF-8 with BOM for Windows PowerShell 5.1."
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($compilePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    throw ($parseErrors | Out-String)
}

Write-Output "PASS: compile.ps1 encoding and syntax (PowerShell $($PSVersionTable.PSVersion))."

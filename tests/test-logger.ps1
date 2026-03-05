# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

# Standalone test -- dot-source Logger.ps1 and exercise all levels.
# Run from a plain PS session: powershell.exe -NoProfile -File tests\test-logger.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path $PSScriptRoot -Parent
$loggerPath = Join-Path $repoRoot 'src/Logger.ps1'
if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
    $env:TEMP = [System.IO.Path]::GetTempPath()
}
if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
    $env:APPDATA = Join-Path $env:TEMP 'Loadout-AppData'
    if (-not (Test-Path $env:APPDATA)) {
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    }
}

# -- Syntax check -----------------------------------------------------------
$parseErrors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile(
    $loggerPath,
    [ref]$null,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    Write-Host 'SYNTAX ERRORS:' -ForegroundColor Red
    $parseErrors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'Syntax OK' -ForegroundColor Green

# -- Dot-source the module --------------------------------------------------
. $loggerPath

# -- Test 1: basic run (no DryRun) ------------------------------------------
Write-Host ''
Write-Host '=== Test 1: Standard run ===' -ForegroundColor Cyan
Initialize-Logger

Write-Log -Message 'INFO message'
Write-Log -Message 'Operation succeeded' -Level OK
Write-Log -Message 'Non-fatal warning'   -Level WARN
Write-Log -Message 'Install failed'      -Level ERROR
Write-Log -Message 'DEBUG suppressed'    -Level DEBUG   # should NOT appear on console

Write-Host ''
Write-Host "Log file: $Script:LogFilePath" -ForegroundColor DarkGray

# -- Test 2: DryRun mode ----------------------------------------------------
Write-Host ''
Write-Host '=== Test 2: DryRun mode ===' -ForegroundColor Cyan

# Re-initialize with DryRun to get a fresh log file
$Script:LogFilePath = $null
$Script:LogPanel    = $null
$Script:DryRun      = $false

Initialize-Logger -DryRun

Write-Log -Message 'INFO in dry run'
Write-Log -Message 'DEBUG visible in dry run' -Level DEBUG   # SHOULD appear

Write-Host ''
Write-Host "Log file: $Script:LogFilePath" -ForegroundColor DarkGray

# -- Test 3: NoNewline ------------------------------------------------------
Write-Host ''
Write-Host '=== Test 3: NoNewline ===' -ForegroundColor Cyan
Write-Log -Message 'Partial line... ' -NoNewline
Write-Log -Message 'continued here'

# -- Verify log files were written ------------------------------------------
Write-Host ''
Write-Host '=== Log file contents (last 10 lines) ===' -ForegroundColor Cyan
Get-Content $Script:LogFilePath | Select-Object -Last 10 | ForEach-Object {
    Write-Host "  $_" -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'All tests passed.' -ForegroundColor Green

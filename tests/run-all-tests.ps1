# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

# run-all-tests.ps1 -- Master test runner for Loadout.
# Runs every test script in the tests/ directory in the order listed below
# and prints a combined pass/fail summary at the end.
#
# Run from repo root:
#   powershell -ExecutionPolicy Bypass -File tests/run-all-tests.ps1
#
# Exit code 0 = all suites passed. Non-zero = at least one suite failed.
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

$ErrorActionPreference = 'Stop'

function Get-PowerShellCommand {
    if (Get-Command powershell -ErrorAction SilentlyContinue) {
        return 'powershell'
    }
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        return 'pwsh'
    }

    throw "Neither 'powershell' nor 'pwsh' is available on PATH."
}

# Ensure Windows-style env vars exist when running under pwsh on Linux/WSL.
if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
    $env:TEMP = [System.IO.Path]::GetTempPath()
}
if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
    $env:APPDATA = Join-Path $env:TEMP 'Loadout-AppData'
    if (-not (Test-Path $env:APPDATA)) {
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    }
}

$testsDir = $PSScriptRoot
$psCommand = Get-PowerShellCommand

$suites = @(
    'parse-check.ps1',
    'verify-logger.ps1',
    'verify-session6.ps1',
    'verify-session15.ps1',
    'verify-session16.ps1',
    'test-logger.ps1',
    'test-install-engine.ps1',
    'test-update-checker.ps1',
    'test-usb-builder.ps1',
    'test-custom-app.ps1',
    'test-config-export-import.ps1'
)

$totalSuites  = $suites.Count
$passedSuites = 0
$failedSuites = @()

$width = 60

Write-Host ''
Write-Host ('=' * $width)
Write-Host '  Loadout -- Test Runner'
Write-Host ('=' * $width)

foreach ($suite in $suites) {
    $path = Join-Path $testsDir $suite

    if (-not (Test-Path $path)) {
        Write-Host ''
        Write-Host "  SKIP  $suite  (file not found)"
        continue
    }

    Write-Host ''
    Write-Host "  >> $suite"
    Write-Host ('-' * $width)

    $exitCode = 0
    try {
        & $psCommand -ExecutionPolicy Bypass -File $path
        $exitCode = $LASTEXITCODE
    } catch {
        Write-Host "  ERROR: suite threw: $_"
        $exitCode = 1
    }

    if ($exitCode -eq 0) {
        $passedSuites++
        Write-Host "  Suite PASSED: $suite" -ForegroundColor Green
    } else {
        $failedSuites += $suite
        Write-Host "  Suite FAILED: $suite (exit $exitCode)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host ('=' * $width)

if ($failedSuites.Count -eq 0) {
    Write-Host "  ALL $totalSuites SUITES PASSED" -ForegroundColor Green
    Write-Host ('=' * $width)
    exit 0
} else {
    Write-Host "  $passedSuites of $totalSuites suites passed. FAILURES:" -ForegroundColor Red
    foreach ($s in $failedSuites) {
        Write-Host "    - $s" -ForegroundColor Red
    }
    Write-Host ('=' * $width)
    exit 1
}

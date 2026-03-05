# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

# test-update-checker.ps1 -- Loadout UpdateChecker test script
# Dot-sources Logger, ManifestManager, and UpdateChecker, then runs
# Invoke-AppScan against a small subset of apps (one per scan method)
# in DryRun mode. Validates that every result has the correct structure
# without making real network or registry calls.
#
# Run from any directory -- paths resolve relative to this file's location.
# ASCII-only file.

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
    $env:TEMP = [System.IO.Path]::GetTempPath()
}
if ([string]::IsNullOrWhiteSpace($env:APPDATA)) {
    $env:APPDATA = Join-Path $env:TEMP 'Loadout-AppData'
    if (-not (Test-Path $env:APPDATA)) {
        New-Item -ItemType Directory -Path $env:APPDATA -Force | Out-Null
    }
}

$here   = $PSScriptRoot
$srcDir = Join-Path (Split-Path $here -Parent) 'src'

. (Join-Path $srcDir 'Logger.ps1')
. (Join-Path $srcDir 'ManifestManager.ps1')
. (Join-Path $srcDir 'UpdateChecker.ps1')

Initialize-Logger -DryRun
Initialize-ManifestManager

# Build a subset: one app of each scan method we care about
$allApps = Get-ManifestApps

$wingetApp   = @($allApps | Where-Object { $_.wingetId -and -not $_.isPrerequisite })[0]
$psGallApp   = @($allApps | Where-Object { $_.psGalleryModule })[0]
$directApp   = @($allApps | Where-Object { $_.directDownload })[0]
$wslApp      = @($allApps | Where-Object { $_.wslDistroName })[0]

$subset = @($wingetApp, $psGallApp, $directApp, $wslApp) | Where-Object { $null -ne $_ }

Write-Host ''
Write-Host '=== Session 5: Invoke-AppScan subset test ===' -ForegroundColor Cyan
Write-Host "Apps selected for scan ($($subset.Count)):"
foreach ($a in $subset) {
    $method = Get-ScanMethod -App $a
    Write-Host ("  [{0,-15}] {1} ({2})" -f $method, $a.displayName, $a.id)
}
Write-Host ''

# -----------------------------------------------------------------------
# Run the scan
# -----------------------------------------------------------------------
$results = Invoke-AppScan -Apps $subset

# -----------------------------------------------------------------------
# Print results table
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '=== Scan Results ===' -ForegroundColor Cyan
Write-Host ('{0,-28} {1,-18} {2,-15} {3}' -f 'ID', 'Status', 'InstalledVersion', 'AvailableVersion')
Write-Host ('{0,-28} {1,-18} {2,-15} {3}' -f '--', '------', '----------------', '----------------')

foreach ($id in $results.Keys) {
    $r          = $results[$id]
    $instVer    = if ($null -ne $r.InstalledVersion) { $r.InstalledVersion } else { '(none)' }
    $availVer   = if ($null -ne $r.AvailableVersion) { $r.AvailableVersion } else { '(none)' }

    $color = switch ($r.Status) {
        'Current'         { 'Green' }
        'UpdateAvailable' { 'Cyan' }
        'NotInstalled'    { 'Gray' }
        'Failed'          { 'Red' }
        default           { 'White' }
    }

    Write-Host ('{0,-28} {1,-18} {2,-15} {3}' -f $id, $r.Status, $instVer, $availVer) `
        -ForegroundColor $color
}

# -----------------------------------------------------------------------
# Validate structure
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '=== Structure Validation ===' -ForegroundColor Cyan

$validStatuses = @('NotInstalled', 'Current', 'UpdateAvailable', 'Failed')
$allValid = $true

foreach ($id in $results.Keys) {
    $r = $results[$id]

    if ($r.Status -notin $validStatuses) {
        Write-Host "FAIL [$id]: invalid Status '$($r.Status)'" -ForegroundColor Red
        $allValid = $false
    }

    if (-not ($r.PSObject.Properties.Name -contains 'InstalledVersion')) {
        Write-Host "FAIL [$id]: missing InstalledVersion property" -ForegroundColor Red
        $allValid = $false
    }

    if (-not ($r.PSObject.Properties.Name -contains 'AvailableVersion')) {
        Write-Host "FAIL [$id]: missing AvailableVersion property" -ForegroundColor Red
        $allValid = $false
    }
}

# Verify DryRun scan returned results for every app in the subset
foreach ($a in $subset) {
    if (-not $results.ContainsKey($a.id)) {
        Write-Host "FAIL: no result returned for app '$($a.id)'" -ForegroundColor Red
        $allValid = $false
    }
}

if ($allValid) {
    Write-Host 'All results have valid structure.' -ForegroundColor Green
}
else {
    Write-Host 'One or more results failed structure validation.' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Session 5 test complete.' -ForegroundColor Cyan

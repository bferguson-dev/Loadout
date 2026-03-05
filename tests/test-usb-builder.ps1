# test-usb-builder.ps1 -- Dry-run tests for USBBuilder.ps1
# All external calls (winget download, Save-Module, Invoke-WebRequest, file I/O)
# are skipped in DryRun mode; only logging and logic are exercised.
#
# Run from repo root or tests/ directory. All tests must pass.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter','')]
param()

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
$testRoot = $PSScriptRoot
$srcRoot  = Join-Path (Split-Path $testRoot -Parent) 'src'

# -----------------------------------------------------------------------
# Dot-source modules (DryRun mode suppresses external calls)
# -----------------------------------------------------------------------
. "$srcRoot\Logger.ps1"
. "$srcRoot\ManifestManager.ps1"
. "$srcRoot\InstallEngine.ps1"
. "$srcRoot\UpdateChecker.ps1"
. "$srcRoot\USBBuilder.ps1"

Initialize-Logger -DryRun

$manifestPath = Join-Path (Split-Path $testRoot -Parent) 'manifest.json'
Initialize-ManifestManager -ManifestPath $manifestPath

Write-Host ""
Write-Host "=== USB Builder Tests (DryRun) ===" -ForegroundColor Cyan

$pass = 0
$fail = 0
$fakeRoot = Join-Path $env:TEMP 'loadout-usb-fake'
$fakeInstallers = Join-Path $fakeRoot 'installers'
$fakeWinget = Join-Path $fakeInstallers 'winget'
$fakeModules = Join-Path $fakeInstallers 'modules'

function Assert-Equal {
    param([string]$Label, $Actual, $Expected)
    if ($Actual -eq $Expected) {
        Write-Host "  PASS: $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  FAIL: $Label -- expected '$Expected', got '$Actual'" -ForegroundColor Red
        $script:fail++
    }
}

function Assert-True {
    param([string]$Label, [bool]$Value)
    if ($Value) {
        Write-Host "  PASS: $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  FAIL: $Label -- expected True, got False" -ForegroundColor Red
        $script:fail++
    }
}

function Assert-NotNull {
    param([string]$Label, $Value)
    if ($null -ne $Value) {
        Write-Host "  PASS: $Label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  FAIL: $Label -- expected non-null, got null" -ForegroundColor Red
        $script:fail++
    }
}

# -----------------------------------------------------------------------
# Test 1: Get-ManifestDirectory returns expected path
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: ManifestManager.Get-ManifestDirectory ---" -ForegroundColor Yellow

$manifestDir = Get-ManifestDirectory
Assert-NotNull 'Get-ManifestDirectory returns non-null'      $manifestDir
Assert-True    'Manifest directory exists'                   (Test-Path $manifestDir)

$expectedDir = Split-Path $manifestPath -Parent
Assert-Equal   'Get-ManifestDirectory matches manifest path' $manifestDir $expectedDir

# -----------------------------------------------------------------------
# Test 2: Get-USBMethod returns correct method per app type
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: Get-USBMethod routing ---" -ForegroundColor Yellow

$allApps = Get-ManifestApps

# Find representative apps for each method
$wingetApp    = $allApps | Where-Object { $_.wingetId -and -not $_.wslDistroName -and -not $_.windowsFeatureMethod -and -not $_.registryPath -and -not $_.vscodeExtensionId } | Select-Object -First 1
$psGalleryApp = $allApps | Where-Object { $_.psGalleryModule } | Select-Object -First 1
$directApp    = $allApps | Where-Object { $_.directDownload -and -not $_.wingetId } | Select-Object -First 1
$vscodeApp    = $allApps | Where-Object { $_.vscodeExtensionId } | Select-Object -First 1
$wslApp       = $allApps | Where-Object { $_.wslDistroName } | Select-Object -First 1
$featureApp   = $allApps | Where-Object { $_.windowsFeatureMethod } | Select-Object -First 1

Assert-Equal 'Winget app method'          (Get-USBMethod $wingetApp)    'Winget'
Assert-Equal 'PSGallery app method'       (Get-USBMethod $psGalleryApp) 'PSGallery'
Assert-Equal 'DirectDownload app method'  (Get-USBMethod $directApp)    'DirectDownload'
Assert-Equal 'VSCodeExtension method'     (Get-USBMethod $vscodeApp)    'VSCodeExtension'
Assert-Equal 'WSL distro method'          (Get-USBMethod $wslApp)       'WSL'
Assert-Equal 'WindowsFeature method'      (Get-USBMethod $featureApp)   'WindowsFeature'

# -----------------------------------------------------------------------
# Test 3: includeInUSBKit=false apps are skipped in Invoke-USBDownloadSingle
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: includeInUSBKit=false skipping ---" -ForegroundColor Yellow

$excludedApp = $allApps | Where-Object { $_.includeInUSBKit -eq $false } | Select-Object -First 1
Assert-NotNull 'Found an includeInUSBKit=false app' $excludedApp

$skipResult = Invoke-USBDownloadSingle -App $excludedApp `
                  -InstallersPath $fakeInstallers `
                  -WingetPath     $fakeWinget `
                  -ModulesPath    $fakeModules

Assert-Equal 'Excluded app status is Skipped'     $skipResult.Status   'Skipped'
Assert-Equal 'Excluded app LocalPath is null'     $skipResult.LocalPath $null

# -----------------------------------------------------------------------
# Test 4: VSCodeExtension apps return Skipped
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: VSCodeExtension skip ---" -ForegroundColor Yellow

$vsCodeResult = Invoke-USBDownloadSingle -App $vscodeApp `
                    -InstallersPath $fakeInstallers `
                    -WingetPath     $fakeWinget `
                    -ModulesPath    $fakeModules

Assert-Equal 'VSCodeExtension status is Skipped'   $vsCodeResult.Status   'Skipped'
Assert-Equal 'VSCodeExtension LocalPath is null'   $vsCodeResult.LocalPath $null

# -----------------------------------------------------------------------
# Test 5: WSL apps return Skipped
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: WSL distro skip ---" -ForegroundColor Yellow

$wslResult = Invoke-USBDownloadSingle -App $wslApp `
                 -InstallersPath $fakeInstallers `
                 -WingetPath     $fakeWinget `
                 -ModulesPath    $fakeModules

Assert-Equal 'WSL status is Skipped'   $wslResult.Status   'Skipped'
Assert-Equal 'WSL LocalPath is null'   $wslResult.LocalPath $null

# -----------------------------------------------------------------------
# Test 6: Winget app returns Success + relative path in DryRun
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: Winget DryRun download ---" -ForegroundColor Yellow

$wingetResult = Invoke-USBDownloadSingle -App $wingetApp `
                    -InstallersPath $fakeInstallers `
                    -WingetPath     $fakeWinget `
                    -ModulesPath    $fakeModules

Assert-Equal   'Winget DryRun status is Success'       $wingetResult.Status 'Success'
Assert-NotNull 'Winget DryRun LocalPath is non-null'   $wingetResult.LocalPath
Assert-True    'Winget DryRun LocalPath starts with installers/winget' `
               ($wingetResult.LocalPath -like 'installers/winget/*')

# -----------------------------------------------------------------------
# Test 7: PSGallery app returns Success in DryRun
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: PSGallery DryRun download ---" -ForegroundColor Yellow

$psResult = Invoke-USBDownloadSingle -App $psGalleryApp `
                -InstallersPath $fakeInstallers `
                -WingetPath     $fakeWinget `
                -ModulesPath    $fakeModules

Assert-Equal 'PSGallery DryRun status is Success'      $psResult.Status    'Success'
Assert-Equal 'PSGallery DryRun LocalPath is modules'   $psResult.LocalPath 'installers/modules'

# -----------------------------------------------------------------------
# Test 8: DirectDownload app returns Success + relative path in DryRun
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: DirectDownload DryRun download ---" -ForegroundColor Yellow

if ($directApp) {
    $ddResult = Invoke-USBDownloadSingle -App $directApp `
                    -InstallersPath $fakeInstallers `
                    -WingetPath     $fakeWinget `
                    -ModulesPath    $fakeModules

    Assert-Equal   'DirectDownload DryRun status is Success'    $ddResult.Status 'Success'
    Assert-NotNull 'DirectDownload DryRun LocalPath is non-null' $ddResult.LocalPath
    Assert-True    'DirectDownload DryRun LocalPath starts with installers/' `
                   ($ddResult.LocalPath -like 'installers/*')
} else {
    Write-Host "  SKIP: No directDownload-only app found in manifest" -ForegroundColor Gray
}

# -----------------------------------------------------------------------
# Test 9: WindowsFeature apps return Skipped
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: WindowsFeature skip ---" -ForegroundColor Yellow

$featureAppIncluded = $allApps | Where-Object {
    $_.windowsFeatureMethod -and $_.includeInUSBKit -ne $false
} | Select-Object -First 1

if ($featureAppIncluded) {
    $featResult = Invoke-USBDownloadSingle -App $featureAppIncluded `
                      -InstallersPath $fakeInstallers `
                      -WingetPath     $fakeWinget `
                      -ModulesPath    $fakeModules
    Assert-Equal 'WindowsFeature status is Skipped'   $featResult.Status   'Skipped'
    Assert-Equal 'WindowsFeature LocalPath is null'   $featResult.LocalPath $null
} else {
    Write-Host "  SKIP: No non-excluded WindowsFeature app found in manifest" -ForegroundColor Gray
}

# -----------------------------------------------------------------------
# Test 10: Registry app returns Skipped
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: Registry skip ---" -ForegroundColor Yellow

$registryApp = $allApps | Where-Object {
    $_.registryPath -and $_.includeInUSBKit -ne $false
} | Select-Object -First 1

if ($registryApp) {
    $regResult = Invoke-USBDownloadSingle -App $registryApp `
                     -InstallersPath $fakeInstallers `
                     -WingetPath     $fakeWinget `
                     -ModulesPath    $fakeModules
    Assert-Equal 'Registry status is Skipped'   $regResult.Status   'Skipped'
    Assert-Equal 'Registry LocalPath is null'   $regResult.LocalPath $null
} else {
    Write-Host "  SKIP: No non-excluded Registry app found in manifest" -ForegroundColor Gray
}

# -----------------------------------------------------------------------
# Test 11: Chocolatey apps return Skipped
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: Chocolatey skip ---" -ForegroundColor Yellow

$chocoApp = [PSCustomObject]@{
    id              = 'test-choco'
    displayName     = 'Test Choco App'
    chocolateyId    = 'some-choco-package'
    includeInUSBKit = $true
}

$chocoResult = Invoke-USBDownloadSingle -App $chocoApp `
                   -InstallersPath $fakeInstallers `
                   -WingetPath     $fakeWinget `
                   -ModulesPath    $fakeModules

Assert-Equal 'Chocolatey status is Skipped'   $chocoResult.Status   'Skipped'
Assert-Equal 'Chocolatey LocalPath is null'   $chocoResult.LocalPath $null

# -----------------------------------------------------------------------
# Test 12: Invoke-USBBuild end-to-end DryRun (subset of apps)
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: Invoke-USBBuild full DryRun ---" -ForegroundColor Yellow

# Use a small cross-section: one winget, one PSGallery, one VSCode, one WSL
$testApps = @(
    $wingetApp,
    $psGalleryApp,
    $vscodeApp,
    $wslApp
) | Where-Object { $null -ne $_ }

$tempDest = Join-Path $env:TEMP 'LoadoutUSBTest'

$startCount = 0
$doneCount  = 0
$onStart    = { param($i, $n, $name) $script:startCount++ }
$onDone     = { param($i, $n, $result) $script:doneCount++ }

$buildResults = Invoke-USBBuild -Apps $testApps `
                                -Destination $tempDest `
                                -OnItemStart $onStart `
                                -OnItemDone  $onDone

Assert-NotNull 'Invoke-USBBuild returns a hashtable'    $buildResults
Assert-Equal   'OnItemStart called for each eligible app' $startCount ($testApps | Where-Object { $_.includeInUSBKit -ne $false }).Count
Assert-Equal   'OnItemDone called for each eligible app'  $doneCount  ($testApps | Where-Object { $_.includeInUSBKit -ne $false }).Count

# VSCode extension should be Skipped
if ($vscodeApp -and $buildResults.ContainsKey($vscodeApp.id)) {
    Assert-Equal 'VSCode app in results is Skipped' $buildResults[$vscodeApp.id] 'Skipped'
}
# WSL should be Skipped
if ($wslApp -and $buildResults.ContainsKey($wslApp.id)) {
    Assert-Equal 'WSL app in results is Skipped' $buildResults[$wslApp.id] 'Skipped'
}
# Winget should be Success (DryRun)
if ($wingetApp -and $buildResults.ContainsKey($wingetApp.id)) {
    Assert-Equal 'Winget app in results is Success (DryRun)' $buildResults[$wingetApp.id] 'Success'
}
# PSGallery should be Success (DryRun)
if ($psGalleryApp -and $buildResults.ContainsKey($psGalleryApp.id)) {
    Assert-Equal 'PSGallery app in results is Success (DryRun)' $buildResults[$psGalleryApp.id] 'Success'
}

# -----------------------------------------------------------------------
# Test 13: Get-USBBuildResults returns last build's hashtable
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "--- Test: Get-USBBuildResults ---" -ForegroundColor Yellow

$retrieved = Get-USBBuildResults
Assert-NotNull 'Get-USBBuildResults returns non-null' $retrieved
Assert-Equal   'Get-USBBuildResults count matches build'  $retrieved.Count $buildResults.Count

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ""
Write-Host "=== Results: $pass passed, $fail failed ===" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })

if ($fail -gt 0) { exit 1 }

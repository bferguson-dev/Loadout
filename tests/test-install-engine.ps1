# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

# test-install-engine.ps1 -- Dry-run test for ManifestManager + InstallEngine
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File tests\test-install-engine.ps1
#
# Covers:
#   - ManifestManager loading and Resolve-InstallPlan (with dependency pull-in)
#   - InstallEngine Phase 1 (prerequisite), Phase 2 (winget + PSGallery),
#     Phase 3 (direct download), Phase 4 (WSL), Phase 5 (Windows Features +
#     Registry settings + PostInstallOnly), Phase 6 (post-install commands)
#   - DryRun mode: all external calls logged but never executed
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

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

Write-Host '======================================================'
Write-Host ' Loadout Install Engine -- Dry Run Test'
Write-Host '======================================================'
Write-Host ''

# -----------------------------------------------------------------------
# Load modules
# -----------------------------------------------------------------------
$srcDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'

. "$srcDir\Logger.ps1"
. "$srcDir\ManifestManager.ps1"
. "$srcDir\InstallEngine.ps1"

# -----------------------------------------------------------------------
# Initialize Logger in DryRun mode
# -----------------------------------------------------------------------
Initialize-Logger -DryRun

Write-Log -Message 'Test script started -- all installs are simulated' -Level INFO

# -----------------------------------------------------------------------
# Initialize ManifestManager (loads manifest.json from repo root)
# -----------------------------------------------------------------------
Initialize-ManifestManager

# -----------------------------------------------------------------------
# Select a representative set of app IDs covering all install paths:
#
#   git              -- Winget (Phase 2, no deps)
#   vscode           -- Winget (Phase 2, no deps)
#   powercli         -- PSGallery (Phase 2, post-install command)
#   vmrc             -- DirectDownload (Phase 3)
#   wsl-ubuntu-2404  -- WSL distro (Phase 4)
#   feature-openssh  -- WindowsFeature/Add-WindowsCapability (Phase 5)
#   setting-fileextensions -- Registry/Set-ItemProperty (Phase 5)
#   setting-highperformance -- PostInstallOnly/powercfg (Phase 5, Phase 6)
#   ext-powershell   -- VSCodeExtension (deferred to Session 12)
#
# Also test dependency pull-in: ext-powershell depends on 'vscode'.
# Since vscode is already selected, it must appear only once in the plan.
# -----------------------------------------------------------------------
Write-Log -Message 'Building test selection...' -Level INFO

$selectedIds = @(
    'git',                    # Phase 2 -- Winget
    'vscode',                 # Phase 2 -- Winget (also a dependency of ext-powershell below)
    'powercli',               # Phase 2 -- PSGallery
    'vmrc',                   # Phase 3 -- DirectDownload
    'wsl-ubuntu-2404',        # Phase 4 -- WSL distro
    'feature-openssh',        # Phase 5 -- WindowsFeature (Add-WindowsCapability)
    'setting-fileextensions', # Phase 5 -- Registry (Set-ItemProperty)
    'setting-highperformance',# Phase 5 + Phase 6 -- PostInstallOnly (powercfg)
    'ext-powershell'          # Phase 6 -- VSCodeExtension; has dep on 'vscode' (dedup test)
)

Write-Log -Message "Selected IDs: $($selectedIds -join ', ')" -Level DEBUG

# -----------------------------------------------------------------------
# Resolve install plan (expands dependencies, deduplicates)
# -----------------------------------------------------------------------
Write-Log -Message 'Resolving install plan...' -Level INFO

$plan = Resolve-InstallPlan -SelectedIds $selectedIds

$planIds = ($plan | ForEach-Object { $_.id }) -join ', '
Write-Log -Message "Resolved plan order: $planIds" -Level INFO
Write-Host ''

# Verify vscode appears exactly once (dedup check)
$vscodeCount = @($plan | Where-Object { $_.id -eq 'vscode' }).Count
if ($vscodeCount -eq 1) {
    Write-Log -Message "Dedup check: 'vscode' appears $vscodeCount time in plan (PASS)" -Level OK
}
else {
    Write-Log -Message "Dedup check: 'vscode' appears $vscodeCount times in plan (FAIL -- expected 1)" -Level ERROR
}
Write-Host ''

# -----------------------------------------------------------------------
# Execute the install plan in DryRun mode
# -----------------------------------------------------------------------
Write-Log -Message 'Invoking install plan...' -Level INFO
Write-Host ''

$results = Invoke-InstallPlan -Apps $plan

# -----------------------------------------------------------------------
# Print install results table
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '------------------------------------------------------'
Write-Host ' Install Results'
Write-Host '------------------------------------------------------'

foreach ($id in ($results.Keys | Sort-Object)) {
    $outcome = $results[$id]
    $color   = switch ($outcome) {
        'Success'  { 'Green'  }
        'Failed'   { 'Red'    }
        'Skipped'  { 'Yellow' }
        'Deferred' { 'Cyan'   }
        default    { 'White'  }
    }
    Write-Host ("  {0,-30} {1}" -f $id, $outcome) -ForegroundColor $color
}

# Assert DryRun-mode install outcomes for Session 11+12 methods
Write-Host ''
$installChecks = @{
    'feature-openssh'         = 'Success'  # WindowsFeature DryRun -> Success
    'setting-fileextensions'  = 'Success'  # Registry DryRun -> Success
    'setting-highperformance' = 'Success'  # PostInstallOnly DryRun -> Success
    'ext-powershell'          = 'Success'  # VSCodeExtension DryRun -> Success
}

$installAllPass = $true
foreach ($checkId in $installChecks.Keys) {
    $expected = $installChecks[$checkId]
    $actual   = $results[$checkId]
    if ($actual -eq $expected) {
        Write-Log -Message "Install check '$checkId': $actual (PASS)" -Level OK
    } else {
        Write-Log -Message "Install check '$checkId': expected $expected, got $actual (FAIL)" -Level ERROR
        $installAllPass = $false
    }
}

if ($installAllPass) {
    Write-Log -Message 'All install checks passed.' -Level OK
} else {
    Write-Log -Message 'One or more install checks FAILED.' -Level ERROR
}

# -----------------------------------------------------------------------
# Invoke-UninstallPlan -- DryRun test
# Covers each supported uninstall method including Session 12 (VSCodeExtension).
#
#   git                    -- Winget uninstall
#   powercli               -- PSGallery uninstall
#   vmrc                   -- DirectDownload uninstall (registry read skipped)
#   wsl-ubuntu-2404        -- WSL uninstall via wsl --unregister
#   feature-openssh        -- WindowsFeature uninstall (Remove-WindowsCapability)
#   setting-fileextensions -- Registry (not uninstallable -- no default value)
#   setting-highperformance -- PostInstallOnly (not uninstallable)
#   ext-powershell         -- VSCodeExtension uninstall via code --uninstall-extension
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '------------------------------------------------------'
Write-Host ' Uninstall Plan (DryRun)'
Write-Host '------------------------------------------------------'

Write-Log -Message 'Building uninstall test selection...' -Level INFO

$uninstallApps = @(
    (Get-AppById -Id 'git'),
    (Get-AppById -Id 'powercli'),
    (Get-AppById -Id 'vmrc'),
    (Get-AppById -Id 'wsl-ubuntu-2404'),
    (Get-AppById -Id 'feature-openssh'),
    (Get-AppById -Id 'setting-fileextensions'),
    (Get-AppById -Id 'setting-highperformance'),
    (Get-AppById -Id 'ext-powershell')
)

$uResults = Invoke-UninstallPlan -Apps $uninstallApps

Write-Host ''
foreach ($id in ($uResults.Keys | Sort-Object)) {
    $outcome = $uResults[$id]
    $color   = switch ($outcome) {
        'Success'  { 'Green'  }
        'Failed'   { 'Red'    }
        'Skipped'  { 'Yellow' }
        default    { 'White'  }
    }
    Write-Host ("  {0,-30} {1}" -f $id, $outcome) -ForegroundColor $color
}

Write-Host ''

# Assert DryRun-mode uninstall outcomes
$uninstallChecks = @{
    'git'                    = 'Success'  # Winget DryRun -> Success
    'powercli'               = 'Success'  # PSGallery DryRun -> Success
    'vmrc'                   = 'Success'  # DirectDownload DryRun -> Success (registry skipped)
    'wsl-ubuntu-2404'        = 'Success'  # WSL -> wsl --unregister (DryRun -> Success)
    'feature-openssh'        = 'Success'  # WindowsFeature -> Remove-WindowsCapability (DryRun -> Success)
    'setting-fileextensions' = 'Skipped'  # Registry -- no default value, uninstall not supported
    'setting-highperformance'= 'Skipped'  # PostInstallOnly -- cannot undo powercfg
    'ext-powershell'         = 'Success'  # VSCodeExtension -> code --uninstall-extension (DryRun -> Success)
}

$allPass = $true
foreach ($checkId in $uninstallChecks.Keys) {
    $expected = $uninstallChecks[$checkId]
    $actual   = $uResults[$checkId]
    if ($actual -eq $expected) {
        Write-Log -Message "Uninstall check '$checkId': $actual (PASS)" -Level OK
    } else {
        Write-Log -Message "Uninstall check '$checkId': expected $expected, got $actual (FAIL)" -Level ERROR
        $allPass = $false
    }
}

Write-Host ''
if ($allPass) {
    Write-Log -Message 'All uninstall checks passed.' -Level OK
} else {
    Write-Log -Message 'One or more uninstall checks FAILED.' -Level ERROR
}

Write-Host ''
Write-Host '======================================================'
Write-Host ' Test complete -- check log output above for details'
Write-Host '======================================================'

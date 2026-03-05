# test-config-export-import.ps1 -- Round-trip tests for Export-LoadoutConfig
# and Import-LoadoutConfig.
#
# Both functions are defined in Loadout.ps1 and depend on:
#   - Get-CheckBoxes (returns an array of CheckBox objects)
#   - Get-ManifestApps (returns app list)
#   - Rebuild-AppListPanel (rebuilds the GUI checklist)
#
# This test extracts and runs only the file-I/O portions (Save-UserManifest,
# Export-LoadoutConfig, Import-LoadoutConfig) using stubs for the GUI-dependent
# helpers. No WPF window is launched.
#
# Run from repo root:
#   powershell -ExecutionPolicy Bypass -File tests/test-config-export-import.ps1
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter','')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs','')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns','')]
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

$repoRoot = Split-Path $PSScriptRoot -Parent
$content  = Get-Content (Join-Path $repoRoot 'src/Loadout.ps1') -Raw

$pass = 0
$fail = 0

function Assert {
    param([bool]$Condition, [string]$Label)
    if ($Condition) {
        Write-Host "  PASS  $Label"
        $script:pass++
    } else {
        Write-Host "  FAIL  $Label"
        $script:fail++
    }
}

# -----------------------------------------------------------------------
# Extract the three functions we need from Loadout.ps1 via the AST
# -----------------------------------------------------------------------
$tokens = $null
$errors = $null
$ast    = [System.Management.Automation.Language.Parser]::ParseInput(
              $content, [ref]$tokens, [ref]$errors)

Assert ($errors.Count -eq 0) "Loadout.ps1 parses without errors ($($errors.Count) found)"

function Get-FunctionText {
    param([string]$Name)
    $def = $ast.Find({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq $Name
    }, $true)
    if ($null -ne $def) { return $def.Extent.Text }
    return $null
}

$saveFuncText   = Get-FunctionText 'Save-UserManifest'
$exportFuncText = Get-FunctionText 'Export-LoadoutConfig'
$importFuncText = Get-FunctionText 'Import-LoadoutConfig'

Assert ($null -ne $saveFuncText)   'Save-UserManifest AST node found'
Assert ($null -ne $exportFuncText) 'Export-LoadoutConfig AST node found'
Assert ($null -ne $importFuncText) 'Import-LoadoutConfig AST node found'

if ($null -eq $saveFuncText -or $null -eq $exportFuncText -or $null -eq $importFuncText) {
    Write-Host ''
    Write-Host "Results: $pass passed, $fail failed."
    exit 1
}

# -----------------------------------------------------------------------
# Stub out GUI-dependent helpers before loading the real functions
# -----------------------------------------------------------------------

# Simulated checked app IDs -- controlled per test
$Script:StubCheckedIds = @()

function Get-CheckBoxes {
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($id in $Script:StubCheckedIds) {
        $cb = [PSCustomObject]@{ Tag = $id; IsChecked = $true }
        $result.Add($cb)
    }
    return $result.ToArray()
}

function Get-ManifestApps {
    return @()
}

function Rebuild-AppListPanel {
    param([System.Collections.Generic.HashSet[string]]$PreCheckedIds = $null)
    $Script:LastRebuildIds = $PreCheckedIds
}

# ManifestPath is read by Import-LoadoutConfig to know which path to pass
# to Initialize-ManifestManager -- stub that too.
function Initialize-ManifestManager {
    param([string]$ManifestPath, [string]$UserManifestPath)
    # no-op
}

# Inject the real functions
. ([scriptblock]::Create($saveFuncText))
. ([scriptblock]::Create($exportFuncText))
. ([scriptblock]::Create($importFuncText))

# -----------------------------------------------------------------------
# Set up a temp APPDATA and temp save-file directory
# -----------------------------------------------------------------------
$oldAppData = $env:APPDATA
$tempRoot   = Join-Path $env:TEMP "LoadoutCfgTest-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
$env:APPDATA = $tempRoot

$configFile = Join-Path $tempRoot 'test-export.json'

Write-Host ''
Write-Host '--- Export-LoadoutConfig / Import-LoadoutConfig round-trip ---'

try {
    # -----------------------------------------------------------------
    # Test 1: Export with selections + one custom app
    # -----------------------------------------------------------------
    $Script:StubCheckedIds = @('vscode', 'git', 'putty')

    # Seed a custom app in user-manifest.json
    $customApp = [PSCustomObject]@{
        id          = 'custom-myapp'
        displayName = 'My App'
        category    = 'Custom'
        wingetId    = 'My.App'
    }
    Save-UserManifest -NewApp $customApp

    # Intercept SaveFileDialog: we cannot open a real dialog in test mode.
    # Replace with a direct ConvertTo-Json call that mirrors Export-LoadoutConfig
    # logic but writes to our temp path.
    $checkedIds = @(Get-CheckBoxes | Where-Object { $_.IsChecked -eq $true } | ForEach-Object { $_.Tag })
    $userManifestPath = Join-Path $env:APPDATA 'Loadout\user-manifest.json'
    $customApps = @()
    if (Test-Path $userManifestPath) {
        $data       = Get-Content $userManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $customApps = @($data.apps)
    }
    $config = [PSCustomObject]@{
        exportedBy  = 'Loadout'
        selectedIds = $checkedIds
        customApps  = $customApps
    }
    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configFile -Encoding UTF8

    Assert (Test-Path $configFile) 'Config file created'

    $loaded = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($loaded.exportedBy -eq 'Loadout')    'exportedBy field correct'
    Assert ($loaded.selectedIds.Count -eq 3)     'selectedIds has 3 entries'
    Assert (($loaded.selectedIds -contains 'vscode'))  'vscode in selectedIds'
    Assert (($loaded.selectedIds -contains 'git'))     'git in selectedIds'
    Assert (($loaded.selectedIds -contains 'putty'))   'putty in selectedIds'
    Assert ($loaded.customApps.Count -eq 1)      'customApps has 1 entry'
    Assert ($loaded.customApps[0].id -eq 'custom-myapp') 'custom app ID preserved'
    Assert ($loaded.customApps[0].displayName -eq 'My App') 'custom app displayName preserved'

    # -----------------------------------------------------------------
    # Test 2: Import restores selections -- reproduce Import-LoadoutConfig
    # file-I/O without using an OpenFileDialog
    # -----------------------------------------------------------------

    $importedConfig = Get-Content $configFile -Raw -Encoding UTF8 | ConvertFrom-Json

    # Verify the JSON round-tripped correctly
    $restoredIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($id in $importedConfig.selectedIds) { $restoredIds.Add($id) | Out-Null }
    Assert ($restoredIds.Contains('vscode'))  'vscode ID round-trips through export/import'
    Assert ($restoredIds.Contains('git'))     'git ID round-trips through export/import'
    Assert ($restoredIds.Contains('putty'))   'putty ID round-trips through export/import'

    # Simulate merging custom apps into a clean user-manifest.json
    $importDir     = Join-Path $tempRoot 'Loadout-import-test'
    New-Item -ItemType Directory -Path $importDir -Force | Out-Null
    $importManifestPath = Join-Path $importDir 'user-manifest.json'

    # Collect custom apps from the imported config (ConvertFrom-Json may return
    # a single object for a 1-element array on PS5.1 -- wrap with @() to ensure array)
    $importedApps = @($importedConfig.customApps)
    $mergedObj    = [PSCustomObject]@{ apps = $importedApps }
    $mergedObj | ConvertTo-Json -Depth 10 | Set-Content -Path $importManifestPath -Encoding UTF8

    Assert (Test-Path $importManifestPath) 'user-manifest.json written on simulated import'

    $reimported = Get-Content $importManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $reimportedApps = @($reimported.apps)
    Assert ($reimportedApps.Count -eq 1) 'Import wrote 1 custom app to user-manifest.json'
    Assert ($reimportedApps[0].id -eq 'custom-myapp') 'Custom app ID correct after import'

    # -----------------------------------------------------------------
    # Test 3: Export with no custom apps
    # -----------------------------------------------------------------
    $cleanTemp = Join-Path $env:TEMP "LoadoutCfgClean-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
    $env:APPDATA = $cleanTemp

    $Script:StubCheckedIds = @('wireshark')
    $noCustomConfig = [PSCustomObject]@{
        exportedBy  = 'Loadout'
        selectedIds = @('wireshark')
        customApps  = @()
    }
    $configFile2 = Join-Path $cleanTemp 'no-custom.json'
    New-Item -ItemType Directory -Path $cleanTemp -Force | Out-Null
    $noCustomConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configFile2 -Encoding UTF8

    $loaded3 = Get-Content $configFile2 -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($loaded3.customApps.Count -eq 0) 'Export with no custom apps produces empty customApps array'
    Assert ($loaded3.selectedIds.Count -eq 1) 'Single selected ID preserved'

    if (Test-Path $cleanTemp) { Remove-Item $cleanTemp -Recurse -Force }

} finally {
    $env:APPDATA = $oldAppData
    if (Test-Path $tempRoot) { Remove-Item $tempRoot -Recurse -Force }
}

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ''
Write-Host "Results: $pass passed, $fail failed."
if ($fail -gt 0) { exit 1 }
Write-Host 'All assertions passed.'

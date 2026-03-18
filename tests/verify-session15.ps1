# verify-session15.ps1 -- Static assertions for Session 15: Custom App Feature
# Checks that all new GUI controls, functions, and wiring exist in the
# expected files without actually running the WPF application.
#
# Run from repo root:
#   powershell -ExecutionPolicy Bypass -File tests/verify-session15.ps1

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

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
$repoRoot    = Split-Path $PSScriptRoot -Parent
$loadoutPs1  = Join-Path $repoRoot 'src\Loadout.ps1'
$guiXaml     = Join-Path $repoRoot 'src\GUI.xaml'
$parseCheck  = Join-Path $PSScriptRoot 'parse-check.ps1'

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
# 1. Parse check -- all src files must parse without errors
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- Parse check ---'
try {
    $psCommand = Get-PowerShellCommand
    & $psCommand -ExecutionPolicy Bypass -File $parseCheck
    Assert $true 'parse-check.ps1 passed'
} catch {
    Assert $false "parse-check.ps1 failed: $_"
}

# -----------------------------------------------------------------------
# 2. GUI.xaml -- new button names present
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- GUI.xaml controls ---'
$xamlContent = Get-Content $guiXaml -Raw
Assert ($xamlContent -match 'x:Name="BtnAddCustomApp"') 'BtnAddCustomApp declared in GUI.xaml'
Assert ($xamlContent -match 'x:Name="BtnBackup"')       'BtnBackup declared in GUI.xaml'

# -----------------------------------------------------------------------
# 3. Loadout.ps1 -- new function definitions present
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- Loadout.ps1 functions ---'
$ps1Content = Get-Content $loadoutPs1 -Raw
Assert ($ps1Content -match 'function Rebuild-AppListPanel')   'Rebuild-AppListPanel defined'
Assert ($ps1Content -match 'function Search-WingetApps')      'Search-WingetApps defined'
Assert ($ps1Content -match 'function Save-UserManifest')      'Save-UserManifest defined'
Assert ($ps1Content -match 'function Add-CustomApp')          'Add-CustomApp defined'
Assert ($ps1Content -match 'function Export-LoadoutConfig')   'Export-LoadoutConfig defined'
Assert ($ps1Content -match 'function Import-LoadoutConfig')   'Import-LoadoutConfig defined'
Assert ($ps1Content -match 'function Show-CustomAppDialog')   'Show-CustomAppDialog defined'

# -----------------------------------------------------------------------
# 4. Loadout.ps1 -- button handlers wired
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- Loadout.ps1 button wiring ---'
Assert ($ps1Content -match "FindName\('BtnAddCustomApp'\)")   'BtnAddCustomApp handler wired'
Assert ($ps1Content -match "FindName\('BtnConfigExport'\)")   'BtnConfigExport handler wired'
Assert ($ps1Content -match "FindName\('BtnConfigImport'\)")   'BtnConfigImport handler wired'

# -----------------------------------------------------------------------
# 5. Loadout.ps1 -- user-manifest.json path uses APPDATA
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- user-manifest.json path ---'
Assert ($ps1Content -match '\$env:APPDATA') 'Save-UserManifest uses $env:APPDATA'
Assert ($ps1Content -match "user-manifest\.json")   'user-manifest.json filename referenced'

# -----------------------------------------------------------------------
# 6. Loadout.ps1 -- Rebuild-AppListPanel called at startup
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- Startup call ---'
Assert ($ps1Content -match 'Rebuild-AppListPanel')  'Rebuild-AppListPanel called at startup'

# -----------------------------------------------------------------------
# 7. Loadout.ps1 -- winget search uses --accept-source-agreements
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- Winget search correctness ---'
Assert ($ps1Content -match 'accept-source-agreements') 'winget search uses --accept-source-agreements'

# -----------------------------------------------------------------------
# 8. GUI.xaml -- dialog inner controls referenced in Loadout.ps1
# -----------------------------------------------------------------------
Write-Host ''
Write-Host '--- Custom app dialog controls in Loadout.ps1 ---'
Assert ($ps1Content -match 'TxtDisplayName')     'TxtDisplayName referenced'
Assert ($ps1Content -match 'CmbCategory')        'CmbCategory referenced'
Assert ($ps1Content -match 'CmbMethod')          'CmbMethod referenced'
Assert ($ps1Content -match 'TxtPrimaryId')       'TxtPrimaryId referenced'
Assert ($ps1Content -match 'BtnSearchWinget')    'BtnSearchWinget referenced'
Assert ($ps1Content -match 'LstSearchResults')   'LstSearchResults referenced'
Assert ($ps1Content -match 'PnlSilentArgs')      'PnlSilentArgs referenced'

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
Write-Host ''
Write-Host "Results: $pass passed, $fail failed."
if ($fail -gt 0) { exit 1 }
Write-Host 'All assertions passed.'

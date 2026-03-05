# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

# verify-session6.ps1 -- Quick verification of Session 6 output
# Checks PS1 syntax, XAML validity, named controls, and function availability.
# Does NOT launch the GUI window.

$ErrorActionPreference = 'Stop'
$pass = 0
$fail = 0

function Check($label, $ok, $detail = '') {
    if ($ok) {
        Write-Host "  PASS  $label" -ForegroundColor Green
        $script:pass++
    } else {
        Write-Host "  FAIL  $label$(if ($detail) { ': ' + $detail })" -ForegroundColor Red
        $script:fail++
    }
}

$src = Join-Path (Split-Path $PSScriptRoot -Parent) 'src'
$loadoutPath = Join-Path $src 'Loadout.ps1'
$guiPath = Join-Path $src 'GUI.xaml'

Write-Host "`nSession 6 Verification`n" -ForegroundColor Cyan

# --- 1. Files exist ---
Write-Host "[ Files ]"
Check 'src/Loadout.ps1 exists'  (Test-Path $loadoutPath)
Check 'src/GUI.xaml exists'     (Test-Path $guiPath)

# --- 2. PS1 syntax ---
Write-Host "`n[ PS1 Syntax ]"
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path $loadoutPath),
    [ref]$null,
    [ref]$errors
) | Out-Null
Check 'Loadout.ps1 parses without errors' ($errors.Count -eq 0) `
    ($errors | ForEach-Object { $_.Message } | Select-Object -First 3 | Out-String)

# --- 3. XAML is well-formed XML ---
Write-Host "`n[ XAML ]"
try {
    $xml = [System.Xml.XmlDocument]::new()
    $xml.Load((Resolve-Path $guiPath).Path)
    Check 'GUI.xaml is well-formed XML' $true
} catch {
    Check 'GUI.xaml is well-formed XML' $false $_.Exception.Message
    $xml = $null
}

# --- 4. Required named controls present ---
Write-Host "`n[ Named Controls ]"
$required = @(
    'BtnScan',
    'LblVersion',
    'StatusBar',
    'ProgressItem',
    'ProgressOverall',
    'BtnSelectAll',
    'BtnDeselectAll',
    'BtnSelectAllUpdates',
    'BtnDeselectAllUpdates',
    'BtnCommit',
    'BtnBuildUsb',
    'AppListPanel',
    'LogPanel'
)

if ($xml) {
    $found = @{}
    $xml.SelectNodes('//*') | ForEach-Object {
        $n = $_.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        if ($n) { $found[$n] = $true }
    }
    foreach ($name in $required) {
        Check "x:Name='$name' present" ($found.ContainsKey($name))
    }
}

# --- 5. Module dot-source lines present in correct order ---
Write-Host "`n[ Module Imports in Loadout.ps1 ]"
$content = Get-Content $loadoutPath -Raw
# Find dot-source lines specifically (lines matching ^\. "...Module.ps1")
$lines = Get-Content $loadoutPath
$dsLogger   = ($lines | Select-String '^\. .*Logger\.ps1').LineNumber
$dsManifest = ($lines | Select-String '^\. .*ManifestManager\.ps1').LineNumber
$dsEngine   = ($lines | Select-String '^\. .*InstallEngine\.ps1').LineNumber
$dsChecker  = ($lines | Select-String '^\. .*UpdateChecker\.ps1').LineNumber

Check 'Logger.ps1 dot-sourced'          ($dsLogger -gt 0)
Check 'ManifestManager.ps1 dot-sourced' ($dsManifest -gt 0)
Check 'InstallEngine.ps1 dot-sourced'   ($dsEngine -gt 0)
Check 'UpdateChecker.ps1 dot-sourced'   ($dsChecker -gt 0)
Check 'Logger first (before others)'    ($dsLogger -lt $dsManifest -and $dsLogger -lt $dsEngine)

# --- 6. Key wiring patterns present ---
Write-Host "`n[ Wiring Patterns ]"
Check 'XAML load: XmlDocument.Load'       ($content -match 'XmlDocument.*new\(\)')
Check 'XAML load: XmlNodeReader'          ($content -match 'XmlNodeReader')
Check 'XAML load: XamlReader::Load'       ($content -match 'XamlReader.*Load')
Check '$Script:LogPanel assigned'         ($content -match '\$Script:LogPanel\s*=')
Check 'Initialize-Logger called'          ($content -match 'Initialize-Logger')
Check 'Initialize-ManifestManager called' ($content -match 'Initialize-ManifestManager')
Check 'Get-ManifestApps called'           ($content -match 'Get-ManifestApps')
Check 'ShowDialog called'                 ($content -match 'ShowDialog')

# --- 7. ASCII-only ---
Write-Host "`n[ ASCII Safety ]"
foreach ($file in @('Loadout.ps1', 'GUI.xaml')) {
    $bytes = [System.IO.File]::ReadAllBytes((Join-Path $src $file))
    $bad   = $bytes | Where-Object { $_ -gt 127 }
    Check "$file is ASCII-only" (-not $bad)
}

# --- Summary ---
Write-Host "`n----------------------------------------"
$color = if ($fail -eq 0) { 'Green' } else { 'Red' }
Write-Host "  $pass passed, $fail failed" -ForegroundColor $color
Write-Host "----------------------------------------`n"
if ($fail -gt 0) { exit 1 }

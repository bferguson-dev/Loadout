# tests/verify-session16.ps1
# Static assertions for Session 16 -- Session and Machine Backup.
# Verifies source files contain all required structure without running the GUI.
# ASCII-only file -- see Coding Standards in DESIGN.md.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

$ErrorActionPreference = 'Stop'

$Script:passed = 0
$Script:failed = 0

function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        Write-Host "  [PASS] $Name" -ForegroundColor Green
        $Script:passed++
    } else {
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        $Script:failed++
    }
}

$repoRoot    = Split-Path $PSScriptRoot -Parent
$guiPath     = Join-Path $repoRoot 'src\GUI.xaml'
$loadoutPath = Join-Path $repoRoot 'src\Loadout.ps1'

$guiContent     = Get-Content $guiPath     -Raw -Encoding UTF8
$loadoutContent = Get-Content $loadoutPath -Raw -Encoding UTF8

Write-Host 'Session 16 -- Static Assertions' -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------
# 1. Parse check -- Loadout.ps1 syntax
# ------------------------------------------------------------------
Write-Host '--- Parse Checks ---' -ForegroundColor Yellow
try {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $loadoutPath,
        [ref]$null,
        [ref]$errors) | Out-Null
    Assert ($errors.Count -eq 0) "Loadout.ps1: no parse errors ($($errors.Count) found)"
} catch {
    Assert $false "Loadout.ps1: parser threw -- $_"
}

# 2. GUI.xaml is valid XML
try {
    $xmlDoc = [System.Xml.XmlDocument]::new()
    $xmlDoc.LoadXml($guiContent)
    Assert $true 'GUI.xaml: valid XML'
} catch {
    Assert $false "GUI.xaml: XML parse error -- $_"
}

# ------------------------------------------------------------------
# 3. GUI controls
# ------------------------------------------------------------------
Write-Host ''
Write-Host '--- GUI Controls ---' -ForegroundColor Yellow

Assert ($guiContent -match 'x:Name="BtnBackup"')  'GUI.xaml: BtnBackup control exists'
Assert ($guiContent -match 'Content="Import/Export"') 'GUI.xaml: BtnBackup has correct label'

# ------------------------------------------------------------------
# 4. Function definitions
# ------------------------------------------------------------------
Write-Host ''
Write-Host '--- Function Definitions ---' -ForegroundColor Yellow

Assert ($loadoutContent -match 'function Show-SessionBackupDialog') 'Loadout.ps1: Show-SessionBackupDialog defined'
Assert ($loadoutContent -match 'function Export-PuttySessions')     'Loadout.ps1: Export-PuttySessions defined'
Assert ($loadoutContent -match 'function Import-PuttySessions')     'Loadout.ps1: Import-PuttySessions defined'
Assert ($loadoutContent -match 'function Export-WinscpSessions')    'Loadout.ps1: Export-WinscpSessions defined'
Assert ($loadoutContent -match 'function Import-WinscpSessions')    'Loadout.ps1: Import-WinscpSessions defined'
Assert ($loadoutContent -match 'function Export-MachineSnapshot')   'Loadout.ps1: Export-MachineSnapshot defined'
Assert ($loadoutContent -match 'function Import-MachineSnapshot')   'Loadout.ps1: Import-MachineSnapshot defined'

# ------------------------------------------------------------------
# 5. Button wiring
# ------------------------------------------------------------------
Write-Host ''
Write-Host '--- Button Wiring ---' -ForegroundColor Yellow

Assert ($loadoutContent -match "FindName\('BtnBackup'\)")        'Loadout.ps1: BtnBackup click handler wired'
Assert ($loadoutContent -match 'Show-SessionBackupDialog')       'Loadout.ps1: BtnBackup calls Show-SessionBackupDialog'

# ------------------------------------------------------------------
# 6. Registry paths and backup paths
# ------------------------------------------------------------------
Write-Host ''
Write-Host '--- Registry Paths and Backup Directories ---' -ForegroundColor Yellow

Assert ($loadoutContent -match 'SimonTatham\\PuTTY') `
       'Loadout.ps1: PuTTY registry path referenced'
Assert ($loadoutContent -match 'Martin Prikryl\\WinSCP') `
       'Loadout.ps1: WinSCP registry path referenced'
Assert ($loadoutContent -match 'Loadout\\SessionBackups') `
       'Loadout.ps1: SessionBackups directory path used'
Assert ($loadoutContent -match 'WinSCP\.ini') `
       'Loadout.ps1: WinSCP INI fallback path referenced'

# ------------------------------------------------------------------
# 7. reg export / import commands
# ------------------------------------------------------------------
Write-Host ''
Write-Host '--- reg.exe Commands ---' -ForegroundColor Yellow

Assert ($loadoutContent -match 'reg export') 'Loadout.ps1: reg export command used'
Assert ($loadoutContent -match 'reg import') 'Loadout.ps1: reg import command used'

# ------------------------------------------------------------------
# 8. Machine snapshot specifics
# ------------------------------------------------------------------
Write-Host ''
Write-Host '--- Machine Snapshot ---' -ForegroundColor Yellow

Assert ($loadoutContent -match 'ConvertTo-Json')           'Loadout.ps1: ConvertTo-Json used in snapshot export'
Assert ($loadoutContent -match 'ConvertFrom-Json')         'Loadout.ps1: ConvertFrom-Json used in snapshot import'
Assert ($loadoutContent -match 'snapshot-\$date\.json')    'Loadout.ps1: timestamped snapshot filename'
Assert ($loadoutContent -match 'Rebuild-AppListPanel.*PreCheckedIds|PreCheckedIds.*Rebuild-AppListPanel') `
       'Loadout.ps1: Import-MachineSnapshot calls Rebuild-AppListPanel'

# ------------------------------------------------------------------
# 9. Dialog XAML control names
# ------------------------------------------------------------------
Write-Host ''
Write-Host '--- Dialog Control Names ---' -ForegroundColor Yellow

Assert ($loadoutContent -match 'LblPuttyStatus')    'Loadout.ps1: LblPuttyStatus in backup dialog'
Assert ($loadoutContent -match 'LblWinscpStatus')   'Loadout.ps1: LblWinscpStatus in backup dialog'
Assert ($loadoutContent -match 'LblSnapshotStatus') 'Loadout.ps1: LblSnapshotStatus in backup dialog'
Assert ($loadoutContent -match 'BtnPuttyExport')    'Loadout.ps1: BtnPuttyExport in backup dialog'
Assert ($loadoutContent -match 'BtnPuttyImport')    'Loadout.ps1: BtnPuttyImport in backup dialog'
Assert ($loadoutContent -match 'BtnWinscpExport')   'Loadout.ps1: BtnWinscpExport in backup dialog'
Assert ($loadoutContent -match 'BtnWinscpImport')   'Loadout.ps1: BtnWinscpImport in backup dialog'
Assert ($loadoutContent -match 'BtnSnapshotExport') 'Loadout.ps1: BtnSnapshotExport in backup dialog'
Assert ($loadoutContent -match 'BtnSnapshotImport') 'Loadout.ps1: BtnSnapshotImport in backup dialog'
Assert ($loadoutContent -match 'BtnBackupClose')    'Loadout.ps1: BtnBackupClose in backup dialog'

# ------------------------------------------------------------------
# 10. ASCII-only check
# ------------------------------------------------------------------
Write-Host ''
Write-Host '--- Encoding ---' -ForegroundColor Yellow

$nonAsciiMatch = Select-String -Path $loadoutPath -Pattern '[^\x00-\x7F]' -Encoding UTF8
Assert ($null -eq $nonAsciiMatch) 'Loadout.ps1: ASCII-only (no non-ASCII characters)'

$nonAsciiGui = Select-String -Path $guiPath -Pattern '[^\x00-\x7F]' -Encoding UTF8
Assert ($null -eq $nonAsciiGui)   'GUI.xaml: ASCII-only (no non-ASCII characters)'

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Host ''
$color = if ($Script:failed -eq 0) { 'Green' } else { 'Red' }
Write-Host "Results: $($Script:passed) passed, $($Script:failed) failed" -ForegroundColor $color
if ($Script:failed -gt 0) { exit 1 }

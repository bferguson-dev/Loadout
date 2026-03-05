# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

$ErrorActionPreference = 'Stop'
$files = @(
    'src\Loadout.ps1',
    'src\InstallEngine.ps1',
    'src\Logger.ps1',
    'src\ManifestManager.ps1',
    'src\UpdateChecker.ps1',
    'src\USBBuilder.ps1',
    'src\SelfUpdater.ps1',
    'src\Update-Helper.ps1',
    'src\GUI.xaml'
)

$allOk = $true
foreach ($f in $files) {
    $path = Join-Path (Join-Path $PSScriptRoot '..') $f
    if ($f -like '*.xaml') {
        try {
            $xml = [System.Xml.XmlDocument]::new()
            $xml.Load($path)
            Write-Host "OK  $f"
        } catch {
            Write-Host "FAIL $f -- $_"
            $allOk = $false
        }
        continue
    }
    $errors = $null
    $tokens = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
        $path, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        Write-Host "FAIL $f"
        $errors | ForEach-Object { Write-Host "  $_" }
        $allOk = $false
    } else {
        Write-Host "OK  $f"
    }
}
if (-not $allOk) { exit 1 }
Write-Host 'All files passed.'

# Repair-WingetFirewall.ps1
# Diagnoses and repairs Windows Firewall rules that can block winget/App Installer.
# Run from an elevated PowerShell prompt:
#   powershell -ExecutionPolicy Bypass -File scripts/Repair-WingetFirewall.ps1

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$Elevate,
    [switch]$SkipConnectivityTest
)

$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatedSelf {
    param([string]$ScriptPath)

    $args = @('-ExecutionPolicy', 'Bypass', '-File', "`"$ScriptPath`"")
    if ($SkipConnectivityTest) { $args += '-SkipConnectivityTest' }
    if ($WhatIfPreference) { $args += '-WhatIf' }

    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($args -join ' ')
}

function Get-WingetProgramCandidates {
    $paths = [System.Collections.Generic.List[string]]::new()

    $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source) {
        $paths.Add($cmd.Source) | Out-Null
    }

    $pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    if ($pkg -and $pkg.InstallLocation) {
        $possible = @(
            (Join-Path $pkg.InstallLocation 'winget.exe'),
            (Join-Path $pkg.InstallLocation 'AppInstallerCLI.exe')
        )
        foreach ($p in $possible) {
            if (Test-Path $p) { $paths.Add($p) | Out-Null }
        }
    }

    # Always include the common alias path for inspection/rules.
    $aliasPath = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    $paths.Add($aliasPath) | Out-Null

    return @($paths | Select-Object -Unique)
}

function Get-BlockingRulesForWinget {
    param(
        [string[]]$ProgramPaths,
        [string]$PackageFamilyName
    )

    $rules = Get-NetFirewallRule -Direction Outbound -Enabled True -Action Block
    $matches = [System.Collections.Generic.List[object]]::new()

    foreach ($rule in $rules) {
        try {
            $appFilter = Get-NetFirewallApplicationFilter -AssociatedNetFirewallRule $rule
        }
        catch {
            continue
        }

        $program = [string]$appFilter.Program
        $package = [string]$appFilter.Package

        $programMatch = $false
        foreach ($path in $ProgramPaths) {
            if ($program -and $path -and $program.Trim().ToLower() -eq $path.Trim().ToLower()) {
                $programMatch = $true
                break
            }
        }

        $packageMatch = $false
        if ($PackageFamilyName -and $package) {
            $packageMatch = $package -like "*$PackageFamilyName*"
        }

        if ($programMatch -or $packageMatch) {
            $matches.Add($rule) | Out-Null
        }
    }

    return @($matches | Sort-Object DisplayName -Unique)
}

function Ensure-AllowRuleForProgram {
    param(
        [Parameter(Mandatory)] [string]$DisplayName,
        [Parameter(Mandatory)] [string]$ProgramPath
    )

    $existing = Get-NetFirewallRule -DisplayName $DisplayName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Output "Rule exists: $DisplayName"
        return
    }

    if ($PSCmdlet.ShouldProcess($DisplayName, "Create allow outbound rule for $ProgramPath")) {
        New-NetFirewallRule -DisplayName $DisplayName `
                            -Direction Outbound `
                            -Action Allow `
                            -Program $ProgramPath `
                            -Profile Any | Out-Null
        Write-Output "Created rule: $DisplayName"
    }
}

if (-not (Test-IsAdministrator)) {
    if ($Elevate) {
        Write-Output 'Not elevated. Relaunching as Administrator...'
        Start-ElevatedSelf -ScriptPath $PSCommandPath
        exit 0
    }
    throw 'Administrator privileges are required. Re-run as admin or use -Elevate.'
}

Write-Output 'Checking winget/App Installer firewall state...'

$pkg = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
if (-not $pkg) {
    Write-Warning 'Microsoft.DesktopAppInstaller is not installed. Firewall repair alone will not restore winget.'
}

$packageFamily = if ($pkg) { $pkg.PackageFamilyName } else { '' }
$programPaths  = Get-WingetProgramCandidates

Write-Output 'Program candidates:'
$programPaths | ForEach-Object { Write-Output "  - $_" }

$blockingRules = Get-BlockingRulesForWinget -ProgramPaths $programPaths -PackageFamilyName $packageFamily
if ($blockingRules.Count -eq 0) {
    Write-Output 'No explicit outbound BLOCK rules found for winget/App Installer targets.'
}
else {
    Write-Output "Found $($blockingRules.Count) outbound BLOCK rule(s) affecting winget/App Installer."
    foreach ($rule in $blockingRules) {
        Write-Output "  - $($rule.DisplayName)"
        if ($PSCmdlet.ShouldProcess($rule.DisplayName, 'Disable blocking rule')) {
            Disable-NetFirewallRule -InputObject $rule | Out-Null
        }
    }
}

# Add explicit allow rules for discovered winget/app-installer executables.
foreach ($programPath in $programPaths) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($programPath)
    $ruleName = "Loadout Allow ${baseName} Outbound"
    Ensure-AllowRuleForProgram -DisplayName $ruleName -ProgramPath $programPath
}

if (-not $SkipConnectivityTest) {
    Write-Output 'Connectivity test:'
    $targets = @(
        'https://api.github.com',
        'https://cdn.winget.microsoft.com',
        'https://aka.ms'
    )
    foreach ($u in $targets) {
        try {
            $resp = Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 10
            Write-Output "  OK  $u (HTTP $($resp.StatusCode))"
        }
        catch {
            Write-Output "  FAIL $u ($($_.Exception.Message))"
        }
    }
}

Write-Output ''
Write-Output 'Done. Test winget with: winget --version'

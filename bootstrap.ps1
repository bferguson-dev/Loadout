#Requires -Version 5.1
<#
.SYNOPSIS
    Loadout bootstrapper -- downloads and installs Loadout from GitHub.
.DESCRIPTION
    Run via one-liner in an elevated PowerShell prompt:
        irm https://bferguson-dev.github.io/Loadout/install | iex

    Or directly:
        irm https://raw.githubusercontent.com/bferguson-dev/Loadout/main/bootstrap.ps1 | iex
.NOTES
    This script handles its own elevation. Running from a non-elevated prompt is supported.
    Machine and user execution policies are never modified -- Process scope only.
#>

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
$Script:LoadoutAppData  = Join-Path $env:APPDATA 'Loadout'
$Script:RawBaseUrl      = 'https://raw.githubusercontent.com/bferguson-dev/Loadout/main'
$Script:VersionJsonUrl  = "$Script:RawBaseUrl/version.json"
$Script:BootstrapUrl    = "$Script:RawBaseUrl/bootstrap.ps1"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Status {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )
    $ts     = Get-Date -Format 'HH:mm:ss'
    $prefix = "[$ts] [$($Level.PadRight(5))]"
    switch ($Level) {
        'OK'    { Write-Host "$prefix $Message" -ForegroundColor Green }
        'WARN'  { Write-Host "$prefix $Message" -ForegroundColor Yellow }
        'ERROR' { Write-Host "$prefix $Message" -ForegroundColor Red }
        default { Write-Host "$prefix $Message" }
    }
}

function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-PreferredPowerShell {
    # Return path to pwsh.exe (PS7) if available, otherwise powershell.exe
    $pwsh = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
    if ($pwsh) { return $pwsh.Source }
    return 'powershell.exe'
}

function Get-TempBootstrapPath {
    return Join-Path $env:TEMP "Loadout-Bootstrap-$(Get-Date -Format 'yyyyMMddHHmmss').ps1"
}

# ---------------------------------------------------------------------------
# Step 1 -- Execution Policy
# ---------------------------------------------------------------------------

function Invoke-ExecutionPolicyCheck {
    Write-Status 'Checking execution policy...'

    $restrictive = @('Restricted', 'AllSigned')

    # Check LocalMachine and CurrentUser scopes as specified by the design.
    # Also check GPO scopes (MachinePolicy, UserPolicy) -- these cannot be overridden
    # via Set-ExecutionPolicy but -ExecutionPolicy on the command line still wins for child processes.
    $localMachine  = Get-ExecutionPolicy -Scope LocalMachine
    $currentUser   = Get-ExecutionPolicy -Scope CurrentUser
    $machinePolicy = Get-ExecutionPolicy -Scope MachinePolicy
    $userPolicy    = Get-ExecutionPolicy -Scope UserPolicy

    if (($machinePolicy -ne 'Undefined') -and ($machinePolicy -in $restrictive)) {
        Write-Status "Machine Group Policy enforces '$machinePolicy' execution policy." 'WARN'
        Write-Status 'Child processes will launch with -ExecutionPolicy Bypass to compensate.' 'WARN'
    }
    if (($userPolicy -ne 'Undefined') -and ($userPolicy -in $restrictive)) {
        Write-Status "User Group Policy enforces '$userPolicy' execution policy." 'WARN'
    }
    if ($localMachine -in $restrictive) {
        Write-Status "LocalMachine execution policy is '$localMachine'." 'WARN'
    }
    if ($currentUser -in $restrictive) {
        Write-Status "CurrentUser execution policy is '$currentUser'." 'WARN'
    }

    $effective = Get-ExecutionPolicy
    if ($effective -in $restrictive) {
        Write-Status "Effective execution policy is '$effective' -- setting Process scope to Bypass for this session only." 'WARN'
        Write-Status 'Machine and user policies are not modified.' 'WARN'
        Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
        Write-Status 'Process-scope execution policy set to Bypass.' 'OK'
    } else {
        Write-Status "Execution policy OK ('$effective')." 'OK'
    }
}

# ---------------------------------------------------------------------------
# Step 2 -- Elevation
# ---------------------------------------------------------------------------

function Invoke-ElevationCheck {
    if (Test-Administrator) {
        Write-Status 'Running as administrator.' 'OK'
        return
    }

    Write-Status 'Not running as administrator -- relaunching elevated...' 'WARN'

    $psExe = Get-PreferredPowerShell

    if ($PSCommandPath) {
        # Running from a saved .ps1 file -- relaunch the same file elevated
        Start-Process $psExe -Verb RunAs `
            -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    } else {
        # Running via irm | iex -- download bootstrap to a temp file and relaunch
        Write-Status 'Saving bootstrap to temp file for elevated relaunch...'
        $tempScript = Get-TempBootstrapPath
        (Invoke-RestMethod $Script:BootstrapUrl) | Set-Content -Path $tempScript -Encoding UTF8
        Start-Process $psExe -Verb RunAs `
            -ArgumentList "-ExecutionPolicy Bypass -File `"$tempScript`""
    }

    exit 0
}

# ---------------------------------------------------------------------------
# Step 3 -- PowerShell Version
# ---------------------------------------------------------------------------

function Invoke-PSVersionCheck {
    $ver = $PSVersionTable.PSVersion
    Write-Status "PowerShell version: $($ver.ToString())"

    if ($ver.Major -lt 7) {
        $pwsh = Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue
        if ($pwsh) {
            Write-Status "PowerShell 7 found at: $($pwsh.Source)" 'OK'
            Write-Status 'Loadout will launch using PowerShell 7.'
        } else {
            Write-Status 'Running PowerShell 5.1. PowerShell 7 is recommended but not required.' 'WARN'
            Write-Status 'Install PowerShell 7: https://aka.ms/install-powershell'
        }
    } else {
        Write-Status "PowerShell $($ver.Major) -- optimal." 'OK'
    }
}

# ---------------------------------------------------------------------------
# Step 4 -- Winget Availability
# ---------------------------------------------------------------------------

function Invoke-WingetDownload {
    param([string]$Url, [string]$Destination)
    Write-Status "Downloading: $(Split-Path $Url -Leaf)"
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

function Invoke-WingetCheck {
    Write-Status 'Checking winget availability...'

    $wingetCmd = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
    if ($wingetCmd) {
        try {
            $ver = (& winget.exe --version 2>&1) -join ''
            if ($LASTEXITCODE -eq 0 -or $ver -match 'v\d') {
                Write-Status "winget found: $($ver.Trim())" 'OK'
                return
            }
        } catch {
            Write-Status "winget version check threw: $_ -- will reinstall." 'WARN'
        }
        Write-Status 'winget found but not functioning -- will reinstall.' 'WARN'
    } else {
        Write-Status 'winget not found -- installing App Installer from GitHub...' 'WARN'
    }

    $tempDir = Join-Path $env:TEMP 'Loadout-WingetInstall'
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        # Resolve latest winget release via GitHub API
        Write-Status 'Fetching latest winget release info from GitHub...'
        $headers = @{ 'User-Agent' = 'Loadout-Bootstrap/1.0' }
        $release = Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' `
            -Headers $headers

        $bundle  = $release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1
        $license = $release.assets | Where-Object { $_.name -like '*License*.xml' }  | Select-Object -First 1

        if (-not $bundle) {
            throw 'Could not locate msixbundle asset in the latest winget release.'
        }

        Write-Status "Latest winget release: $($release.tag_name)"

        # VCLibs dependency
        $vclibsPath = Join-Path $tempDir 'Microsoft.VCLibs.x64.appx'
        Invoke-WingetDownload -Url 'https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx' `
            -Destination $vclibsPath

        # Microsoft.UI.Xaml 2.8.x from NuGet
        $uiXamlPath  = $null
        $nugetPkg    = Join-Path $tempDir 'microsoft.ui.xaml.nupkg'
        $nugetExtDir = Join-Path $tempDir 'xaml-nupkg'
        Invoke-WingetDownload -Url 'https://www.nuget.org/api/v2/package/Microsoft.UI.Xaml/2.8.6' `
            -Destination $nugetPkg
        Expand-Archive -Path $nugetPkg -DestinationPath $nugetExtDir -Force
        $xamlAppx = Get-ChildItem -Path $nugetExtDir -Recurse -Filter '*x64*.appx' | Select-Object -First 1
        if ($xamlAppx) {
            $uiXamlPath = Join-Path $tempDir 'Microsoft.UI.Xaml.x64.appx'
            Copy-Item $xamlAppx.FullName $uiXamlPath
        }

        # Winget bundle itself
        $bundlePath  = Join-Path $tempDir $bundle.name
        $licensePath = if ($license) { Join-Path $tempDir $license.name } else { $null }
        Invoke-WingetDownload -Url $bundle.browser_download_url -Destination $bundlePath
        if ($license) {
            Invoke-WingetDownload -Url $license.browser_download_url -Destination $licensePath
        }

        # Build dependency array
        $deps = [System.Collections.Generic.List[string]]@($vclibsPath)
        if ($uiXamlPath -and (Test-Path $uiXamlPath)) { $deps.Add($uiXamlPath) }

        Write-Status 'Installing winget dependencies and bundle...'
        if ($license -and (Test-Path $licensePath)) {
            Add-AppxProvisionedPackage -Online -PackagePath $bundlePath `
                -DependencyPackagePath $deps.ToArray() -LicensePath $licensePath | Out-Null
        } else {
            Add-AppxPackage -Path $bundlePath -DependencyPath $deps.ToArray()
        }

        # Verify install
        $wingetCmd = Get-Command 'winget.exe' -ErrorAction SilentlyContinue
        if ($wingetCmd) {
            $ver = (& winget.exe --version 2>&1) -join ''
            Write-Status "winget installed successfully: $($ver.Trim())" 'OK'
        } else {
            Write-Status 'winget installed but not yet in PATH. A reboot may be required.' 'WARN'
            Write-Status 'After rebooting, re-run the Loadout one-liner to continue.' 'WARN'
            Read-Host 'Press Enter to exit'
            exit 1
        }

    } catch {
        Write-Status "Failed to install winget: $_" 'ERROR'
        Write-Status 'Loadout requires winget. Install App Installer from the Microsoft Store and retry.' 'ERROR'
        Read-Host 'Press Enter to exit'
        exit 1
    } finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Step 5 -- Windows Build
# ---------------------------------------------------------------------------

function Invoke-WindowsBuildCheck {
    # Minimum supported: Windows 10 version 1903 = build 18362
    $minBuild = 18362
    $build    = [System.Environment]::OSVersion.Version.Build

    try {
        $os     = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
        $osName = if ($os) { $os.Caption } else { 'Unknown' }
    } catch {
        $osName = 'Unknown'
    }

    Write-Status "Operating system: $osName (build $build)"

    if ($build -lt $minBuild) {
        Write-Status "Windows build $build is below the recommended minimum (build $minBuild / version 1903)." 'WARN'
        Write-Status 'Some features may not work correctly. Continuing anyway...' 'WARN'
    } else {
        Write-Status 'Windows build OK (>= 1903).' 'OK'
    }
}

# ---------------------------------------------------------------------------
# Step 6 -- Check if Loadout Already Installed
# Returns $true  if already installed and current (skip download/extract)
# Returns $false if fresh install or update is needed
# ---------------------------------------------------------------------------

function Invoke-InstallCheck {
    if (-not (Test-Path $Script:LoadoutAppData)) {
        Write-Status 'No existing Loadout installation found -- performing fresh install.'
        return $false
    }

    Write-Status "Existing installation found at: $Script:LoadoutAppData" 'OK'
    Write-Status 'Checking for updates...'

    $versionFile = Join-Path $Script:LoadoutAppData 'version.json'
    if (-not (Test-Path $versionFile)) {
        Write-Status 'Local version.json missing -- reinstalling.' 'WARN'
        return $false
    }

    try {
        $local  = (Get-Content $versionFile -Raw | ConvertFrom-Json).version
        $remote = (Invoke-RestMethod $Script:VersionJsonUrl).version

        Write-Status "Installed: v$local  |  Latest: v$remote"

        if ($local -eq $remote) {
            Write-Status "Loadout v$local is up to date." 'OK'
            return $true
        }

        Write-Status "Update available: v$local -> v$remote. Updating..." 'OK'
        return $false

    } catch {
        Write-Status "Could not reach update server: $_" 'WARN'
        Write-Status 'Launching existing installation without update check.'
        return $true
    }
}

# ---------------------------------------------------------------------------
# Step 7 -- Download Latest Release
# ---------------------------------------------------------------------------

function Get-LoadoutRelease {
    Write-Status 'Fetching version info from GitHub...'

    $versionInfo = Invoke-RestMethod $Script:VersionJsonUrl
    $version     = $versionInfo.version
    $releaseUrl  = $versionInfo.releaseUrl

    Write-Status "Downloading Loadout v$version..."
    $zipPath = Join-Path $env:TEMP "Loadout-v$version.zip"
    Invoke-WebRequest -Uri $releaseUrl -OutFile $zipPath -UseBasicParsing
    Write-Status 'Download complete.' 'OK'

    return @{ ZipPath = $zipPath; Version = $version }
}

# ---------------------------------------------------------------------------
# Step 8 -- Extract to AppData
# ---------------------------------------------------------------------------

function Expand-LoadoutRelease {
    param(
        [string]$ZipPath,
        [string]$Version
    )

    Write-Status "Extracting Loadout v$Version to: $Script:LoadoutAppData"

    # Back up existing install in case extraction fails
    $backupPath = "$Script:LoadoutAppData.bak"
    if (Test-Path $Script:LoadoutAppData) {
        Remove-Item $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        Rename-Item $Script:LoadoutAppData $backupPath
    }

    try {
        New-Item -ItemType Directory -Path $Script:LoadoutAppData -Force | Out-Null

        $extractTemp = Join-Path $env:TEMP 'Loadout-Extract'
        Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $ZipPath -DestinationPath $extractTemp -Force

        # Zip may contain a single root folder -- detect and flatten
        $contents   = Get-ChildItem $extractTemp
        $sourceRoot = if ($contents.Count -eq 1 -and $contents[0].PSIsContainer) {
            $contents[0].FullName
        } else {
            $extractTemp
        }

        Copy-Item -Path "$sourceRoot\*" -Destination $Script:LoadoutAppData -Recurse -Force
        Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue

        # Write version.json to install location for version tracking
        $versionInfo = Invoke-RestMethod $Script:VersionJsonUrl
        $versionInfo | ConvertTo-Json -Depth 5 |
            Set-Content (Join-Path $Script:LoadoutAppData 'version.json') -Encoding UTF8

        # Clean up backup on success
        Remove-Item $backupPath -Recurse -Force -ErrorAction SilentlyContinue

        Write-Status "Loadout v$Version installed to: $Script:LoadoutAppData" 'OK'

    } catch {
        # Restore backup on failure
        if (Test-Path $backupPath) {
            Remove-Item $Script:LoadoutAppData -Recurse -Force -ErrorAction SilentlyContinue
            Rename-Item $backupPath $Script:LoadoutAppData
            Write-Status 'Extraction failed -- previous installation restored.' 'WARN'
        }
        throw
    } finally {
        Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Step 9 -- Offer Shortcuts
# NOTE: Text-mode stub. A WPF dialog replaces these Read-Host prompts
#       once the GUI shell is built in a later session.
# ---------------------------------------------------------------------------

function Invoke-ShortcutSetup {
    $loadoutScript = Join-Path $Script:LoadoutAppData 'src\Loadout.ps1'
    $psExe         = Get-PreferredPowerShell
    $wsh           = New-Object -ComObject WScript.Shell

    Write-Host ''
    Write-Status 'Shortcut setup:'

    $addDesktop   = Read-Host '  Add Desktop shortcut? [Y/n]'
    $addStartMenu = Read-Host '  Add Start Menu entry? [Y/n]'

    if ($addDesktop -ne 'n' -and $addDesktop -ne 'N') {
        try {
            $link                  = $wsh.CreateShortcut("$env:USERPROFILE\Desktop\Loadout.lnk")
            $link.TargetPath       = $psExe
            $link.Arguments        = "-ExecutionPolicy Bypass -File `"$loadoutScript`""
            $link.WorkingDirectory = Split-Path $loadoutScript
            $link.Description      = 'Loadout - Windows Infrastructure Setup Tool'
            $link.Save()
            Write-Status 'Desktop shortcut created.' 'OK'
        } catch {
            Write-Status "Could not create Desktop shortcut: $_" 'WARN'
        }
    }

    if ($addStartMenu -ne 'n' -and $addStartMenu -ne 'N') {
        try {
            $startMenuDir          = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
            $link                  = $wsh.CreateShortcut("$startMenuDir\Loadout.lnk")
            $link.TargetPath       = $psExe
            $link.Arguments        = "-ExecutionPolicy Bypass -File `"$loadoutScript`""
            $link.WorkingDirectory = Split-Path $loadoutScript
            $link.Description      = 'Loadout - Windows Infrastructure Setup Tool'
            $link.Save()
            Write-Status 'Start Menu entry created.' 'OK'
        } catch {
            Write-Status "Could not create Start Menu entry: $_" 'WARN'
        }
    }
}

# ---------------------------------------------------------------------------
# Step 10 -- Launch Loadout
# ---------------------------------------------------------------------------

function Start-Loadout {
    $loadoutScript = Join-Path $Script:LoadoutAppData 'src\Loadout.ps1'

    if (-not (Test-Path $loadoutScript)) {
        Write-Status "Loadout.ps1 not found at: $loadoutScript" 'ERROR'
        Write-Status 'Installation may be incomplete. Please re-run the one-liner.' 'ERROR'
        Read-Host 'Press Enter to exit'
        exit 1
    }

    $psExe = Get-PreferredPowerShell
    Write-Host ''
    Write-Status 'Launching Loadout...' 'OK'

    Start-Process $psExe -ArgumentList "-ExecutionPolicy Bypass -File `"$loadoutScript`""
}

# ===========================================================================
# MAIN -- Bootstrap Sequence
# ===========================================================================

Write-Host ''
Write-Host '  ======================================' -ForegroundColor Cyan
Write-Host '    L O A D O U T'                       -ForegroundColor Cyan
Write-Host '    Windows Infrastructure Setup Tool'   -ForegroundColor Cyan
Write-Host '    github.com/bferguson-dev/Loadout'    -ForegroundColor Gray
Write-Host '  ======================================' -ForegroundColor Cyan
Write-Host ''

try {
    # Step 1 -- Execution Policy
    Invoke-ExecutionPolicyCheck

    # Step 2 -- Elevation (exits and relaunches if not admin)
    Invoke-ElevationCheck

    # Step 3 -- PowerShell Version
    Invoke-PSVersionCheck

    # Step 4 -- Winget
    Invoke-WingetCheck

    # Step 5 -- Windows Build
    Invoke-WindowsBuildCheck

    # Step 6 -- Check existing install / update status
    $alreadyInstalled = Invoke-InstallCheck

    if (-not $alreadyInstalled) {
        # Step 7 -- Download latest release
        $release = Get-LoadoutRelease

        # Step 8 -- Extract to AppData
        Expand-LoadoutRelease -ZipPath $release.ZipPath -Version $release.Version
    }

    # Step 9 -- Shortcuts
    Invoke-ShortcutSetup

    # Step 10 -- Launch Loadout.ps1
    Start-Loadout

} catch {
    Write-Host ''
    Write-Status "Bootstrap failed: $_" 'ERROR'
    Write-Status 'Check your internet connection and try again.' 'ERROR'
    Read-Host 'Press Enter to exit'
    exit 1
}

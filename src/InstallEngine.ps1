# InstallEngine.ps1 -- Loadout install engine
# Executes an install plan produced by ManifestManager.Resolve-InstallPlan
# in six sequential phases. Supports DryRun mode: every external call is
# guarded by $Script:DryRun (set by Logger.Initialize-Logger) and is
# replaced with a Write-Log describing what would have run.
#
# Public install entry point: Invoke-InstallPlan -Apps <array of app objects>
# Public uninstall entry point: Invoke-UninstallPlan -Apps <array of app objects>
#
# Deferred to later sessions:
#   VS Code Extensions (Session 12) -- skipped here, logged as deferred
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns','')]
param()

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------
# Script-scope state -- reset at the start of each Invoke-InstallPlan call
# -----------------------------------------------------------------------

# id -> 'Success' | 'Failed' | 'Skipped' | 'Deferred'
$Script:InstallResults = @{}

# id -> 'Success' | 'Failed' | 'Skipped'
$Script:UninstallResults = @{}

# IDs of prerequisite apps that failed -- dependents are skipped
$Script:FailedPrereqIds = [System.Collections.Generic.HashSet[string]]::new()

# Progress tracking -- set by Invoke-InstallPlan, read by Invoke-SingleApp
$Script:OnItemStart     = $null   # scriptblock ($index, $total, $displayName)
$Script:OnItemDone      = $null   # scriptblock ($index, $total, $result)
$Script:ProgressIndex   = 0
$Script:ProgressTotal   = 0

# Chocolatey gate -- $true only when the commit preview dialog has been confirmed
$Script:AllowChocolatey = $false

# IDs that should use 'winget upgrade' instead of 'winget install'
# Populated by Set-UpgradeIds before Invoke-InstallPlan for update operations.
$Script:UpgradeIdSet = [System.Collections.Generic.HashSet[string]]::new()

# -----------------------------------------------------------------------
# Private: Get-InstallMethod
# Returns the primary install method string for an app object.
# Priority: WSL > WindowsFeature > Registry > VSCodeExtension >
#           Winget > PSGallery > DirectDownload > Chocolatey > Unknown
# -----------------------------------------------------------------------
function Get-InstallMethod {
    param([Parameter(Mandatory)] [object]$App)

    if ($App.wslDistroName)         { return 'WSL' }
    if ($App.windowsFeatureMethod)  { return 'WindowsFeature' }
    if ($App.registryPath)          { return 'Registry' }
    if ($App.vscodeExtensionId)     { return 'VSCodeExtension' }
    if ($App.wingetId)              { return 'Winget' }
    if ($App.psGalleryModule)       { return 'PSGallery' }
    if ($App.directDownload)        { return 'DirectDownload' }
    if ($App.chocolateyId)          { return 'Chocolatey' }
    if ($App.postInstallOnly -eq $true)  { return 'PostInstallOnly' }
    # Apps with only postInstallCommands and no other install method
    if ($App.postInstallCommands -and $App.postInstallCommands.Count -gt 0) { return 'PostInstallOnly' }
    return 'Unknown'
}

# -----------------------------------------------------------------------
# Private: Test-DependenciesMet
# Returns $true if every dependency of the app either succeeded this run
# or was not in the install plan (assumed already installed).
# Returns $false and logs a reason if any dependency failed.
# -----------------------------------------------------------------------
function Test-DependenciesMet {
    param([Parameter(Mandatory)] [object]$App)

    if (-not $App.dependencies -or $App.dependencies.Count -eq 0) {
        return $true
    }

    foreach ($depId in $App.dependencies) {
        if ($Script:FailedPrereqIds.Contains($depId)) {
            Write-Log -Message "[$($App.displayName)] Skipped -- prerequisite '$depId' failed to install" -Level WARN
            return $false
        }
        # If the dep was in the plan and failed (non-prereq dependency)
        if ($Script:InstallResults[$depId] -eq 'Failed') {
            Write-Log -Message "[$($App.displayName)] Skipped -- dependency '$depId' failed to install" -Level WARN
            return $false
        }
    }

    return $true
}

# -----------------------------------------------------------------------
# Public: Set-UpgradeIds
# Registers app IDs that should use 'winget upgrade' (not 'winget install')
# during the next Invoke-InstallPlan call. Called by Loadout.ps1 before
# launching the install runspace when the Commit plan includes updates.
# -----------------------------------------------------------------------
function Set-UpgradeIds {
    param([string[]]$Ids)
    $Script:UpgradeIdSet.Clear()
    foreach ($id in $Ids) {
        if ($id) { $Script:UpgradeIdSet.Add($id) | Out-Null }
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-WingetInstall
# Runs winget install (or upgrade for IDs in UpgradeIdSet) with the exact
# flags from DESIGN.md Section 9.
# In DryRun mode: logs the command that would have run instead.
# -----------------------------------------------------------------------
function Invoke-WingetInstall {
    param([Parameter(Mandatory)] [object]$App)

    # If the USB kit pre-downloaded a winget manifest, install from local path
    if ($App.localWingetManifest) {
        $manifestDir  = Get-ManifestDirectory
        $localManPath = Join-Path $manifestDir $App.localWingetManifest
        if (Test-Path $localManPath) {
            $wingetArgs = @(
                'install', '--manifest', $localManPath,
                '--architecture', 'x64', '--silent',
                '--accept-package-agreements', '--accept-source-agreements'
            )
            $cmdDisplay = "winget install --manifest `"$localManPath`" --architecture x64 --silent --accept-package-agreements --accept-source-agreements"
            if ($Script:DryRun) {
                Write-Log -Message "  [DRY RUN] Would run: $cmdDisplay" -Level DEBUG
                return
            }
            Write-Log -Message "  Running offline: $cmdDisplay" -Level DEBUG
            $output = & winget.exe @wingetArgs 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "winget exited with code $LASTEXITCODE -- $($output -join '; ')"
            }
            return
        }
    }

    # Use 'winget upgrade' for apps flagged as updates; 'install' for fresh installs
    $wingetAction = if ($Script:UpgradeIdSet.Contains($App.id)) { 'upgrade' } else { 'install' }

    $wingetArgs = @(
        $wingetAction,
        '--id', $App.wingetId,
        '--architecture', 'x64',
        '--silent',
        '--accept-package-agreements',
        '--accept-source-agreements'
    )

    $cmdDisplay = "winget $($wingetArgs -join ' ')"

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: $cmdDisplay" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: $cmdDisplay" -Level DEBUG

    $proc = Start-Process -FilePath 'winget.exe' `
                          -ArgumentList $wingetArgs `
                          -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -ne 0) {
        # If this was a 'winget upgrade' that failed (e.g. app not installed via winget),
        # fall back to 'winget install' which handles already-installed apps gracefully.
        if ($wingetAction -eq 'upgrade') {
            Write-Log -Message "  winget upgrade returned $($proc.ExitCode) -- falling back to winget install" -Level WARN
            $fallbackArgs = @(
                'install',
                '--id', $App.wingetId,
                '--architecture', 'x64',
                '--silent',
                '--accept-package-agreements',
                '--accept-source-agreements'
            )
            Write-Log -Message "  Running: winget $($fallbackArgs -join ' ')" -Level DEBUG
            $proc2 = Start-Process -FilePath 'winget.exe' `
                                   -ArgumentList $fallbackArgs `
                                   -Wait -PassThru -NoNewWindow
            if ($proc2.ExitCode -ne 0) {
                # Second fallback: drop --architecture in case the package
                # has no x64 variant (e.g. 32-bit-only apps like WinSCP)
                Write-Log -Message "  winget install (x64) returned $($proc2.ExitCode) -- retrying without --architecture" -Level WARN
                $fallback2Args = @(
                    'install',
                    '--id', $App.wingetId,
                    '--silent',
                    '--accept-package-agreements',
                    '--accept-source-agreements'
                )
                Write-Log -Message "  Running: winget $($fallback2Args -join ' ')" -Level DEBUG
                $proc3 = Start-Process -FilePath 'winget.exe' `
                                       -ArgumentList $fallback2Args `
                                       -Wait -PassThru -NoNewWindow
                if ($proc3.ExitCode -ne 0) {
                    throw "winget install (fallback2) exited with code $($proc3.ExitCode)"
                }
            }
        } else {
            throw "winget exited with code $($proc.ExitCode)"
        }
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-PSGalleryInstall
# Runs Install-Module with -Force and -AllowClobber.
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-PSGalleryInstall {
    param([Parameter(Mandatory)] [object]$App)

    $modName = $App.psGalleryModule

    # If the USB kit pre-downloaded the module, install from local directory copy
    if ($App.localModulePath) {
        $manifestDir   = Get-ManifestDirectory
        $localModBase  = Join-Path $manifestDir $App.localModulePath
        $localModDir   = Join-Path $localModBase $modName
        if (Test-Path $localModDir) {
            $destBase = ($env:PSModulePath -split ';')[0]
            if ($Script:DryRun) {
                Write-Log -Message "  [DRY RUN] Would copy $localModDir -> $destBase" -Level DEBUG
                return
            }
            Write-Log -Message "  Installing from local copy: $localModDir" -Level DEBUG
            Copy-Item -Path $localModDir -Destination (Join-Path $destBase $modName) -Recurse -Force
            return
        }
    }

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: Install-Module -Name $modName -Force -AllowClobber" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: Install-Module -Name $modName -Force -AllowClobber" -Level DEBUG
    Install-Module -Name $modName -Force -AllowClobber
}

# -----------------------------------------------------------------------
# Private: Invoke-DirectDownloadInstall
# Downloads the installer to a temp file, runs it with silentArgs,
# then removes the temp file.
# In DryRun mode: logs download URL and install command instead.
# -----------------------------------------------------------------------
function Invoke-DirectDownloadInstall {
    param([Parameter(Mandatory)] [object]$App)

    $url        = $App.directDownload.url
    $silentArgs = if ($App.silentArgs) { $App.silentArgs } else { '/S' }
    $urlLeaf    = [System.IO.Path]::GetFileName($url)

    # Check for locally-downloaded installer (USB kit offline mode)
    $localPath = $null
    if ($App.directDownload.localInstaller) {
        $manifestDir = Get-ManifestDirectory
        $candidate   = Join-Path $manifestDir $App.directDownload.localInstaller
        if (Test-Path $candidate) { $localPath = $candidate }
    }

    $installerFile = if ($localPath) { $localPath } else { Join-Path $env:TEMP "Loadout-$($App.id)-$urlLeaf" }

    if ($Script:DryRun) {
        if (-not $localPath) { Write-Log -Message "  [DRY RUN] Would download: $url" -Level DEBUG }
        Write-Log -Message "  [DRY RUN] Would run: $installerFile $silentArgs" -Level DEBUG
        return
    }

    if (-not $localPath) {
        Write-Log -Message "  Downloading: $url" -Level DEBUG
        Invoke-WebRequest -Uri $url -OutFile $installerFile -UseBasicParsing
    } else {
        Write-Log -Message "  Using local installer: $localPath" -Level DEBUG
    }

    Write-Log -Message "  Installing: $installerFile $silentArgs" -Level DEBUG
    $proc = Start-Process -FilePath $installerFile `
                          -ArgumentList $silentArgs `
                          -Wait -PassThru

    if (-not $localPath) {
        Remove-Item -Path $installerFile -Force -ErrorAction SilentlyContinue
    }

    if ($proc.ExitCode -ne 0) {
        throw "Installer exited with code $($proc.ExitCode)"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-ChocolateyInstall
# Installs an app via Chocolatey. Only called when $Script:AllowChocolatey
# is $true (set by the commit preview dialog confirmation).
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-ChocolateyInstall {
    param([Parameter(Mandatory)] [object]$App)

    $chocoId = $App.chocolateyId

    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        throw "choco.exe not found on PATH. Chocolatey may not be installed."
    }

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: choco install $chocoId -y --no-progress" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: choco install $chocoId -y --no-progress" -Level DEBUG
    & choco install $chocoId -y --no-progress 2>&1 | ForEach-Object {
        Write-Log -Message "  [choco] $_" -Level DEBUG
    }

    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 1641 -and $LASTEXITCODE -ne 3010) {
        throw "Chocolatey install exited with code $LASTEXITCODE"
    }

    if ($LASTEXITCODE -eq 1641 -or $LASTEXITCODE -eq 3010) {
        Write-Log -Message "  Chocolatey install succeeded; a reboot may be required." -Level WARN
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-WSLPostInstall
# Installs postInstallPackages into a WSL distro via the distro's package
# manager (apt, dnf, yum, pacman, or zypper) running as root.
# Called from Invoke-WSLInstall.
# In DryRun mode: logs the commands that would have run.
# -----------------------------------------------------------------------
function Invoke-WSLPostInstall {
    param([Parameter(Mandatory)] [object]$App)

    $distroName = $App.wslDistroName
    $pm         = [string]$App.packageManager
    $pkgs       = @($App.postInstallPackages)

    switch ($pm) {
        'apt' {
            $updateVerb  = @('apt-get', 'update', '-qq')
            $installVerb = @('apt-get', 'install', '-y')
        }
        'dnf' {
            $updateVerb  = @('dnf', 'makecache', '-q')
            $installVerb = @('dnf', 'install', '-y')
        }
        'yum' {
            $updateVerb  = @('yum', 'makecache', '-q')
            $installVerb = @('yum', 'install', '-y')
        }
        'pacman' {
            $updateVerb  = @('pacman', '-Sy', '--noconfirm')
            $installVerb = @('pacman', '-S', '--noconfirm')
        }
        'zypper' {
            $updateVerb  = @('zypper', '--non-interactive', 'refresh')
            $installVerb = @('zypper', '--non-interactive', 'install')
        }
        default {
            throw "Unsupported WSL packageManager '$pm' for app '$($App.id)'."
        }
    }

    $updateArgs  = @('-d', $distroName, '-u', 'root', '--') + $updateVerb
    $installArgs = @('-d', $distroName, '-u', 'root', '--') + $installVerb + $pkgs

    $updateDisplay  = "wsl $($updateArgs  -join ' ')"
    $installDisplay = "wsl $($installArgs -join ' ')"

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: $updateDisplay"  -Level DEBUG
        Write-Log -Message "  [DRY RUN] Would run: $installDisplay" -Level DEBUG
        return
    }

    Write-Log -Message "[$($App.displayName)] Installing post-install packages via $pm..." -Level INFO

    Write-Log -Message "  Running: $updateDisplay" -Level DEBUG
    $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList $updateArgs -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        throw "$pm update exited with code $($proc.ExitCode)"
    }

    Write-Log -Message "  Running: $installDisplay" -Level DEBUG
    $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList $installArgs -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        throw "$pm install exited with code $($proc.ExitCode)"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-WSLInstall
# Installs a WSL 2 distro via 'wsl --install -d <DistroName> --no-launch'
# then installs postInstallPackages as root inside the distro.
# In DryRun mode: logs the commands that would have run.
# -----------------------------------------------------------------------
function Invoke-WSLInstall {
    param([Parameter(Mandatory)] [object]$App)

    $distroName = $App.wslDistroName

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: wsl --set-default-version 2" -Level DEBUG
        Write-Log -Message "  [DRY RUN] Would run: wsl --install -d $distroName --no-launch" -Level DEBUG
        if ($App.postInstallPackages -and $App.postInstallPackages.Count -gt 0) {
            Invoke-WSLPostInstall -App $App
        }
        return
    }

    # Ensure WSL 2 is the default version before installing
    Write-Log -Message "  Running: wsl --set-default-version 2" -Level DEBUG
    $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList '--set-default-version', '2' -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        Write-Log -Message "  wsl --set-default-version 2 exited with code $($proc.ExitCode) -- continuing" -Level WARN
    }

    # Install the distro without launching it interactively
    Write-Log -Message "  Running: wsl --install -d $distroName --no-launch" -Level DEBUG
    $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList '--install', '-d', $distroName, '--no-launch' -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        throw "wsl --install -d $distroName exited with code $($proc.ExitCode)"
    }

    # Install post-install packages inside the distro as root
    if ($App.postInstallPackages -and $App.postInstallPackages.Count -gt 0) {
        Invoke-WSLPostInstall -App $App
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-WSLUninstall
# Unregisters a WSL distro via 'wsl --unregister <DistroName>'.
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-WSLUninstall {
    param([Parameter(Mandatory)] [object]$App)

    $distroName = $App.wslDistroName

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: wsl --unregister $distroName" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: wsl --unregister $distroName" -Level DEBUG
    $proc = Start-Process -FilePath 'wsl.exe' -ArgumentList '--unregister', $distroName -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -ne 0) {
        throw "wsl --unregister $distroName exited with code $($proc.ExitCode)"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-WindowsFeatureInstall
# Enables a Windows Feature or Capability using the method specified in
# windowsFeatureMethod: Enable-WindowsOptionalFeature or Add-WindowsCapability.
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-WindowsFeatureInstall {
    param([Parameter(Mandatory)] [object]$App)

    $featureMethod = $App.windowsFeatureMethod
    $featureName   = $App.windowsFeatureName

    if ($featureMethod -eq 'Enable-WindowsOptionalFeature') {
        $cmd = "Enable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart"
        if ($Script:DryRun) {
            Write-Log -Message "  [DRY RUN] Would run: $cmd" -Level DEBUG
            return
        }
        Write-Log -Message "  Running: $cmd" -Level DEBUG
        Enable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart | Out-Null
    }
    elseif ($featureMethod -eq 'Add-WindowsCapability') {
        $cmd = "Add-WindowsCapability -Online -Name $featureName"
        if ($Script:DryRun) {
            Write-Log -Message "  [DRY RUN] Would run: $cmd" -Level DEBUG
            return
        }
        Write-Log -Message "  Running: $cmd" -Level DEBUG
        Add-WindowsCapability -Online -Name $featureName | Out-Null
    }
    else {
        throw "Unknown windowsFeatureMethod '$featureMethod'"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-WindowsFeatureUninstall
# Disables a Windows Feature or Capability using the inverse of the
# install method: Disable-WindowsOptionalFeature or Remove-WindowsCapability.
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-WindowsFeatureUninstall {
    param([Parameter(Mandatory)] [object]$App)

    $featureMethod = $App.windowsFeatureMethod
    $featureName   = $App.windowsFeatureName

    if ($featureMethod -eq 'Enable-WindowsOptionalFeature') {
        $cmd = "Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart"
        if ($Script:DryRun) {
            Write-Log -Message "  [DRY RUN] Would run: $cmd" -Level DEBUG
            return
        }
        Write-Log -Message "  Running: $cmd" -Level DEBUG
        Disable-WindowsOptionalFeature -Online -FeatureName $featureName -NoRestart | Out-Null
    }
    elseif ($featureMethod -eq 'Add-WindowsCapability') {
        $cmd = "Remove-WindowsCapability -Online -Name $featureName"
        if ($Script:DryRun) {
            Write-Log -Message "  [DRY RUN] Would run: $cmd" -Level DEBUG
            return
        }
        Write-Log -Message "  Running: $cmd" -Level DEBUG
        Remove-WindowsCapability -Online -Name $featureName | Out-Null
    }
    else {
        throw "Unknown windowsFeatureMethod '$featureMethod'"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-RegistryInstall
# Writes a registry value and creates the key if it does not exist.
# New-ItemProperty is used when creating a value so registryType is
# honored; Set-ItemProperty updates existing values.
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-RegistryInstall {
    param([Parameter(Mandatory)] [object]$App)

    $regPath  = $App.registryPath
    $regName  = $App.registryName
    $regValue = $App.registryValue
    $regType  = $App.registryType

    $cmd = "Set/New-ItemProperty -Path '$regPath' -Name '$regName' -Value $regValue -PropertyType $regType"

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: $cmd" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: $cmd" -Level DEBUG

    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }
    $existing = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        Set-ItemProperty -Path $regPath -Name $regName -Value $regValue
    } else {
        New-ItemProperty -Path $regPath -Name $regName -Value $regValue -PropertyType $regType -Force | Out-Null
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-VSCodeExtensionInstall
# Installs a VS Code extension via the 'code' CLI.
# Requires VS Code installed and 'code' on the PATH (winget installs it).
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-VSCodeExtensionInstall {
    param([Parameter(Mandatory)] [object]$App)

    $extId = $App.vscodeExtensionId
    $cmd   = "code --install-extension $extId"

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: $cmd" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: $cmd" -Level DEBUG
    $output = & code --install-extension $extId 2>&1
    Write-Log -Message "  code: $output" -Level DEBUG
    if ($LASTEXITCODE -ne 0) {
        throw "code install-extension exited with code $LASTEXITCODE -- $($output -join '; ')"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-VSCodeExtensionUninstall
# Uninstalls a VS Code extension via the 'code' CLI.
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-VSCodeExtensionUninstall {
    param([Parameter(Mandatory)] [object]$App)

    $extId = $App.vscodeExtensionId
    $cmd   = "code --uninstall-extension $extId"

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: $cmd" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: $cmd" -Level DEBUG
    $output = & code --uninstall-extension $extId 2>&1
    Write-Log -Message "  code: $output" -Level DEBUG
    if ($LASTEXITCODE -ne 0) {
        throw "code uninstall-extension exited with code $LASTEXITCODE -- $($output -join '; ')"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-WingetUninstall
# Runs winget uninstall with silent flags.
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-WingetUninstall {
    param([Parameter(Mandatory)] [object]$App)

    $wingetArgs = @(
        'uninstall',
        '--id', $App.wingetId,
        '--silent',
        '--accept-source-agreements'
    )

    $cmdDisplay = "winget $($wingetArgs -join ' ')"

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: $cmdDisplay" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: $cmdDisplay" -Level DEBUG

    $proc = Start-Process -FilePath 'winget.exe' `
                          -ArgumentList $wingetArgs `
                          -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -ne 0) {
        throw "winget uninstall exited with code $($proc.ExitCode)"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-PSGalleryUninstall
# Removes all installed versions of the module via Uninstall-Module.
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-PSGalleryUninstall {
    param([Parameter(Mandatory)] [object]$App)

    $modName = $App.psGalleryModule

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: Uninstall-Module -Name $modName -AllVersions -Force" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: Uninstall-Module -Name $modName -AllVersions -Force" -Level DEBUG
    Uninstall-Module -Name $modName -AllVersions -Force
}

# -----------------------------------------------------------------------
# Private: Invoke-DirectDownloadUninstall
# Reads the UninstallString (or QuietUninstallString) from the HKLM
# Uninstall registry key for the app and executes it.
# In DryRun mode: skips the registry lookup and logs what would run.
# -----------------------------------------------------------------------
function Invoke-DirectDownloadUninstall {
    param([Parameter(Mandatory)] [object]$App)

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would read UninstallString from registry for '$($App.displayName)' and execute it" -Level DEBUG
        return
    }

    $searchName = $App.displayName
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $uninstallString = $null
    foreach ($regPath in $regPaths) {
        $entry = Get-ItemProperty $regPath -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "*$searchName*" } |
                 Select-Object -First 1

        if ($entry) {
            # Prefer QuietUninstallString; it already includes silent flags
            $uninstallString = if ($entry.QuietUninstallString) {
                $entry.QuietUninstallString
            } else {
                $entry.UninstallString
            }
            break
        }
    }

    if (-not $uninstallString) {
        throw "No registry uninstall entry found matching display name '$searchName'"
    }

    Write-Log -Message "  Running: $uninstallString" -Level DEBUG

    # Parse into executable + args
    if ($uninstallString -match '^"([^"]+)"(.*)$') {
        $exe     = $matches[1]
        $exeArgs = $matches[2].Trim()
    } else {
        $parts   = $uninstallString -split '\s+', 2
        $exe     = $parts[0]
        $exeArgs = if ($parts.Length -gt 1) { $parts[1] } else { '' }
    }

    $procParams = @{ FilePath = $exe; Wait = $true; PassThru = $true }
    if ($exeArgs) { $procParams.ArgumentList = $exeArgs }

    $proc = Start-Process @procParams
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        throw "Uninstaller exited with code $($proc.ExitCode)"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-ChocolateyUninstall
# Uninstalls via choco uninstall. Throws if choco.exe is absent.
# In DryRun mode: logs the command that would have run.
# -----------------------------------------------------------------------
function Invoke-ChocolateyUninstall {
    param([Parameter(Mandatory)] [object]$App)

    $chocoId = $App.chocolateyId

    if (-not (Get-Command choco.exe -ErrorAction SilentlyContinue)) {
        throw "choco.exe not found on PATH. Chocolatey may not be installed."
    }

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: choco uninstall $chocoId -y" -Level DEBUG
        return
    }

    Write-Log -Message "  Running: choco uninstall $chocoId -y" -Level DEBUG
    & choco uninstall $chocoId -y 2>&1 | ForEach-Object {
        Write-Log -Message "  [choco] $_" -Level DEBUG
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Chocolatey uninstall exited with code $LASTEXITCODE"
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-SingleAppUninstall
# Uninstalls one app using its primary install method. Records result in
# $Script:UninstallResults. Methods not yet supported (WSL, Windows
# Features, etc.) are skipped with a warning.
# -----------------------------------------------------------------------
function Invoke-SingleAppUninstall {
    param([Parameter(Mandatory)] [object]$App)

    $id     = $App.id
    $name   = $App.displayName
    $method = Get-InstallMethod -App $App

    $Script:ProgressIndex++
    if ($null -ne $Script:OnItemStart) {
        & $Script:OnItemStart $Script:ProgressIndex $Script:ProgressTotal $name
    }

    $uninstallable = @('Winget', 'PSGallery', 'DirectDownload', 'Chocolatey', 'WSL', 'WindowsFeature', 'VSCodeExtension')
    if ($uninstallable -notcontains $method) {
        Write-Log -Message "[$name] Uninstall of '$method' apps not yet supported -- skipping" -Level WARN
        $Script:UninstallResults[$id] = 'Skipped'
        if ($null -ne $Script:OnItemDone) { & $Script:OnItemDone $Script:ProgressIndex $Script:ProgressTotal 'Skipped' }
        return
    }

    Write-Log -Message "[$name] Uninstalling via $method..." -Level INFO

    try {
        switch ($method) {
            'Winget'          { Invoke-WingetUninstall          -App $App }
            'PSGallery'       { Invoke-PSGalleryUninstall       -App $App }
            'DirectDownload'  { Invoke-DirectDownloadUninstall  -App $App }
            'Chocolatey'      { Invoke-ChocolateyUninstall      -App $App }
            'WSL'              { Invoke-WSLUninstall              -App $App }
            'WindowsFeature'   { Invoke-WindowsFeatureUninstall   -App $App }
            'VSCodeExtension'  { Invoke-VSCodeExtensionUninstall  -App $App }
        }

        Write-Log -Message "[$name] Uninstalled OK" -Level OK
        $Script:UninstallResults[$id] = 'Success'
        if ($null -ne $Script:OnItemDone) { & $Script:OnItemDone $Script:ProgressIndex $Script:ProgressTotal 'Success' }
    }
    catch {
        Write-Log -Message "[$name] Uninstall FAILED -- $($_.Exception.Message)" -Level ERROR
        $Script:UninstallResults[$id] = 'Failed'
        if ($null -ne $Script:OnItemDone) { & $Script:OnItemDone $Script:ProgressIndex $Script:ProgressTotal 'Failed' }
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-AppPostInstall
# Runs postInstallCommands for a single app.
# Commands are executed via scriptblocks after a lightweight unsafe-pattern check.
# In DryRun mode: logs commands that would have run.
# -----------------------------------------------------------------------
function Invoke-AppPostInstall {
    param([Parameter(Mandatory)] [object]$App)

    if (-not $App.postInstallCommands -or $App.postInstallCommands.Count -eq 0) {
        return
    }

    Write-Log -Message "[$($App.displayName)] Running post-install commands..." -Level INFO

    $unsafePattern = '(?i)(Invoke-Expression|\biex\b|Invoke-RestMethod\s+[^|]*\|\s*(Invoke-Expression|\biex\b)|Invoke-WebRequest\s+[^|]*\|\s*(Invoke-Expression|\biex\b)|DownloadString\s*\()'
    $hadFailure = $false

    foreach ($cmd in $App.postInstallCommands) {
        if ([string]::IsNullOrWhiteSpace([string]$cmd)) {
            Write-Log -Message "[$($App.displayName)] Skipping empty post-install command." -Level WARN
            $hadFailure = $true
            continue
        }

        if ([regex]::IsMatch([string]$cmd, $unsafePattern)) {
            Write-Log -Message "[$($App.displayName)] Blocked risky post-install command: $cmd" -Level ERROR
            $hadFailure = $true
            continue
        }

        if ($Script:DryRun) {
            Write-Log -Message "  [DRY RUN] Would run: $cmd" -Level DEBUG
        }
        else {
            Write-Log -Message "  Running: $cmd" -Level DEBUG
            try {
                & ([scriptblock]::Create([string]$cmd))
            } catch {
                Write-Log -Message "[$($App.displayName)] Post-install command failed: $($_.Exception.Message)" -Level ERROR
                $hadFailure = $true
            }
        }
    }

    if ($hadFailure) {
        $Script:InstallResults[$App.id] = 'Failed'
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-SingleApp
# Installs one app using its primary install method. Records result in
# $Script:InstallResults. If the app is a prerequisite and fails, adds
# its ID to $Script:FailedPrereqIds so dependents can be skipped.
# -----------------------------------------------------------------------
function Invoke-SingleApp {
    param(
        [Parameter(Mandatory)] [object]$App
    )

    $id     = $App.id
    $name   = $App.displayName
    $method = Get-InstallMethod -App $App

    # Increment index and fire OnItemStart callback
    $Script:ProgressIndex++
    if ($null -ne $Script:OnItemStart) {
        & $Script:OnItemStart $Script:ProgressIndex $Script:ProgressTotal $name
    }

    # PostInstallOnly apps have no install step -- mark Success now so Phase 6 runs their commands
    if ($method -eq 'PostInstallOnly') {
        Write-Log -Message "[$name] No installation required -- post-install commands will run in Phase 6" -Level INFO
        $Script:InstallResults[$id] = 'Success'
        if ($null -ne $Script:OnItemDone) { & $Script:OnItemDone $Script:ProgressIndex $Script:ProgressTotal 'Success' }
        return
    }

    if ($method -eq 'Unknown') {
        Write-Log -Message "[$name] No install method found in manifest entry -- skipping" -Level WARN
        $Script:InstallResults[$id] = 'Skipped'
        if ($null -ne $Script:OnItemDone) { & $Script:OnItemDone $Script:ProgressIndex $Script:ProgressTotal 'Skipped' }
        return
    }

    # Check that all dependencies succeeded before proceeding
    if (-not (Test-DependenciesMet -App $App)) {
        $Script:InstallResults[$id] = 'Skipped'
        if ($App.isPrerequisite) {
            [void]$Script:FailedPrereqIds.Add($id)
        }
        if ($null -ne $Script:OnItemDone) { & $Script:OnItemDone $Script:ProgressIndex $Script:ProgressTotal 'Skipped' }
        return
    }

    Write-Log -Message "[$name] Installing via $method..." -Level INFO

    try {
        switch ($method) {
            'Winget'          { Invoke-WingetInstall          -App $App }
            'PSGallery'       { Invoke-PSGalleryInstall       -App $App }
            'DirectDownload'  { Invoke-DirectDownloadInstall  -App $App }
            'WSL'             { Invoke-WSLInstall             -App $App }
            'WindowsFeature'   { Invoke-WindowsFeatureInstall   -App $App }
            'Registry'         { Invoke-RegistryInstall         -App $App }
            'VSCodeExtension'  { Invoke-VSCodeExtensionInstall  -App $App }
            'Chocolatey'     {
                if (-not $Script:AllowChocolatey) {
                    Write-Log -Message "[$name] Chocolatey install not confirmed -- skipping" -Level WARN
                    $Script:InstallResults[$id] = 'Skipped'
                    if ($App.isPrerequisite) {
                        [void]$Script:FailedPrereqIds.Add($id)
                        Write-Log -Message "  Prerequisite skipped: apps depending on '$id' will be skipped" -Level WARN
                    }
                    if ($null -ne $Script:OnItemDone) { & $Script:OnItemDone $Script:ProgressIndex $Script:ProgressTotal 'Skipped' }
                    return
                }
                Invoke-ChocolateyInstall -App $App
            }
        }

        Write-Log -Message "[$name] OK" -Level OK
        $Script:InstallResults[$id] = 'Success'
        if ($null -ne $Script:OnItemDone) { & $Script:OnItemDone $Script:ProgressIndex $Script:ProgressTotal 'Success' }
    }
    catch {
        Write-Log -Message "[$name] FAILED -- $($_.Exception.Message)" -Level ERROR
        $Script:InstallResults[$id] = 'Failed'

        if ($App.isPrerequisite) {
            [void]$Script:FailedPrereqIds.Add($id)
            Write-Log -Message "  Prerequisite failure: apps depending on '$id' will be skipped" -Level WARN
        }
        if ($null -ne $Script:OnItemDone) { & $Script:OnItemDone $Script:ProgressIndex $Script:ProgressTotal 'Failed' }
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-PhasePrerequisites
# Phase 1 -- silent installs for all isPrerequisite:true apps.
# -----------------------------------------------------------------------
function Invoke-PhasePrerequisites {
    param([object[]]$Apps)

    if (-not $Apps -or $Apps.Count -eq 0) { return }

    Write-Log -Message '--- Phase 1: Prerequisites ---' -Level INFO
    Write-Log -Message 'Preparing prerequisites...' -Level INFO

    foreach ($app in $Apps) {
        Invoke-SingleApp -App $app
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-PhaseStandard
# Phase 2 -- winget and PSGallery installs for non-prerequisite apps.
# -----------------------------------------------------------------------
function Invoke-PhaseStandard {
    param([object[]]$Apps)

    if (-not $Apps -or $Apps.Count -eq 0) { return }

    Write-Log -Message '--- Phase 2: Standard Installs (winget / PSGallery) ---' -Level INFO

    foreach ($app in $Apps) {
        Invoke-SingleApp -App $app
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-PhaseDirect
# Phase 3 -- direct download installs for non-prerequisite apps.
# -----------------------------------------------------------------------
function Invoke-PhaseDirect {
    param([object[]]$Apps)

    if (-not $Apps -or $Apps.Count -eq 0) { return }

    Write-Log -Message '--- Phase 3: Direct Downloads ---' -Level INFO

    foreach ($app in $Apps) {
        Invoke-SingleApp -App $app
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-PhasePostInstall
# Phase 7 -- runs postInstallCommands for every app that succeeded.
# Also runs for DryRun (commands are logged, not executed).
# -----------------------------------------------------------------------
function Invoke-PhasePostInstall {
    param([object[]]$Apps)

    $withCommands = @($Apps | Where-Object {
        $_.postInstallCommands -and $_.postInstallCommands.Count -gt 0 `
        -and $Script:InstallResults[$_.id] -eq 'Success'
    })

    if ($withCommands.Count -eq 0) { return }

    Write-Log -Message '--- Phase 7: Post-Install ---' -Level INFO

    foreach ($app in $withCommands) {
        Invoke-AppPostInstall -App $app
    }
}

# -----------------------------------------------------------------------
# Public: Invoke-InstallPlan
# Main entry point for the install engine. Accepts an array of app
# objects (typically produced by ManifestManager.Resolve-InstallPlan)
# and installs them in phase order.
#
# Returns a hashtable of id -> result string for reporting.
# -----------------------------------------------------------------------
function Invoke-InstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Apps,

        # Optional progress callbacks -- called by Invoke-SingleApp for every app processed.
        # OnItemStart: invoked before install begins  -- args ($index, $total, $displayName)
        # OnItemDone:  invoked after install completes -- args ($index, $total, $result)
        [scriptblock]$OnItemStart = $null,
        [scriptblock]$OnItemDone  = $null,

        # Set $true when the user has confirmed the commit preview dialog for a plan
        # that contains Chocolatey apps. Defaults to $false to keep the gate closed.
        [bool]$AllowChocolatey = $false
    )

    # Reset per-run state
    $Script:InstallResults  = @{}
    $Script:FailedPrereqIds = [System.Collections.Generic.HashSet[string]]::new()
    $Script:OnItemStart     = $OnItemStart
    $Script:OnItemDone      = $OnItemDone
    $Script:ProgressIndex   = 0
    $Script:ProgressTotal   = $Apps.Count
    $Script:AllowChocolatey = $AllowChocolatey

    $modeLabel = if ($Script:DryRun) { ' (DRY RUN)' } else { '' }
    Write-Log -Message "Install plan: $($Apps.Count) app(s) to process$modeLabel" -Level INFO

    # Partition apps into phases by install method
    $prereqs  = @($Apps | Where-Object { $_.isPrerequisite -eq $true })

    $standard = @($Apps | Where-Object {
        -not $_.isPrerequisite `
        -and (Get-InstallMethod -App $_) -in @('Winget', 'PSGallery', 'Chocolatey')
    })

    $direct   = @($Apps | Where-Object {
        -not $_.isPrerequisite `
        -and (Get-InstallMethod -App $_) -eq 'DirectDownload'
    })

    # WSL distros go to Phase 4
    $wsl      = @($Apps | Where-Object {
        -not $_.isPrerequisite `
        -and (Get-InstallMethod -App $_) -eq 'WSL'
    })

    # Phase 5: Windows Features, Registry settings, PostInstallOnly (powercfg-style commands)
    $features = @($Apps | Where-Object {
        -not $_.isPrerequisite `
        -and (Get-InstallMethod -App $_) -in @('WindowsFeature', 'Registry', 'PostInstallOnly')
    })

    # Phase 6: VS Code Extensions (requires VS Code from Phase 2)
    $vscodeExts = @($Apps | Where-Object {
        -not $_.isPrerequisite `
        -and (Get-InstallMethod -App $_) -eq 'VSCodeExtension'
    })

    # Phase 1: Prerequisites
    Invoke-PhasePrerequisites -Apps $prereqs

    # Phase 2: Standard (winget + PSGallery)
    Invoke-PhaseStandard -Apps $standard

    # Phase 3: Direct downloads
    Invoke-PhaseDirect -Apps $direct

    # Phase 4: WSL distros
    if ($wsl.Count -gt 0) {
        Write-Log -Message '--- Phase 4: WSL Distros ---' -Level INFO
        foreach ($app in $wsl) {
            Invoke-SingleApp -App $app
        }
    }

    # Phase 5: Windows Features, Registry Settings, PostInstallOnly
    if ($features.Count -gt 0) {
        Write-Log -Message '--- Phase 5: Windows Features and Settings ---' -Level INFO
        foreach ($app in $features) {
            Invoke-SingleApp -App $app
        }
    }

    # Phase 6: VS Code Extensions
    if ($vscodeExts.Count -gt 0) {
        Write-Log -Message '--- Phase 6: VS Code Extensions ---' -Level INFO
        foreach ($app in $vscodeExts) {
            Invoke-SingleApp -App $app
        }
    }

    # Phase 7: Post-install commands
    Invoke-PhasePostInstall -Apps $Apps

    # Summary
    $succeeded = @($Script:InstallResults.Keys | Where-Object { $Script:InstallResults[$_] -eq 'Success' }).Count
    $failed    = @($Script:InstallResults.Keys | Where-Object { $Script:InstallResults[$_] -eq 'Failed' }).Count
    $skipped   = @($Script:InstallResults.Keys | Where-Object { $Script:InstallResults[$_] -eq 'Skipped' }).Count

    Write-Log -Message "Install complete -- OK: $succeeded  Failed: $failed  Skipped: $skipped" -Level INFO

    return $Script:InstallResults
}

# -----------------------------------------------------------------------
# Public: Get-InstallResults
# Returns the results hashtable from the most recent Invoke-InstallPlan.
# -----------------------------------------------------------------------
function Get-InstallResults {
    return $Script:InstallResults
}

# -----------------------------------------------------------------------
# Public: Invoke-UninstallPlan
# Removes an array of app objects. Each app is processed via its primary
# install method's corresponding uninstall routine. Methods not yet
# supported (Registry, PostInstallOnly) are skipped with a warning.
#
# Returns a hashtable of id -> result string for reporting.
# -----------------------------------------------------------------------
function Invoke-UninstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Apps,

        [scriptblock]$OnItemStart = $null,
        [scriptblock]$OnItemDone  = $null
    )

    $Script:UninstallResults = @{}
    $Script:OnItemStart      = $OnItemStart
    $Script:OnItemDone       = $OnItemDone
    $Script:ProgressIndex    = 0
    $Script:ProgressTotal    = $Apps.Count

    $modeLabel = if ($Script:DryRun) { ' (DRY RUN)' } else { '' }
    Write-Log -Message "Uninstall plan: $($Apps.Count) app(s) to remove$modeLabel" -Level INFO

    foreach ($app in $Apps) {
        Invoke-SingleAppUninstall -App $app
    }

    $succeeded = @($Script:UninstallResults.Keys | Where-Object { $Script:UninstallResults[$_] -eq 'Success' }).Count
    $failed    = @($Script:UninstallResults.Keys | Where-Object { $Script:UninstallResults[$_] -eq 'Failed' }).Count
    $skipped   = @($Script:UninstallResults.Keys | Where-Object { $Script:UninstallResults[$_] -eq 'Skipped' }).Count

    Write-Log -Message "Uninstall complete -- OK: $succeeded  Failed: $failed  Skipped: $skipped" -Level INFO

    return $Script:UninstallResults
}

# -----------------------------------------------------------------------
# Public: Get-UninstallResults
# Returns the results hashtable from the most recent Invoke-UninstallPlan.
# -----------------------------------------------------------------------
function Get-UninstallResults {
    return $Script:UninstallResults
}

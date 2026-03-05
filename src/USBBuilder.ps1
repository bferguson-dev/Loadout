# USBBuilder.ps1 -- Builds a self-contained offline USB kit from selected apps.
# Downloads installers, PSGallery modules, and winget packages to a destination
# folder, generates a manifest-local.json with local file paths, copies Loadout
# source files, and writes README.txt so the kit runs fully offline.
#
# Public:
#   Invoke-USBBuild -Apps <object[]> -Destination <string> [-OnItemStart] [-OnItemDone]
#   Get-USBBuildResults
#
# Dot-sourced by Loadout.ps1 alongside Logger, ManifestManager, and InstallEngine.
# ASCII-only file -- see Coding Standards in DESIGN.md.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns','')]
param()

$ErrorActionPreference = 'Stop'

# id -> 'Success' | 'WingetOnly' | 'Skipped' | 'Failed'
$Script:USBBuildResults = @{}

# -----------------------------------------------------------------------
# Private: Get-USBMethod
# Returns the download method for USB packaging purposes.
# Priority matches Get-InstallMethod in InstallEngine except WSL, Windows
# Features, Registry, PostInstallOnly, and Chocolatey are non-downloadable.
# -----------------------------------------------------------------------
function Get-USBMethod {
    param([Parameter(Mandatory)] [object]$App)

    if ($App.wingetId)             { return 'Winget' }
    if ($App.psGalleryModule)      { return 'PSGallery' }
    if ($App.directDownload)       { return 'DirectDownload' }
    if ($App.vscodeExtensionId)    { return 'VSCodeExtension' }
    if ($App.wslDistroName)        { return 'WSL' }
    if ($App.windowsFeatureMethod) { return 'WindowsFeature' }
    if ($App.registryPath)         { return 'Registry' }
    if ($App.chocolateyId)         { return 'Chocolatey' }
    return 'Unknown'
}

# -----------------------------------------------------------------------
# Private: Invoke-WingetDownload
# Runs winget download --id <ID> into a subdirectory of $WingetPath.
# Returns the relative path string (e.g. "winget/<id>") on success, or
# $null if winget download is unavailable or fails.
# -----------------------------------------------------------------------
function Invoke-WingetDownload {
    param(
        [Parameter(Mandatory)] [object]$App,
        [Parameter(Mandatory)] [string]$WingetPath
    )

    $subDir  = Join-Path $WingetPath $App.wingetId
    $relPath = "winget/$($App.wingetId)"

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: winget download --id $($App.wingetId) -d $subDir" -Level DEBUG
        return $relPath
    }

    New-Item -ItemType Directory -Path $subDir -Force | Out-Null

    $proc = Start-Process -FilePath 'winget.exe' `
                -ArgumentList @('download', '--id', $App.wingetId,
                                '--architecture', 'x64',
                                '--accept-package-agreements', '--accept-source-agreements',
                                '--download-directory', $subDir) `
                -Wait -PassThru -NoNewWindow

    if ($proc.ExitCode -eq 0) { return $relPath }

    Write-Log -Message "  winget download exited $($proc.ExitCode) for $($App.id) -- will install online." -Level WARN
    return $null
}

# -----------------------------------------------------------------------
# Private: Invoke-PSGalleryDownload
# Saves a PSGallery module to $ModulesPath using Save-Module.
# Returns $true on success.
# -----------------------------------------------------------------------
function Invoke-PSGalleryDownload {
    param(
        [Parameter(Mandatory)] [object]$App,
        [Parameter(Mandatory)] [string]$ModulesPath
    )

    $modName = $App.psGalleryModule

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: Save-Module -Name $modName -Path $ModulesPath" -Level DEBUG
        return $true
    }

    Save-Module -Name $modName -Path $ModulesPath -Force
    return $true
}

# -----------------------------------------------------------------------
# Private: Invoke-DirectDownloadUSB
# Downloads the installer file to $InstallersPath.
# Returns the filename on success, or throws on failure.
# -----------------------------------------------------------------------
function Invoke-DirectDownloadUSB {
    param(
        [Parameter(Mandatory)] [object]$App,
        [Parameter(Mandatory)] [string]$InstallersPath
    )

    $url     = $App.directDownload.url
    $urlLeaf = [System.IO.Path]::GetFileName($url)
    if (-not $urlLeaf) { $urlLeaf = "$($App.id).exe" }
    $outPath = Join-Path $InstallersPath $urlLeaf

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would download: $url -> $outPath" -Level DEBUG
        return $urlLeaf
    }

    Write-Log -Message "  Downloading: $url" -Level DEBUG
    Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing
    return $urlLeaf
}

# -----------------------------------------------------------------------
# Private: Invoke-USBDownloadSingle
# Downloads one app's installer using the appropriate method.
# Returns a hashtable: { Status: string, LocalPath: string or $null }
#   Status values: 'Success', 'WingetOnly', 'Skipped', 'Failed'
#   LocalPath: relative path from the USB root (e.g. "installers/foo.exe")
# -----------------------------------------------------------------------
function Invoke-USBDownloadSingle {
    param(
        [Parameter(Mandatory)] [object]$App,
        [Parameter(Mandatory)] [string]$InstallersPath,
        [Parameter(Mandatory)] [string]$WingetPath,
        [Parameter(Mandatory)] [string]$ModulesPath
    )

    # Skip apps explicitly excluded from USB kit
    if ($App.includeInUSBKit -eq $false) {
        Write-Log -Message "  $($App.id): excluded (includeInUSBKit=false) -- skipped." -Level DEBUG
        return @{ Status = 'Skipped'; LocalPath = $null }
    }

    $method = Get-USBMethod -App $App

    switch ($method) {
        'Winget' {
            try {
                $relPath = Invoke-WingetDownload -App $App -WingetPath $WingetPath
                if ($relPath) {
                    return @{ Status = 'Success'; LocalPath = "installers/$relPath" }
                }
                return @{ Status = 'WingetOnly'; LocalPath = $null }
            } catch {
                Write-Log -Message "  $($App.id): winget download error: $_" -Level WARN
                return @{ Status = 'WingetOnly'; LocalPath = $null }
            }
        }
        'PSGallery' {
            try {
                Invoke-PSGalleryDownload -App $App -ModulesPath $ModulesPath | Out-Null
                return @{ Status = 'Success'; LocalPath = 'installers/modules' }
            } catch {
                Write-Log -Message "  $($App.id): Save-Module failed: $_" -Level WARN
                return @{ Status = 'Failed'; LocalPath = $null }
            }
        }
        'DirectDownload' {
            try {
                $fileName = Invoke-DirectDownloadUSB -App $App -InstallersPath $InstallersPath
                return @{ Status = 'Success'; LocalPath = "installers/$fileName" }
            } catch {
                Write-Log -Message "  $($App.id): download failed: $_" -Level WARN
                return @{ Status = 'Failed'; LocalPath = $null }
            }
        }
        'VSCodeExtension' {
            Write-Log -Message "  $($App.id): VS Code extensions require marketplace access -- skipped." -Level WARN
            return @{ Status = 'Skipped'; LocalPath = $null }
        }
        { $_ -in 'WSL', 'WindowsFeature', 'Registry' } {
            Write-Log -Message "  $($App.id): $method not applicable for USB kit -- skipped." -Level DEBUG
            return @{ Status = 'Skipped'; LocalPath = $null }
        }
        'Chocolatey' {
            Write-Log -Message "  $($App.id): Chocolatey apps not pre-downloaded -- skipped." -Level WARN
            return @{ Status = 'Skipped'; LocalPath = $null }
        }
        default {
            Write-Log -Message "  $($App.id): no USB download method -- skipped." -Level WARN
            return @{ Status = 'Skipped'; LocalPath = $null }
        }
    }
}

# -----------------------------------------------------------------------
# Private: New-LocalManifest
# Deep-copies the original manifest JSON, injects local file paths for
# apps that were successfully downloaded, and writes manifest-local.json.
# Fields added per method:
#   DirectDownload -> app.directDownload.localInstaller = "installers/file.exe"
#   PSGallery      -> app.localModulePath = "installers/modules"
#   Winget         -> app.localWingetManifest = "installers/winget/<id>"
# -----------------------------------------------------------------------
function New-LocalManifest {
    param(
        [Parameter(Mandatory)] [string]$OriginalManifestPath,
        [Parameter(Mandatory)] [hashtable]$DownloadResults,
        [Parameter(Mandatory)] [string]$OutputPath
    )

    $raw  = Get-Content $OriginalManifestPath -Raw -Encoding UTF8
    $data = $raw | ConvertFrom-Json

    foreach ($app in $data.apps) {
        $id = $app.id
        if (-not $DownloadResults.ContainsKey($id)) { continue }

        $res = $DownloadResults[$id]
        if ($res.Status -ne 'Success' -or -not $res.LocalPath) { continue }

        $method = Get-USBMethod -App $app
        switch ($method) {
            'DirectDownload' {
                $app.directDownload | Add-Member -NotePropertyName 'localInstaller' `
                    -NotePropertyValue $res.LocalPath -Force
            }
            'PSGallery' {
                $app | Add-Member -NotePropertyName 'localModulePath' `
                    -NotePropertyValue $res.LocalPath -Force
            }
            'Winget' {
                $app | Add-Member -NotePropertyName 'localWingetManifest' `
                    -NotePropertyValue $res.LocalPath -Force
            }
        }
    }

    $data | ConvertTo-Json -Depth 10 | Set-Content $OutputPath -Encoding UTF8
    Write-Log -Message "manifest-local.json written: $OutputPath" -Level DEBUG
}

# -----------------------------------------------------------------------
# Private: Copy-LoadoutFiles
# Copies required Loadout source assets to <UsbRoot>/src/ and writes a thin
# Loadout-Offline.ps1 entry point at the USB root that references the
# local manifest.
# -----------------------------------------------------------------------
function Copy-LoadoutFiles {
    param(
        [Parameter(Mandatory)] [string]$SrcRoot,
        [Parameter(Mandatory)] [string]$UsbRoot
    )

    $usbSrcDir = Join-Path $UsbRoot 'src'

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would copy src/*.ps1 and GUI.xaml -> $usbSrcDir" -Level DEBUG
    } else {
        New-Item -ItemType Directory -Path $usbSrcDir -Force | Out-Null
        foreach ($f in (Get-ChildItem $SrcRoot -Filter '*.ps1')) {
            Copy-Item $f.FullName $usbSrcDir -Force
        }
        $guiPath = Join-Path $SrcRoot 'GUI.xaml'
        if (Test-Path $guiPath) {
            Copy-Item $guiPath $usbSrcDir -Force
        }
        Write-Log -Message "  Loadout src files copied to $usbSrcDir" -Level DEBUG
    }

    # Loadout-Offline.ps1 is a thin wrapper that passes the local manifest
    # path to Loadout.ps1 so ManifestManager loads manifest-local.json.
    $offlineScript = @'
# Loadout-Offline.ps1 -- USB kit entry point.
# Launches Loadout from this drive using the locally-cached manifest.
# Run from an elevated PowerShell prompt.
$ErrorActionPreference = 'Stop'
$srcDir      = Join-Path $PSScriptRoot 'src'
$manifestPath = Join-Path $PSScriptRoot 'manifest-local.json'
& "$srcDir\Loadout.ps1" -ManifestPath $manifestPath
'@

    $offlinePath = Join-Path $UsbRoot 'Loadout-Offline.ps1'
    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would write: $offlinePath" -Level DEBUG
    } else {
        $offlineScript | Set-Content $offlinePath -Encoding ASCII
        Write-Log -Message "  Loadout-Offline.ps1 written: $offlinePath" -Level DEBUG
    }
}

# -----------------------------------------------------------------------
# Private: Write-USBReadme
# Writes README.txt to the USB root with usage and content notes.
# -----------------------------------------------------------------------
function Write-USBReadme {
    param(
        [Parameter(Mandatory)] [string]$UsbRoot,
        [string]$Version = '?'
    )

    $readme = @"
Loadout USB Kit -- v$Version
================================

USAGE
-----
1. Open an elevated PowerShell prompt (Run as Administrator).
2. Navigate to this folder:
     cd <drive letter>:\Loadout-USB
3. Run the offline launcher:
     .\Loadout-Offline.ps1

CONTENTS
--------
  Loadout-Offline.ps1     Entry point (run this)
  manifest-local.json     App registry with local installer paths
  src\                    Loadout PowerShell modules
  installers\             Downloaded app installers
  installers\modules\     Downloaded PowerShell modules (PSGallery)
  installers\winget\      Winget offline manifests and packages

NOTES
-----
- Winget must be installed on the target machine. On Windows 11 it is
  included by default.
- VS Code extensions are not included -- they require marketplace access.
- WSL distros, Windows Features, and Registry settings require an internet
  connection and cannot be pre-packaged in the USB kit.
- Apps listed as WingetOnly will use winget to install; an internet
  connection may be required for those specific apps.

Built with Loadout -- github.com/bferguson-dev/Loadout
"@

    $readmePath = Join-Path $UsbRoot 'README.txt'
    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would write: $readmePath" -Level DEBUG
    } else {
        $readme | Set-Content $readmePath -Encoding ASCII
        Write-Log -Message "  README.txt written: $readmePath" -Level DEBUG
    }
}

# -----------------------------------------------------------------------
# Public: Invoke-USBBuild
# Main entry point for USB kit building. Downloads all USB-eligible apps,
# generates manifest-local.json, copies Loadout source files, and writes
# README.txt.
#
# -Apps          <object[]>   -- app objects to process (all manifest apps)
# -Destination   <string>     -- parent folder; kit built at Destination\Loadout-USB\
# -OnItemStart   <scriptblock($i, $n, $name)>   -- called before each download
# -OnItemDone    <scriptblock($i, $n, $status)> -- called after each download
#
# Returns the build-results hashtable (id -> status string).
# -----------------------------------------------------------------------
function Invoke-USBBuild {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]]$Apps,
        [Parameter(Mandatory)] [string]$Destination,
        [scriptblock]$OnItemStart = $null,
        [scriptblock]$OnItemDone  = $null
    )

    $Script:USBBuildResults = @{}

    # Only process apps that are not explicitly excluded from USB kit
    $buildableApps = @($Apps | Where-Object { $_.includeInUSBKit -ne $false })

    $usbRoot        = Join-Path $Destination 'Loadout-USB'
    $installersPath = Join-Path $usbRoot 'installers'
    $wingetPath     = Join-Path $installersPath 'winget'
    $modulesPath    = Join-Path $installersPath 'modules'

    Write-Log -Message "USB kit build started. Output: $usbRoot" -Level INFO
    Write-Log -Message "$($buildableApps.Count) of $($Apps.Count) apps eligible for USB kit." -Level INFO

    if (-not $Script:DryRun) {
        New-Item -ItemType Directory -Path $usbRoot        -Force | Out-Null
        New-Item -ItemType Directory -Path $installersPath -Force | Out-Null
        New-Item -ItemType Directory -Path $wingetPath     -Force | Out-Null
        New-Item -ItemType Directory -Path $modulesPath    -Force | Out-Null
    }

    # Download phase
    $downloadResults = @{}  # id -> { Status, LocalPath }
    $i = 0
    foreach ($app in $buildableApps) {
        $i++
        $n = $buildableApps.Count
        if ($OnItemStart) { & $OnItemStart $i $n $app.displayName }
        Write-Log -Message "[$i/$n] USB: $($app.displayName)" -Level INFO

        $res = Invoke-USBDownloadSingle -App $app `
                   -InstallersPath $installersPath `
                   -WingetPath     $wingetPath `
                   -ModulesPath    $modulesPath

        $downloadResults[$app.id]        = $res
        $Script:USBBuildResults[$app.id] = $res.Status

        if ($OnItemDone) { & $OnItemDone $i $n $res.Status }
    }

    # Generate manifest-local.json
    $manifestPath      = Get-ManifestPath
    $localManifestPath = Join-Path $usbRoot 'manifest-local.json'
    if (-not $manifestPath -or -not (Test-Path $manifestPath)) {
        throw "Loaded manifest path is invalid or missing: '$manifestPath'"
    }

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would generate: $localManifestPath" -Level DEBUG
    } else {
        New-LocalManifest -OriginalManifestPath $manifestPath `
                          -DownloadResults $downloadResults `
                          -OutputPath $localManifestPath
    }

    # Copy Loadout source files and write offline entry point
    Copy-LoadoutFiles -SrcRoot $PSScriptRoot -UsbRoot $usbRoot

    # Write README
    $version = '?'
    try {
        $versionFile = Join-Path (Split-Path $PSScriptRoot -Parent) 'version.json'
        $vd = Get-Content $versionFile -Raw | ConvertFrom-Json
        $version = $vd.version
    } catch { Write-Log -Message "Could not read version.json for USB README: $_" -Level WARN }
    Write-USBReadme -UsbRoot $usbRoot -Version $version

    # Summary
    $successes   = @($Script:USBBuildResults.Values | Where-Object { $_ -eq 'Success' }).Count
    $wingetOnly  = @($Script:USBBuildResults.Values | Where-Object { $_ -eq 'WingetOnly' }).Count
    $skipped     = @($Script:USBBuildResults.Values | Where-Object { $_ -eq 'Skipped' }).Count
    $failed      = @($Script:USBBuildResults.Values | Where-Object { $_ -eq 'Failed' }).Count

    Write-Log -Message "USB kit complete. Downloaded: $successes  WingetOnly: $wingetOnly  Skipped: $skipped  Failed: $failed" -Level OK
    Write-Log -Message "USB kit location: $usbRoot" -Level OK

    return $Script:USBBuildResults
}

# -----------------------------------------------------------------------
# Public: Get-USBBuildResults
# Returns the results hashtable from the last Invoke-USBBuild call.
# id -> 'Success' | 'WingetOnly' | 'Skipped' | 'Failed'
# -----------------------------------------------------------------------
function Get-USBBuildResults {
    return $Script:USBBuildResults
}

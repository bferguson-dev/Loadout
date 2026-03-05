# ManifestManager.ps1 -- Loadout manifest loading and querying module
# Loads manifest.json from repo root, optionally merges user-manifest.json
# from AppData. Provides app lookup and install plan resolution.
#
# Dot-sourced by Loadout.ps1 at startup alongside Logger.ps1.
# All output goes through Write-Log -- no bare Write-Host calls.
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns','')]
param()

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------
# Script-scope state -- set by Initialize-ManifestManager
# -----------------------------------------------------------------------
$Script:ManifestApps      = @()      # Combined app list (manifest + user-manifest)
$Script:PreferX64         = $true    # Global preferX64 flag from manifest top level
$Script:ManifestVersion   = '0.0.0'  # Version string from manifest
$Script:ManifestPath      = ''       # Full path to the loaded manifest file
$Script:ManifestDirectory = ''       # Directory containing the loaded manifest file

# -----------------------------------------------------------------------
# Public: Initialize-ManifestManager
# Loads manifest.json and optionally merges user-manifest.json.
#
# ManifestPath defaults to manifest.json one directory above $PSScriptRoot
# (i.e., repo root when running from src/ or tests/).
# UserManifestPath defaults to %APPDATA%\Loadout\user-manifest.json.
# -----------------------------------------------------------------------
function Initialize-ManifestManager {
    [CmdletBinding()]
    param(
        [string]$ManifestPath,
        [string]$UserManifestPath
    )

    # Default: manifest.json at repo root (parent of whichever dir is running)
    if (-not $ManifestPath) {
        $repoRoot     = Split-Path $PSScriptRoot -Parent
        $ManifestPath = Join-Path $repoRoot 'manifest.json'
    }

    if (-not (Test-Path $ManifestPath)) {
        throw "Manifest not found at: $ManifestPath"
    }

    Write-Log -Message "Loading manifest: $ManifestPath" -Level DEBUG

    $raw  = Get-Content -Path $ManifestPath -Raw -Encoding UTF8
    $data = $raw | ConvertFrom-Json

    $Script:ManifestVersion   = $data.version
    $Script:PreferX64         = if ($null -ne $data.preferX64) { [bool]$data.preferX64 } else { $true }
    $Script:ManifestApps      = @($data.apps)
    $Script:ManifestPath      = $ManifestPath
    $Script:ManifestDirectory = Split-Path $ManifestPath -Parent

    Write-Log -Message "Manifest loaded: $($Script:ManifestApps.Count) apps (v$($Script:ManifestVersion))" -Level INFO

    # Merge user-manifest if it exists
    if (-not $UserManifestPath) {
        $UserManifestPath = Join-Path $env:APPDATA 'Loadout\user-manifest.json'
    }

    if (Test-Path $UserManifestPath) {
        Write-Log -Message "Loading user manifest: $UserManifestPath" -Level DEBUG

        $userRaw  = Get-Content -Path $UserManifestPath -Raw -Encoding UTF8
        $userData = $userRaw | ConvertFrom-Json
        $userApps = @($userData.apps)
        $merged   = 0

        foreach ($userApp in $userApps) {
            # User manifest entries override matching IDs in the main manifest
            $Script:ManifestApps = @($Script:ManifestApps | Where-Object { $_.id -ne $userApp.id })
            $Script:ManifestApps = $Script:ManifestApps + @($userApp)
            $merged++
        }

        Write-Log -Message "User manifest merged: $merged custom app(s)" -Level INFO
    }
}

# -----------------------------------------------------------------------
# Public: Get-ManifestApps
# Returns the full merged app list.
# -----------------------------------------------------------------------
function Get-ManifestApps {
    return $Script:ManifestApps
}

# -----------------------------------------------------------------------
# Public: Get-ManifestDirectory
# Returns the directory that contains the loaded manifest file.
# Used by USBBuilder and InstallEngine for offline local-path resolution.
# -----------------------------------------------------------------------
function Get-ManifestDirectory {
    return $Script:ManifestDirectory
}

# -----------------------------------------------------------------------
# Public: Get-ManifestPath
# Returns the full path to the manifest file loaded by
# Initialize-ManifestManager.
# -----------------------------------------------------------------------
function Get-ManifestPath {
    return $Script:ManifestPath
}

# -----------------------------------------------------------------------
# Public: Get-AppById
# Returns the app object with the given ID, or $null if not found.
# -----------------------------------------------------------------------
function Get-AppById {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Id
    )

    return $Script:ManifestApps | Where-Object { $_.id -eq $Id } | Select-Object -First 1
}

# -----------------------------------------------------------------------
# Public: Get-AppsByCategory
# Returns all apps belonging to the given category.
# -----------------------------------------------------------------------
function Get-AppsByCategory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Category
    )

    return @($Script:ManifestApps | Where-Object { $_.category -eq $Category })
}

# -----------------------------------------------------------------------
# Public: Get-PrerequisiteApps
# Returns all apps where isPrerequisite is true.
# -----------------------------------------------------------------------
function Get-PrerequisiteApps {
    return @($Script:ManifestApps | Where-Object { $_.isPrerequisite -eq $true })
}

# -----------------------------------------------------------------------
# Public: Resolve-InstallPlan
# Given an array of selected app IDs, returns an ordered array of app
# objects with dependencies injected ahead of the apps that need them.
# Each ID appears at most once (deduplicated). Missing dependency IDs
# are logged as WARN and skipped.
# -----------------------------------------------------------------------
function Resolve-InstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$SelectedIds
    )

    $visited = @{}  # id -> $true, tracks what has been added
    $ordered = [System.Collections.Generic.List[object]]::new()

    # Inner recursive function: depth-first, dependencies before the app
    function Resolve-AppById {
        param([string]$Id)

        if ($visited[$Id]) { return }
        $visited[$Id] = $true

        $app = Get-AppById -Id $Id
        if ($null -eq $app) {
            Write-Log -Message "Dependency '$Id' not found in manifest -- skipping" -Level WARN
            return
        }

        # Recurse into dependencies first so they land ahead of this app
        if ($app.dependencies -and $app.dependencies.Count -gt 0) {
            foreach ($depId in $app.dependencies) {
                Resolve-AppById -Id $depId
            }
        }

        $ordered.Add($app)
    }

    foreach ($id in $SelectedIds) {
        Resolve-AppById -Id $id
    }

    Write-Log -Message "Install plan resolved: $($ordered.Count) app(s) (from $($SelectedIds.Count) selected)" -Level DEBUG

    return $ordered.ToArray()
}

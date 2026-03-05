# SelfUpdater.ps1 -- Checks GitHub for a newer Loadout version and applies it.
# Dot-sourced by Loadout.ps1. Exposes three functions:
#   Get-RemoteVersionInfo  -- fetches version.json from GitHub
#   Test-NewerVersion      -- semver comparison
#   Invoke-SelfUpdate      -- downloads release zip, extracts, launches Update-Helper.ps1
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

$ErrorActionPreference = 'Stop'

$Script:RemoteVersionUrl = 'https://raw.githubusercontent.com/bferguson-dev/Loadout/main/version.json'

# -----------------------------------------------------------------------
# Get-RemoteVersionInfo
# Fetches version.json from GitHub with a 5-second timeout.
# Returns PSCustomObject{ version: string; releaseUrl: string }
# or $null if the request fails (offline, firewall, etc.).
# -----------------------------------------------------------------------
function Get-RemoteVersionInfo {
    try {
        $response = Invoke-WebRequest -Uri $Script:RemoteVersionUrl `
                        -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        return $response.Content | ConvertFrom-Json
    } catch {
        Write-Log -Message "Version check failed: $_" -Level DEBUG
        return $null
    }
}

# -----------------------------------------------------------------------
# Test-NewerVersion
# Returns $true if $Remote is strictly newer than $Local (semver strings,
# e.g. '1.2.0' vs '1.1.3'). Returns $false on parse error or equal versions.
# -----------------------------------------------------------------------
function Test-NewerVersion {
    param(
        [string]$Local,
        [string]$Remote
    )
    try {
        $l   = $Local  -split '\.' | ForEach-Object { [int]$_ }
        $r   = $Remote -split '\.' | ForEach-Object { [int]$_ }
        $max = [Math]::Max($l.Count, $r.Count)
        for ($i = 0; $i -lt $max; $i++) {
            $lv = if ($i -lt $l.Count) { $l[$i] } else { 0 }
            $rv = if ($i -lt $r.Count) { $r[$i] } else { 0 }
            if ($rv -gt $lv) { return $true  }
            if ($rv -lt $lv) { return $false }
        }
        return $false
    } catch {
        return $false
    }
}

# -----------------------------------------------------------------------
# Invoke-SelfUpdate
# Downloads the release zip to %TEMP%\Loadout-Update\, extracts it,
# then launches Update-Helper.ps1 as a separate powershell.exe process.
# Update-Helper waits for the calling process (ProcessId) to exit, copies
# the new files over RepoRoot, and relaunches Loadout.ps1.
#
# Returns $true if the helper was launched successfully; $false on error.
# The caller should close the window after $true is returned.
# -----------------------------------------------------------------------
function Invoke-SelfUpdate {
    param(
        [Parameter(Mandatory)] [string]$ReleaseUrl,
        [Parameter(Mandatory)] [string]$RepoRoot,
        [Parameter(Mandatory)] [int]$ProcessId
    )

    try {
        # Only allow GitHub-hosted HTTPS release archives.
        $releaseUri = [Uri]$ReleaseUrl
        if ($releaseUri.Scheme -ne 'https' -or
            $releaseUri.Host -notin @('github.com', 'objects.githubusercontent.com', 'codeload.github.com')) {
            throw "Release URL host is not allowed: $($releaseUri.Host)"
        }

        $tempDir    = Join-Path $env:TEMP 'Loadout-Update'
        $zipPath    = Join-Path $tempDir  'Loadout-update.zip'
        $extractDir = Join-Path $tempDir  'extracted'

        # Clean up any leftover temp from a previous interrupted attempt
        if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
        [void][System.IO.Directory]::CreateDirectory($tempDir)
        [void][System.IO.Directory]::CreateDirectory($extractDir)

        Write-Log -Message "Downloading update from: $ReleaseUrl" -Level INFO
        Invoke-WebRequest -Uri $ReleaseUrl -OutFile $zipPath `
                          -UseBasicParsing -TimeoutSec 120 -ErrorAction Stop

        Write-Log -Message 'Extracting update archive...' -Level INFO
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir)

        # GitHub release zips have one top-level folder (e.g. Loadout-v1.2.0/).
        # Find it; if the zip is already flat, use extractDir directly.
        $topDirs   = @(Get-ChildItem -LiteralPath $extractDir -Directory)
        $sourceDir = if ($topDirs.Count -eq 1) { $topDirs[0].FullName } else { $extractDir }

        # Always execute the currently-installed helper script. Running a helper
        # script directly from the downloaded archive would execute untrusted code
        # before files are copied into RepoRoot.
        $helperPath = Join-Path $RepoRoot 'src\Update-Helper.ps1'
        if (-not (Test-Path $helperPath)) {
            throw "Update helper not found at: $helperPath"
        }

        $launchScript = Join-Path $RepoRoot 'src\Loadout.ps1'

        Write-Log -Message 'Launching update helper...' -Level INFO
        $argList = @(
            '-ExecutionPolicy', 'Bypass',
            '-NonInteractive',
            '-File',         $helperPath,
            '-MainPid',      $ProcessId,
            '-SourceDir',    $sourceDir,
            '-RepoRoot',     $RepoRoot,
            '-LaunchScript', $launchScript
        )
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argList -WindowStyle Normal
        return $true
    } catch {
        Write-Log -Message "Self-update failed: $_" -Level ERROR
        return $false
    }
}

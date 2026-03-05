# Update-Helper.ps1 -- Applies a Loadout update after the main process exits.
# Launched by SelfUpdater.ps1 via Start-Process (runs in its own powershell.exe).
#
# Flow:
#   1. Wait for the main Loadout process (MainPid) to exit (up to 30 s).
#   2. Copy new files from SourceDir over RepoRoot (recursive, -Force).
#   3. Remove the temp directory.
#   4. Relaunch Loadout via LaunchScript.
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param(
    [int]$MainPid,
    [string]$SourceDir,
    [string]$RepoRoot,
    [string]$LaunchScript
)

$ErrorActionPreference = 'Continue'

function Write-Status {
    param([string]$Message)
    Write-Host "[Loadout Updater] $Message"
}

Write-Status "Update helper started."
Write-Status "Waiting for Loadout (PID $MainPid) to exit..."

# Wait up to 30 seconds for the main process to exit before proceeding.
$deadline = (Get-Date).AddSeconds(30)
do {
    $proc = Get-Process -Id $MainPid -ErrorAction SilentlyContinue
    if (-not $proc) { break }
    Start-Sleep -Milliseconds 500
} while ((Get-Date) -lt $deadline)

$stillRunning = Get-Process -Id $MainPid -ErrorAction SilentlyContinue
if ($stillRunning) {
    Write-Status "ERROR: Main process did not exit within 30 s. Update aborted to avoid partial copy."
    Read-Host 'Press Enter to exit'
    exit 1
}

# Copy new files over the existing install.
Write-Status "Copying updated files to: $RepoRoot"
try {
    Copy-Item -Path "$SourceDir\*" -Destination $RepoRoot -Recurse -Force -ErrorAction Stop
    Write-Status "Files copied successfully."
} catch {
    Write-Status "ERROR: Could not copy files: $_"
    Read-Host 'Press Enter to exit'
    exit 1
}

# Remove the temp directory (best-effort).
try {
    $tempParent = Split-Path $SourceDir -Parent
    Remove-Item $tempParent -Recurse -Force -ErrorAction SilentlyContinue
} catch { Write-Status "Temp directory cleanup skipped: $_" }

# Relaunch Loadout.
Write-Status "Relaunching Loadout..."
try {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-ExecutionPolicy', 'Bypass', '-File', $LaunchScript)
    Write-Status "Loadout relaunched. This window will close shortly."
    Start-Sleep -Seconds 2
} catch {
    Write-Status "ERROR: Could not relaunch Loadout: $_"
    Write-Status "Please launch manually: $LaunchScript"
    Read-Host 'Press Enter to exit'
    exit 1
}

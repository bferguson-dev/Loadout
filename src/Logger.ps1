# Logger.ps1 -- Loadout logging module
# Handles dual-stream output: WPF log panel and timestamped disk log.
# Dot-sourced by Loadout.ps1 at startup. No other src/ module calls
# Write-Host directly -- all output goes through Write-Log.
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost','')]
param()

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------
# Script-scope state -- set by Initialize-Logger, read by Write-Log
# -----------------------------------------------------------------------
$Script:LogFilePath = $null   # Full path to the open log file for this run
$Script:LogPanel    = $null   # WPF control reference (null until Session 7 wires it in)
$Script:DryRun      = $false  # Whether DryRun mode is active
$Script:DiskLogUnavailableNotified = $false  # Avoid repeated console warnings when disk logging fails

# Log level -> padded label (5 chars wide for column alignment in log file)
$Script:LevelPad = @{
    'INFO'  = 'INFO '
    'OK'    = 'OK   '
    'WARN'  = 'WARN '
    'ERROR' = 'ERROR'
    'DEBUG' = 'DEBUG'
}

# Log level -> Write-Host foreground color (console fallback)
$Script:LevelColor = @{
    'INFO'  = 'White'
    'OK'    = 'Green'
    'WARN'  = 'Yellow'
    'ERROR' = 'Red'
    'DEBUG' = 'Gray'
}

# Log level -> WPF hex foreground color (RichTextBox Run elements)
$Script:LevelWpfColor = @{
    'INFO'  = '#FFFFFF'
    'OK'    = '#00D26A'
    'WARN'  = '#FFB900'
    'ERROR' = '#E74856'
    'DEBUG' = '#888888'
}


# -----------------------------------------------------------------------
# Public: Initialize-Logger
# Call once from Loadout.ps1 before any Write-Log calls.
# Creates %APPDATA%\Loadout\Logs\ if missing and opens a new
# timestamped log file for this run. Stores the DryRun flag.
# -----------------------------------------------------------------------
function Initialize-Logger {
    [CmdletBinding()]
    param(
        [switch]$DryRun
    )

    $Script:DryRun = $DryRun.IsPresent
    $Script:DiskLogUnavailableNotified = $false

    # Create a writable log directory. Prefer APPDATA; fall back to TEMP.
    $candidateDirs = @(
        (Join-Path $env:APPDATA 'Loadout\Logs'),
        (Join-Path $env:TEMP    'Loadout\Logs')
    )

    $logDir = $null
    foreach ($candidate in $candidateDirs) {
        if (-not $candidate) { continue }
        try {
            if (-not (Test-Path $candidate)) {
                New-Item -ItemType Directory -Path $candidate -Force | Out-Null
            }
            $probePath = Join-Path $candidate "probe-$([guid]::NewGuid().ToString('N')).tmp"
            Set-Content -Path $probePath -Value 'ok' -Encoding ASCII
            Remove-Item -Path $probePath -Force -ErrorAction SilentlyContinue
            $logDir = $candidate
            break
        }
        catch {
            continue
        }
    }

    if (-not $logDir) {
        $Script:LogFilePath = $null
        Write-Host '[WARN ] Logging to disk is unavailable; continuing with console-only logs.' -ForegroundColor Yellow
        return
    }

    # One log file per run -- timestamped to the second
    $stamp = Get-Date -Format 'yyyy-MM-dd-HHmmss'
    $Script:LogFilePath = Join-Path $logDir "Loadout-$stamp.log"

    # Write session header to disk
    $modeTag = if ($Script:DryRun) { ' -- DRY RUN MODE' } else { '' }
    $header  = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [INFO ] Loadout session started$modeTag"
    try {
        Add-Content -Path $Script:LogFilePath -Value $header -Encoding UTF8
    }
    catch {
        $Script:LogFilePath = $null
        Write-Host "[WARN ] Could not write log file: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Echo header to console -- LogPanel is always null at this stage
    $headerColor = if ($Script:DryRun) { 'Yellow' } else { 'White' }
    Write-Host $header -ForegroundColor $headerColor
}

# -----------------------------------------------------------------------
# Public: Write-Log
# The sole output function for all src/ modules. Never call Write-Host
# from InstallEngine, UpdateChecker, ManifestManager, or any other
# src/ module -- always use Write-Log instead.
#
# Level defaults to INFO. -NoNewline suppresses the line ending on both
# console and GUI output; disk always receives the text as-is.
#
# DEBUG messages are written to disk on every call but are suppressed
# from the console and GUI unless DryRun was set in Initialize-Logger.
# -----------------------------------------------------------------------
function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',

        [switch]$NoNewline
    )

    # Guard: Initialize-Logger must be called first
    if (-not $Script:LogFilePath) {
        if (-not $Script:DiskLogUnavailableNotified) {
            $Script:DiskLogUnavailableNotified = $true
            Write-Host '[WARN ] Write-Log called before Initialize-Logger -- console only' `
                -ForegroundColor Yellow
        }
        Write-Host $Message -ForegroundColor White -NoNewline:$NoNewline
        return
    }

    # Build the formatted log line
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $pad  = $Script:LevelPad[$Level]
    $line = "[$ts] [$pad] $Message"

    # Always attempt disk logging regardless of level or DryRun state.
    # If disk logging fails, continue with console/GUI output.
    try {
        if ($NoNewline) {
            # Append without trailing newline -- bypass Add-Content which forces one
            [System.IO.File]::AppendAllText(
                $Script:LogFilePath,
                $line,
                [System.Text.Encoding]::UTF8
            )
        }
        else {
            Add-Content -Path $Script:LogFilePath -Value $line -Encoding UTF8
        }
    }
    catch {
        $Script:LogFilePath = $null
        if (-not $Script:DiskLogUnavailableNotified) {
            $Script:DiskLogUnavailableNotified = $true
            Write-Host "[WARN ] Logging to disk failed; switching to console-only output. $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # DEBUG: suppress from console and GUI unless DryRun is active
    if ($Level -eq 'DEBUG' -and -not $Script:DryRun) { return }

    $color = $Script:LevelColor[$Level]

    # WPF panel output (only when GUI is attached -- Session 7 and later)
    # LogPanel is a RichTextBox. One Paragraph per Write-Log call is appended
    # directly to Document.Blocks -- avoids BlockCollection enumeration quirks.
    # Uses Dispatcher.Invoke for thread safety.
    if ($null -ne $Script:LogPanel) {
        try {
            # Capture all needed references as locals -- GetNewClosure() captures
            # locals reliably; $Script: variables resolve to Logger.ps1's own scope
            # inside a closure and would be null at that point.
            $capturedPanel    = $Script:LogPanel
            $capturedLine     = $line
            $capturedHexColor = $Script:LevelWpfColor[$Level]

            $appendBlock = {
                $para           = [System.Windows.Documents.Paragraph]::new()
                $para.Margin    = [System.Windows.Thickness]::new(0)
                $run            = [System.Windows.Documents.Run]::new($capturedLine)
                $run.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($capturedHexColor)
                [void]$para.Inlines.Add($run)
                [void]$capturedPanel.Document.Blocks.Add($para)
                $capturedPanel.ScrollToEnd()
            }.GetNewClosure()

            $capturedPanel.Dispatcher.Invoke([System.Action]$appendBlock)
        }
        catch {
            # GUI write failed -- fall through to console
            Write-Host $line -ForegroundColor $color -NoNewline:$NoNewline
        }
        return
    }

    # Console fallback -- default until GUI is attached in Session 7
    Write-Host $line -ForegroundColor $color -NoNewline:$NoNewline
}

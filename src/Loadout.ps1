# Loadout.ps1 -- Entry point for the Loadout WPF GUI application.
# Dot-sources all modules in order, loads GUI.xaml, wires the Logger
# to the WPF log panel, populates the app checklist from the manifest,
# and shows the main window.
#
# -ManifestPath: optional path to manifest.json; used by Loadout-Offline.ps1
#                to point at manifest-local.json on a USB kit drive.
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs','')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions','')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns','')]
param([string]$ManifestPath = '')

$ErrorActionPreference = 'Stop'

# Keep one resolved manifest path for all foreground/background operations.
$Script:ActiveManifestPath = if ($ManifestPath) {
    $ManifestPath
} else {
    Join-Path (Split-Path $PSScriptRoot -Parent) 'manifest.json'
}

# -----------------------------------------------------------------------
# Module imports -- order matters: Logger must come first so $Script:DryRun
# and $Script:LogPanel are defined before the other modules reference them.
# InstallEngine.ps1 does NOT dot-source Logger or ManifestManager itself;
# Loadout.ps1 brings everything into scope.
# -----------------------------------------------------------------------
. "$PSScriptRoot\Logger.ps1"
. "$PSScriptRoot\ManifestManager.ps1"
. "$PSScriptRoot\InstallEngine.ps1"
. "$PSScriptRoot\UpdateChecker.ps1"
. "$PSScriptRoot\USBBuilder.ps1"
. "$PSScriptRoot\SelfUpdater.ps1"

# -----------------------------------------------------------------------
# WPF assemblies
# -----------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# -----------------------------------------------------------------------
# Load XAML -- pattern locked in by DESIGN.md, do not change
# -----------------------------------------------------------------------
$xaml = [System.Xml.XmlDocument]::new()
$xaml.Load("$PSScriptRoot\GUI.xaml")
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# -----------------------------------------------------------------------
# Initialize Logger and wire to WPF log panel
# -----------------------------------------------------------------------
Initialize-Logger

# Assign the RichTextBox to Logger's $Script:LogPanel.
$Script:LogPanel = $window.FindName('LogPanel')
$Script:LogPanel.Document.PagePadding = [System.Windows.Thickness]::new(4)

# -----------------------------------------------------------------------
# Initialize ManifestManager -- use override path from -ManifestPath if given
# -----------------------------------------------------------------------
Initialize-ManifestManager -ManifestPath $Script:ActiveManifestPath

# -----------------------------------------------------------------------
# Set version label from version.json at repo root
# -----------------------------------------------------------------------
$lblVersion   = $window.FindName('LblVersion')
$localVersion = '0.0.0'
try {
    $versionFile  = Join-Path (Split-Path $PSScriptRoot -Parent) 'version.json'
    $versionData  = Get-Content $versionFile -Raw | ConvertFrom-Json
    $localVersion = $versionData.version
    $lblVersion.Text = "v$($versionData.version)"
} catch {
    $lblVersion.Text = 'v?.?.?'
    Write-Log -Message "Could not read version.json: $_" -Level 'WARN'
}

# -----------------------------------------------------------------------
# Helper: Rebuild-AppListPanel
# Clears and repopulates the app checklist from the current manifest.
# Called at startup and after any manifest change (custom app add/import).
# PreCheckedIds: HashSet of app IDs to pre-check; $null = leave all unchecked.
# -----------------------------------------------------------------------
function Rebuild-AppListPanel {
    param([System.Collections.Generic.HashSet[string]]$PreCheckedIds = $null)

    $appListPanel.Children.Clear()
    $Script:AppRowElements = @{}   # clear lookup table on every rebuild
    $brush    = [System.Windows.Media.BrushConverter]::new()
    $grayBrush = $brush.ConvertFromString('#666666')
    $firstCat = $true

    # Group apps by category, preserving manifest order
    $catOrder = [System.Collections.Generic.List[string]]::new()
    $catApps  = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[object]]]::new()
    foreach ($app in (Get-ManifestApps)) {
        $cat = $app.category
        if (-not $catApps.ContainsKey($cat)) {
            $catApps[$cat] = [System.Collections.Generic.List[object]]::new()
            $catOrder.Add($cat)
        }
        $catApps[$cat].Add($app)
    }

    foreach ($cat in $catOrder) {
        # Spacer between categories (not before the first)
        if (-not $firstCat) {
            $spacer        = [System.Windows.Controls.TextBlock]::new()
            $spacer.Height = 6
            $appListPanel.Children.Add($spacer) | Out-Null
        }
        $firstCat = $false

        # Outer container for this category (header + apps)
        $catPanel = [System.Windows.Controls.StackPanel]::new()

        # Apps container -- collapsed/expanded by the toggle button; starts collapsed
        $appsContainer = [System.Windows.Controls.StackPanel]::new()
        $appsContainer.Visibility = [System.Windows.Visibility]::Collapsed

        # Toggle button: "v  Category" when expanded, ">  Category" when collapsed
        $headerBtn                          = [System.Windows.Controls.Button]::new()
        $headerBtn.Content                  = ">  $cat"
        $headerBtn.Tag                      = $cat
        $headerBtn.Foreground               = $brush.ConvertFromString('#5CB8FF')
        $headerBtn.Background               = [System.Windows.Media.Brushes]::Transparent
        $headerBtn.BorderThickness          = [System.Windows.Thickness]::new(0)
        $headerBtn.HorizontalContentAlignment = [System.Windows.HorizontalAlignment]::Left
        $headerBtn.FontSize                 = $Script:FontSizes.Cat
        $headerBtn.FontWeight               = [System.Windows.FontWeights]::SemiBold
        $headerBtn.Margin                   = [System.Windows.Thickness]::new(0, 4, 0, 2)
        $headerBtn.Cursor                   = [System.Windows.Input.Cursors]::Hand
        $headerBtn.Padding                  = [System.Windows.Thickness]::new(2, 0, 0, 0)

        $capturedBtn       = $headerBtn
        $capturedContainer = $appsContainer
        $capturedCat       = $cat

        $headerBtn.Add_Click({
            if ($capturedContainer.Visibility -eq [System.Windows.Visibility]::Visible) {
                $capturedContainer.Visibility = [System.Windows.Visibility]::Collapsed
                $capturedBtn.Content          = ">  $capturedCat"
            } else {
                $capturedContainer.Visibility = [System.Windows.Visibility]::Visible
                $capturedBtn.Content          = "v  $capturedCat"
            }
        }.GetNewClosure())

        $sep            = [System.Windows.Controls.Separator]::new()
        $sep.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $sep.Background = $brush.ConvertFromString('#3A3A3A')

        $catPanel.Children.Add($headerBtn)      | Out-Null
        $catPanel.Children.Add($sep)            | Out-Null
        $catPanel.Children.Add($appsContainer)  | Out-Null
        $appListPanel.Children.Add($catPanel)   | Out-Null

        # Populate the apps container -- each app gets a DockPanel row:
        #   [UpdateCB (right)] [VersionTb (right)] [InstallCB (fill)]
        foreach ($app in $catApps[$cat]) {
            $row        = [System.Windows.Controls.DockPanel]::new()
            $row.Margin = [System.Windows.Thickness]::new(8, 2, 0, 2)

            # Update slot -- right-docked DockPanel; checkbox is right-aligned inside so
            # the tick stays near the right edge; version text fills the left of the slot
            # so it sits immediately to the left of the tick rather than 80px away.
            $updateSlot            = [System.Windows.Controls.DockPanel]::new()
            $updateSlot.MinWidth   = [Math]::Max(56, $Script:FontSizes.Header * 4)
            [System.Windows.Controls.DockPanel]::SetDock($updateSlot, [System.Windows.Controls.Dock]::Right)
            $row.Children.Add($updateSlot) | Out-Null

            $updateCb                     = [System.Windows.Controls.CheckBox]::new()
            $updateCb.Tag                 = "__upd__$($app.id)"
            $updateCb.IsEnabled           = $false
            $updateCb.IsChecked           = $false
            $updateCb.Opacity             = 0.3
            $updateCb.VerticalAlignment   = [System.Windows.VerticalAlignment]::Center
            $updateCb.Foreground          = $grayBrush
            $updateCb.ToolTip             = 'Check to include this update in the next Commit'
            [System.Windows.Controls.DockPanel]::SetDock($updateCb, [System.Windows.Controls.Dock]::Right)
            $updateSlot.Children.Add($updateCb) | Out-Null

            # Version text -- fills left portion of update slot, hidden until scan data available
            $verTb               = [System.Windows.Controls.TextBlock]::new()
            $verTb.Tag           = "__ver__$($app.id)"
            $verTb.Text          = ''
            $verTb.Visibility    = [System.Windows.Visibility]::Collapsed
            $verTb.FontFamily    = [System.Windows.Media.FontFamily]::new('Consolas')
            $verTb.FontSize      = $Script:FontSizes.Log
            $verTb.Foreground    = $brush.ConvertFromString('#FFB900')
            $verTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $verTb.TextAlignment = [System.Windows.TextAlignment]::Right
            $verTb.Margin        = [System.Windows.Thickness]::new(0, 0, 12, 0)
            $updateSlot.Children.Add($verTb) | Out-Null

            # Install / Uninstall checkbox -- fills remaining left space
            $cb            = [System.Windows.Controls.CheckBox]::new()
            $cb.Content    = $app.displayName
            $cb.Tag        = $app.id
            $cb.Foreground = [System.Windows.Media.Brushes]::WhiteSmoke
            $cb.ToolTip    = $app.description
            $cb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            if ($null -ne $PreCheckedIds -and $PreCheckedIds.Contains($app.id)) {
                $cb.IsChecked = $true
            }
            $row.Children.Add($cb) | Out-Null

            $appsContainer.Children.Add($row) | Out-Null

            # Register in lookup table for fast access by Apply-ScanResults
            $Script:AppRowElements[$app.id] = @{
                InstallCb  = $cb
                UpdateCb   = $updateCb
                UpdateSlot = $updateSlot
                VersionTb  = $verTb
            }
        }
    }
}

# -----------------------------------------------------------------------
# Script-scope UI state -- font sizes as a mutable reference container
# (must be set before Rebuild-AppListPanel is called)
# -----------------------------------------------------------------------
$Script:FontSizes = @{ Log = 11; Cat = 12; Header = 20 }

# -----------------------------------------------------------------------
# Helper: Expand-CategoriesWithInstalledApps
# After a scan completes, expands any collapsed category that contains at
# least one app with Status Current or UpdateAvailable.
# -----------------------------------------------------------------------
function Expand-CategoriesWithInstalledApps {
    param([hashtable]$ScanResults)
    foreach ($catPanel in $appListPanel.Children) {
        if ($catPanel -isnot [System.Windows.Controls.StackPanel]) { continue }
        $headerBtn     = $null
        $appsContainer = $null
        foreach ($child in $catPanel.Children) {
            if ($child -is [System.Windows.Controls.Button])     { $headerBtn     = $child }
            if ($child -is [System.Windows.Controls.StackPanel]) { $appsContainer = $child }
        }
        if ($null -eq $headerBtn -or $null -eq $appsContainer) { continue }
        if ($appsContainer.Visibility -eq [System.Windows.Visibility]::Visible) { continue }

        $hasInstalled = $false
        foreach ($item in $appsContainer.Children) {
            # Each row is a DockPanel; find the install checkbox (tag without __upd__ prefix)
            if ($item -is [System.Windows.Controls.DockPanel]) {
                foreach ($child in $item.Children) {
                    if ($child -is [System.Windows.Controls.CheckBox] -and
                        -not ([string]$child.Tag).StartsWith('__upd__')) {
                        $id = $child.Tag
                        if ($ScanResults.ContainsKey($id)) {
                            $st = $ScanResults[$id].Status
                            if ($st -eq 'Current' -or $st -eq 'UpdateAvailable') {
                                $hasInstalled = $true
                                break
                            }
                        }
                    }
                }
                if ($hasInstalled) { break }
            }
        }

        if ($hasInstalled) {
            $appsContainer.Visibility = [System.Windows.Visibility]::Visible
            $headerBtn.Content        = "v  $($headerBtn.Tag)"
        }
    }
}

# -----------------------------------------------------------------------
# Populate app checklist from manifest
# -----------------------------------------------------------------------
$appListPanel = $window.FindName('AppListPanel')
[System.Windows.Documents.TextElement]::SetFontSize($appListPanel, $Script:FontSizes.Log)
$apps = Get-ManifestApps
$Script:AppRowElements = @{}   # id -> @{InstallCb; UpdateCb; VersionTb}
Rebuild-AppListPanel

Write-Log -Message "Loadout started. $($apps.Count) apps loaded from manifest." -Level 'INFO'

# -----------------------------------------------------------------------
# Script-scope state -- last completed scan results (for update buttons)
# -----------------------------------------------------------------------
$Script:LastScanResults = @{}

# -----------------------------------------------------------------------
# Helper: Get-CheckBoxes
# Returns all CheckBox controls in AppListPanel (skips TextBlock/Separator)
# -----------------------------------------------------------------------
function Get-CheckBoxes {
    # Structure: appListPanel > catPanel (StackPanel) > appsContainer (StackPanel) >
    #            row (DockPanel) > [UpdateCb (tag starts __upd__), VersionTb, InstallCb]
    # Returns only the INSTALL checkboxes (those whose Tag does NOT start with __upd__).
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($catPanel in $appListPanel.Children) {
        if ($catPanel -isnot [System.Windows.Controls.StackPanel]) { continue }
        foreach ($catChild in $catPanel.Children) {
            if ($catChild -isnot [System.Windows.Controls.StackPanel]) { continue }
            foreach ($row in $catChild.Children) {
                if ($row -isnot [System.Windows.Controls.DockPanel]) { continue }
                foreach ($item in $row.Children) {
                    if ($item -is [System.Windows.Controls.CheckBox] -and
                        -not ([string]$item.Tag).StartsWith('__upd__')) {
                        $result.Add($item) | Out-Null
                    }
                }
            }
        }
    }
    return $result.ToArray()
}

# -----------------------------------------------------------------------
# Helper: Get-UpdateCheckBoxes
# Returns all UPDATE checkboxes (tag starts with __upd__) in AppListPanel.
# -----------------------------------------------------------------------
function Get-UpdateCheckBoxes {
    $result = [System.Collections.Generic.List[object]]::new()
    foreach ($catPanel in $appListPanel.Children) {
        if ($catPanel -isnot [System.Windows.Controls.StackPanel]) { continue }
        foreach ($catChild in $catPanel.Children) {
            if ($catChild -isnot [System.Windows.Controls.StackPanel]) { continue }
            foreach ($row in $catChild.Children) {
                if ($row -isnot [System.Windows.Controls.DockPanel]) { continue }
                foreach ($item in $row.Children) {
                    if ($item -is [System.Windows.Controls.CheckBox] -and
                        ([string]$item.Tag).StartsWith('__upd__')) {
                        $result.Add($item) | Out-Null
                    }
                }
            }
        }
    }
    return $result.ToArray()
}

# -----------------------------------------------------------------------
# Helper: Apply-ScanResults
# Called on the UI thread after a scan completes. Caches the results,
# pre-checks installed apps, and updates StatusBar with the update count.
# -----------------------------------------------------------------------
function Apply-ScanResults {
    param([object]$ScanResults)

    # ScanResults arrives as a PSObject wrapping a hashtable; unwrap it
    $hash = if ($ScanResults -is [hashtable]) {
        $ScanResults
    } elseif ($null -ne $ScanResults -and $null -ne $ScanResults.BaseObject -and
              $ScanResults.BaseObject -is [hashtable]) {
        $ScanResults.BaseObject
    } else { $null }

    # Guard: if the scan returned nothing useful, keep the last known state
    # to prevent all checked apps from appearing as "needs install."
    if ($null -eq $hash -or $hash.Count -eq 0) {
        Write-Log -Message 'Scan returned no data -- previous state preserved.' -Level WARN
        return
    }

    $Script:LastScanResults = $hash

    $whiteBrush  = [System.Windows.Media.Brushes]::WhiteSmoke
    $bconv       = [System.Windows.Media.BrushConverter]::new()
    $grayVerBrush   = $bconv.ConvertFromString('#666666')
    $yellowVerBrush = $bconv.ConvertFromString('#FFB900')
    $updateCount = 0

    foreach ($id in $Script:AppRowElements.Keys) {
        $row   = $Script:AppRowElements[$id]
        $instCb  = $row.InstallCb
        $updCb   = $row.UpdateCb
        $verTb   = $row.VersionTb

        if ($hash.ContainsKey($id)) {
            $entry = $hash[$id]

            # Mark installed apps as checked
            if ($entry.Status -eq 'Current' -or $entry.Status -eq 'UpdateAvailable') {
                $instCb.IsChecked = $true
            }

            if ($entry.Status -eq 'UpdateAvailable') {
                $updateCount++
                # Enable update column -- bright appearance
                $updCb.IsEnabled  = $true
                $updCb.IsChecked  = $false
                $updCb.Opacity    = 1.0
                $updCb.Foreground = $whiteBrush
                $instVer  = if ($entry.InstalledVersion) { $entry.InstalledVersion } else { '?' }
                $availVer = if ($entry.AvailableVersion) { $entry.AvailableVersion } else { '?' }
                $verTb.Text       = "$instVer -> $availVer"
                $verTb.Foreground = $yellowVerBrush
                $verTb.Visibility = [System.Windows.Visibility]::Visible
            } elseif ($entry.Status -eq 'Current') {
                # Installed, no update -- show version dimly, keep update CB greyed
                $updCb.IsEnabled  = $false
                $updCb.IsChecked  = $false
                $updCb.Opacity    = 0.3
                $instVer = if ($entry.InstalledVersion) { $entry.InstalledVersion } else { '' }
                if ($instVer -and $instVer -ne '(installed)') {
                    $verTb.Text       = $instVer
                    $verTb.Foreground = $grayVerBrush
                    $verTb.Visibility = [System.Windows.Visibility]::Visible
                } else {
                    $verTb.Visibility = [System.Windows.Visibility]::Collapsed
                }
            } else {
                # NotInstalled or Failed -- reset to clean state
                $updCb.IsEnabled  = $false
                $updCb.IsChecked  = $false
                $updCb.Opacity    = 0.3
                $verTb.Visibility = [System.Windows.Visibility]::Collapsed
            }
        } else {
            # Not in scan results -- reset
            $updCb.IsEnabled  = $false
            $updCb.IsChecked  = $false
            $updCb.Opacity    = 0.3
            $verTb.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }

    Expand-CategoriesWithInstalledApps -ScanResults $hash

    $window.FindName('StatusBar').Text = if ($updateCount -gt 0) {
        "$updateCount update(s) available"
    } else {
        'All apps up to date'
    }
}

# -----------------------------------------------------------------------
# Helper: Start-BackgroundRunspace
# Runs $ScriptText in a background runspace and polls with a
# DispatcherTimer (250 ms) so results are marshalled back to the UI
# thread without blocking ShowDialog's message pump.
# $OnComplete is called with the last PSObject output from the script.
# -----------------------------------------------------------------------
function Start-BackgroundRunspace {
    param(
        [string]$ScriptText,
        [scriptblock]$OnComplete
    )

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($ScriptText)

    $output      = [System.Management.Automation.PSDataCollection[PSObject]]::new()
    $asyncResult = $ps.BeginInvoke(
                       [System.Management.Automation.PSDataCollection[PSObject]]::new(),
                       $output)

    $capturedPs       = $ps
    $capturedRs       = $rs
    $capturedOutput   = $output
    $capturedAr       = $asyncResult
    $capturedCallback = $OnComplete

    $timer        = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [System.TimeSpan]::FromMilliseconds(250)
    $capturedTimer  = $timer

    $timer.Add_Tick({
        $state = $capturedPs.InvocationStateInfo.State
        if ($state -ne [System.Management.Automation.PSInvocationState]::Running) {
            $capturedTimer.Stop()
            try { $capturedPs.EndInvoke($capturedAr) } catch { Write-Log -Message "EndInvoke error (bg runspace): $_" -Level DEBUG }

            $lastOut = if ($capturedOutput.Count -gt 0) {
                $capturedOutput[$capturedOutput.Count - 1]
            } else { $null }

            $capturedPs.Dispose()
            $capturedRs.Dispose()

            & $capturedCallback $lastOut
        }
    }.GetNewClosure())
    $timer.Start()
}

# -----------------------------------------------------------------------
# Helper: Build-ScanScriptText
# Returns the PowerShell script string that runs Invoke-AppScan.
# -----------------------------------------------------------------------
function Build-ScanScriptText {
    $lp = ("$PSScriptRoot\Logger.ps1") -replace "'", "''"
    $mp = ("$PSScriptRoot\ManifestManager.ps1") -replace "'", "''"
    $ep = ("$PSScriptRoot\InstallEngine.ps1") -replace "'", "''"
    $cp = ("$PSScriptRoot\UpdateChecker.ps1") -replace "'", "''"
    $mf = $Script:ActiveManifestPath -replace "'", "''"
    return @"
. '$lp'
. '$mp'
. '$ep'
. '$cp'
Initialize-Logger
Initialize-ManifestManager -ManifestPath '$mf'
`$allApps = Get-ManifestApps
Invoke-AppScan -Apps `$allApps
"@
}

# -----------------------------------------------------------------------
# Startup: self-update check then app scan
# Runs as soon as the window is fully loaded.
# Self-update check is synchronous (5 s timeout) and runs before the scan
# so that if an update is confirmed, the scan never starts.
# -----------------------------------------------------------------------
$capturedPID      = $PID
$capturedLocalVer = $localVersion
$capturedRepoRoot = Split-Path $PSScriptRoot -Parent
$capturedManifestPath = $Script:ActiveManifestPath

$capturedScriptPath = "$PSScriptRoot\Loadout.ps1"

$window.Add_Loaded({
    # --- Admin elevation check ---
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Log -Message 'Running without admin rights -- installers may prompt for UAC elevation separately.' -Level WARN
        $choice = [System.Windows.MessageBox]::Show(
            "Loadout is not running as Administrator.`nSome installers will prompt for elevation on each app.`n`nRelaunch as Administrator now?",
            'Administrator Rights',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) {
            $argList = "-ExecutionPolicy Bypass -NoExit -File `"$capturedScriptPath`" -ManifestPath `"$capturedManifestPath`""
            Start-Process powershell.exe -Verb RunAs `
                -ArgumentList $argList
            $window.Close()
            return
        }
    }

    # --- Self-update check ---
    $remoteInfo = Get-RemoteVersionInfo
    if ($remoteInfo -and (Test-NewerVersion -Local $capturedLocalVer -Remote $remoteInfo.version)) {
        Write-Log -Message "Update available: v$capturedLocalVer -> v$($remoteInfo.version)" -Level INFO
        $updateMsg = "Loadout v$($remoteInfo.version) is available (you have v$capturedLocalVer).`nDownload and install now?"
        $choice = [System.Windows.MessageBox]::Show(
            $updateMsg,
            'Update Available',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Information)
        if ($choice -eq [System.Windows.MessageBoxResult]::Yes) {
            $launched = Invoke-SelfUpdate -ReleaseUrl $remoteInfo.releaseUrl `
                            -RepoRoot $capturedRepoRoot -ProcessId $capturedPID
            if ($launched) {
                $window.Close()
                return
            }
        }
    }
    # --- End self-update check ---

    $window.FindName('StatusBar').Text = 'Scanning installed apps...'
    Start-BackgroundRunspace -ScriptText (Build-ScanScriptText) -OnComplete {
        param($result)
        Apply-ScanResults -ScanResults $result
        Write-Log -Message 'Startup scan complete.' -Level INFO
    }
}.GetNewClosure())

# -----------------------------------------------------------------------
# Select All / Deselect All
# -----------------------------------------------------------------------
$window.FindName('BtnSelectAll').Add_Click({
    foreach ($cb in (Get-CheckBoxes)) { $cb.IsChecked = $true }
})

$window.FindName('BtnDeselectAll').Add_Click({
    foreach ($cb in (Get-CheckBoxes)) { $cb.IsChecked = $false }
})

# -----------------------------------------------------------------------
# Scan -- re-runs the installed-app scan on demand
# -----------------------------------------------------------------------
$window.FindName('BtnScan').Add_Click({
    $window.FindName('StatusBar').Text = 'Scanning installed apps...'
    Start-BackgroundRunspace -ScriptText (Build-ScanScriptText) -OnComplete {
        param($result)
        Apply-ScanResults -ScanResults $result
        Write-Log -Message 'Scan complete.' -Level INFO
    }
}.GetNewClosure())

# -----------------------------------------------------------------------
# Settings -- placeholder (no-op for now)
# -----------------------------------------------------------------------
$window.FindName('BtnSettings').Add_Click({
    Write-Log -Message 'Settings not yet implemented.' -Level INFO
}.GetNewClosure())

# -----------------------------------------------------------------------
# Helper: Run-UpdateInBackground
# Runs an uninstall phase followed by an install/update phase in a single
# background runspace. Either phase may be empty (pass @() or omit).
# Progress is tracked via a ConcurrentQueue drained by a DispatcherTimer.
# A PHASE message in the queue signals the switch from uninstall to install
# so the progress denominator updates correctly.
# -----------------------------------------------------------------------
function Run-UpdateInBackground {
    param(
        [object[]]$AppsToUpdate    = @(),
        [object[]]$AppsToUninstall = @(),
        [string[]]$UpgradeIds      = @(),   # IDs that should use 'winget upgrade' not 'install'
        [bool]$AllowChocolatey     = $false
    )

    $installCount   = $AppsToUpdate.Count
    $uninstallCount = $AppsToUninstall.Count

    if ($installCount -eq 0 -and $uninstallCount -eq 0) {
        Write-Log -Message 'Nothing to do.' -Level WARN
        return
    }

    $progressItem    = $window.FindName('ProgressItem')
    $progressOverall = $window.FindName('ProgressOverall')
    $statusBar       = $window.FindName('StatusBar')

    $progressItem.Value    = 0
    $progressOverall.Value = 0

    $actionParts = @()
    if ($uninstallCount -gt 0) { $actionParts += "Uninstalling $uninstallCount" }
    if ($installCount   -gt 0) { $actionParts += "Installing/updating $installCount" }
    $statusBar.Text = ($actionParts -join ', ') + '...'

    # Thread-safe queue: runspace enqueues "START:i:n:name", "DONE:i:n:result",
    # or "PHASE:N" (switch denominator to N when install phase begins).
    $progressQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $lp = ("$PSScriptRoot\Logger.ps1") -replace "'", "''"
    $mp = ("$PSScriptRoot\ManifestManager.ps1") -replace "'", "''"
    $ep = ("$PSScriptRoot\InstallEngine.ps1") -replace "'", "''"
    $cp = ("$PSScriptRoot\UpdateChecker.ps1") -replace "'", "''"
    $mf = $Script:ActiveManifestPath -replace "'", "''"

    # Build the uninstall script block (empty string when nothing to uninstall)
    $uninstallBlock = ''
    if ($uninstallCount -gt 0) {
        $uninstallIdList = ($AppsToUninstall | ForEach-Object { "'" + $_.id + "'" }) -join ','
        $uninstallBlock  = @"
`$uPlan = @(@($uninstallIdList) | ForEach-Object { Get-AppById -Id `$_ })
Invoke-UninstallPlan -Apps `$uPlan -OnItemStart `$onStart -OnItemDone `$onDone
"@
        if ($installCount -gt 0) {
            $uninstallBlock += "`$progressQueue.Enqueue('PHASE:$installCount')`n"
        }
    }

    # Build the install script block (empty string when nothing to install).
    # UpgradeIds are registered so InstallEngine uses 'winget upgrade' for them.
    $installBlock = ''
    if ($installCount -gt 0) {
        $idList       = ($AppsToUpdate | ForEach-Object { "'" + $_.id + "'" }) -join ','
        $upgradeIdStr = if ($UpgradeIds.Count -gt 0) {
            ($UpgradeIds | ForEach-Object { "'" + $_ + "'" }) -join ','
        } else { '' }
        $setUpgradesLine = if ($upgradeIdStr) {
            "Set-UpgradeIds -Ids @($upgradeIdStr)"
        } else { '' }
        $installBlock = @"
$setUpgradesLine
`$plan = Resolve-InstallPlan -SelectedIds @($idList)
Invoke-InstallPlan -Apps `$plan -OnItemStart `$onStart -OnItemDone `$onDone -AllowChocolatey `$allowChocolatey
"@
    }

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('progressQueue',   $progressQueue)
    $rs.SessionStateProxy.SetVariable('allowChocolatey', [bool]$AllowChocolatey)
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs

    $scriptText = @"
. '$lp'
. '$mp'
. '$ep'
. '$cp'
Initialize-Logger
Initialize-ManifestManager -ManifestPath '$mf'
# Forward all log messages to the UI panel via the progress queue (LOG:LEVEL:MSG format)
function Write-Log {
    param([string]`$Message, [string]`$Level = 'INFO', [switch]`$NoNewline)
    `$stamp  = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    `$padded = @{INFO='INFO '; OK='OK   '; WARN='WARN '; ERROR='ERROR'; DEBUG='DEBUG'}[`$Level]
    if (-not `$padded) { `$padded = `$Level.PadRight(5) }
    `$line = "[`$stamp] [`$padded] `$Message"
    try { Add-Content -Path `$Script:LogFilePath -Value `$line -Encoding UTF8 } catch { }
    `$progressQueue.Enqueue("LOG:`${Level}:`${Message}")
}
`$onStart = { param(`$i,`$n,`$name)   `$progressQueue.Enqueue("START:`${i}:`${n}:`${name}") }
`$onDone  = { param(`$i,`$n,`$result) `$progressQueue.Enqueue("DONE:`${i}:`${n}:`${result}") }
$uninstallBlock
$installBlock
"@

    [void]$ps.AddScript($scriptText)

    $output      = [System.Management.Automation.PSDataCollection[PSObject]]::new()
    $asyncResult = $ps.BeginInvoke(
                       [System.Management.Automation.PSDataCollection[PSObject]]::new(),
                       $output)

    # $capturedTotalRef is a single-element array so the timer tick can update
    # the denominator when a PHASE message arrives (uninstall -> install switch).
    $capturedTotalRef            = @(if ($uninstallCount -gt 0) { $uninstallCount } else { $installCount })
    $capturedPs                  = $ps
    $capturedRs                  = $rs
    $capturedAr                  = $asyncResult
    $capturedProgressItem        = $progressItem
    $capturedProgressOverall     = $progressOverall
    $capturedStatusBar           = $statusBar
    $capturedQueue               = $progressQueue

    $timer          = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [System.TimeSpan]::FromMilliseconds(100)
    $capturedTimer  = $timer

    $timer.Add_Tick({
        $msg = $null
        while ($capturedQueue.TryDequeue([ref]$msg)) {
            # Split on ':' with a max of 3 parts so message body can contain colons
            $parts = $msg -split ':', 3
            if ($parts[0] -eq 'PHASE') {
                # Switch denominator to install phase count
                $capturedTotalRef[0] = [int]$parts[1]
            }
            elseif ($parts[0] -eq 'START') {
                $capturedProgressItem.Value    = 0
                $capturedProgressOverall.Value = if ($capturedTotalRef[0] -gt 0) {
                    [int](([int]$parts[1] - 1) / $capturedTotalRef[0] * 100)
                } else { 0 }
            }
            elseif ($parts[0] -eq 'DONE') {
                $capturedProgressItem.Value    = 100
                $capturedProgressOverall.Value = if ($capturedTotalRef[0] -gt 0) {
                    [int]([int]$parts[1] / $capturedTotalRef[0] * 100)
                } else { 100 }
            }
            elseif ($parts[0] -eq 'LOG') {
                # Forward background runspace log message to the UI panel
                $lvl = if ($parts.Count -ge 2) { $parts[1] } else { 'INFO' }
                $txt = if ($parts.Count -ge 3) { $parts[2] } else { '' }
                Write-Log -Message $txt -Level $lvl
            }
        }

        $state = $capturedPs.InvocationStateInfo.State
        if ($state -ne [System.Management.Automation.PSInvocationState]::Running) {
            $capturedTimer.Stop()
            $runspaceErrors = @()
            try {
                $capturedPs.EndInvoke($capturedAr)
            } catch {
                $runspaceErrors += $_.ToString()
            }
            foreach ($se in $capturedPs.Streams.Error) {
                $runspaceErrors += $se.ToString()
            }
            $capturedPs.Dispose()
            $capturedRs.Dispose()

            $capturedProgressItem.Value    = 100
            $capturedProgressOverall.Value = 100
            if ($runspaceErrors.Count -gt 0) {
                $capturedStatusBar.Text = 'Operation failed -- see log for details.'
                foreach ($e in $runspaceErrors) {
                    Write-Log -Message "Install error: $e" -Level ERROR
                }
            } else {
                $capturedStatusBar.Text = 'Operation complete. Rescanning...'
                Write-Log -Message 'Operation complete.' -Level OK
            }

            # Auto-rescan so the UI reflects the new installed state
            Start-BackgroundRunspace -ScriptText (Build-ScanScriptText) -OnComplete {
                param($result)
                Apply-ScanResults -ScanResults $result
                Write-Log -Message 'Rescan complete.' -Level INFO
                $window.FindName('StatusBar').Text = 'Rescan complete.'
            }
        }
    }.GetNewClosure())
    $timer.Start()
}

# -----------------------------------------------------------------------
# Helper: Build-CommitPlan
# Examines the current checkbox state and scan results to determine what
# needs to happen. Returns a PSCustomObject with:
#   ToInstall       -- app objects the user wants to install (not yet present)
#   ToUpdate        -- app objects the user wants to update
#   ToUninstall     -- installed apps the user has unchecked (to be removed)
#   OrphanedPrereqs -- installed prereqs no longer needed after the planned uninstall
#   ImplicitDeps    -- deps pulled in by Resolve-InstallPlan but not directly selected
#   FullPlan        -- full Resolve-InstallPlan result (ToInstall + ToUpdate + ImplicitDeps)
#   HasChocolatey   -- $true if any plan app uses chocolateyId
#   IsEmpty         -- $true if there is nothing to do
# -----------------------------------------------------------------------
function Build-CommitPlan {
    $checkedIds = @(
        Get-CheckBoxes |
        Where-Object { $_.IsChecked -eq $true } |
        ForEach-Object { $_.Tag }
    )

    $toInstallIds = [System.Collections.Generic.List[string]]::new()
    $toUpdateIds  = [System.Collections.Generic.List[string]]::new()

    foreach ($id in $checkedIds) {
        if ($Script:LastScanResults.ContainsKey($id)) {
            $status = $Script:LastScanResults[$id].Status
            if ($status -eq 'UpdateAvailable') {
                # Only queue an update if the user also checked the Update checkbox
                $updCbChecked = $Script:AppRowElements.ContainsKey($id) -and
                                $Script:AppRowElements[$id].UpdateCb.IsChecked -eq $true
                if ($updCbChecked) {
                    $toUpdateIds.Add($id)
                }
                # If update CB not checked: app is installed, no action needed
            } elseif ($status -eq 'NotInstalled') {
                # Only NotInstalled should be queued for install.
                $toInstallIds.Add($id)
            } elseif ($status -eq 'Failed') {
                # Failed detection should not trigger a reinstall automatically.
                Write-Log -Message "[$id] Scan status is Failed -- skipping install queue for safety." -Level WARN
            }
            # Current -> nothing to do
        } else {
            # No scan data yet -> assume not installed
            $toInstallIds.Add($id)
        }
    }

    # ToUninstall: unchecked apps that are currently installed
    $toUninstallSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($cb in (Get-CheckBoxes)) {
        if ($cb.IsChecked -ne $true) {
            $cbId = $cb.Tag
            if ($Script:LastScanResults.ContainsKey($cbId)) {
                $st = $Script:LastScanResults[$cbId].Status
                if ($st -eq 'Current' -or $st -eq 'UpdateAvailable') {
                    $toUninstallSet.Add($cbId) | Out-Null
                }
            }
        }
    }

    # Orphaned prerequisites: installed prereqs no longer needed after the
    # planned uninstall. Uses manifest dependency data + scan results.
    $allApps = Get-ManifestApps

    $allInstalledIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($key in $Script:LastScanResults.Keys) {
        $st = $Script:LastScanResults[$key].Status
        if ($st -eq 'Current' -or $st -eq 'UpdateAvailable') {
            $allInstalledIds.Add($key) | Out-Null
        }
    }

    # Apps that will remain installed after the planned uninstall
    $remainingIds = [System.Collections.Generic.HashSet[string]]::new($allInstalledIds)
    foreach ($rmId in $toUninstallSet) { $remainingIds.Remove($rmId) | Out-Null }

    # Dependency IDs still required by remaining installed apps
    $stillNeededDeps = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($app in $allApps) {
        if ($remainingIds.Contains($app.id) -and $app.dependencies) {
            foreach ($dep in $app.dependencies) {
                $stillNeededDeps.Add($dep) | Out-Null
            }
        }
    }

    # Prereqs that are installed, not in the explicit uninstall list, and
    # no longer needed by any remaining app
    $orphanedPrereqIds = [System.Collections.Generic.List[string]]::new()
    foreach ($app in $allApps) {
        if ($app.isPrerequisite -and
            $allInstalledIds.Contains($app.id) -and
            -not $toUninstallSet.Contains($app.id) -and
            -not $stillNeededDeps.Contains($app.id)) {
            $orphanedPrereqIds.Add($app.id)
        }
    }

    $combinedIds = @($toInstallIds) + @($toUpdateIds)
    $isEmpty = $combinedIds.Count -eq 0 -and $toUninstallSet.Count -eq 0 -and $orphanedPrereqIds.Count -eq 0

    if ($isEmpty) {
        return [PSCustomObject]@{
            ToInstall       = @()
            ToUpdate        = @()
            ToUninstall     = @()
            OrphanedPrereqs = @()
            ImplicitDeps    = @()
            FullPlan        = @()
            HasChocolatey   = $false
            IsEmpty         = $true
        }
    }

    $fullPlan = if ($combinedIds.Count -gt 0) {
        Resolve-InstallPlan -SelectedIds $combinedIds
    } else { @() }

    $toInstallSet = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($id in $toInstallIds) { $toInstallSet.Add($id) | Out-Null }
    $toUpdateSet  = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($id in $toUpdateIds)  { $toUpdateSet.Add($id)  | Out-Null }

    $toUninstallObjs    = @($allApps | Where-Object { $toUninstallSet.Contains($_.id) })
    $orphanedPrereqObjs = @($allApps | Where-Object { $orphanedPrereqIds.Contains($_.id) })

    $hasChocolatey = @($fullPlan | Where-Object { $_.chocolateyId }).Count -gt 0

    return [PSCustomObject]@{
        ToInstall       = @($fullPlan | Where-Object {  $toInstallSet.Contains($_.id) })
        ToUpdate        = @($fullPlan | Where-Object {  $toUpdateSet.Contains($_.id) })
        ToUninstall     = $toUninstallObjs
        OrphanedPrereqs = $orphanedPrereqObjs
        ImplicitDeps    = @($fullPlan | Where-Object { -not $toInstallSet.Contains($_.id) -and -not $toUpdateSet.Contains($_.id) })
        FullPlan        = $fullPlan
        HasChocolatey   = $hasChocolatey
        IsEmpty         = $false
    }
}

# -----------------------------------------------------------------------
# Helper: Show-CommitPreviewDialog
# Builds and shows a modal WPF dialog summarising the commit plan.
# Returns $true if the user confirmed, $false if cancelled.
# -----------------------------------------------------------------------
function Show-CommitPreviewDialog {
    param([Parameter(Mandatory)] [PSCustomObject]$Plan)

    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Commit Preview"
        Width="480" Height="520"
        Background="#1E1E1E" Foreground="WhiteSmoke"
        WindowStartupLocation="CenterOwner"
        ResizeMode="CanResizeWithGrip">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="PreviewPanel" Background="Transparent"/>
    </ScrollViewer>
    <StackPanel Grid.Row="1" Orientation="Horizontal"
                HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnConfirm" Content="Confirm" Width="90" Margin="0,0,8,0"
              Background="#0078D4" Foreground="White"
              BorderThickness="0" Padding="0,6"/>
      <Button x:Name="BtnCancel" Content="Cancel" Width="90"
              Background="#3A3A3A" Foreground="WhiteSmoke"
              BorderThickness="0" Padding="0,6"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $xmlDoc   = [System.Xml.XmlDocument]::new()
    $xmlDoc.LoadXml($dialogXaml)
    $xmlReader = [System.Xml.XmlNodeReader]::new($xmlDoc)
    $dialog    = [System.Windows.Markup.XamlReader]::Load($xmlReader)

    $panel = $dialog.FindName('PreviewPanel')
    $brush = [System.Windows.Media.BrushConverter]::new()
    $mono  = [System.Windows.Media.FontFamily]::new('Consolas')

    # Adds a colored section header + thin separator to the panel
    $addHeader = {
        param([string]$Text, [string]$Color)
        $tb = [System.Windows.Controls.TextBlock]::new()
        $tb.Text       = $Text
        $tb.FontSize   = 12
        $tb.FontWeight = [System.Windows.FontWeights]::SemiBold
        $tb.Foreground = $brush.ConvertFromString($Color)
        $tb.Margin     = [System.Windows.Thickness]::new(0, 8, 0, 2)
        $panel.Children.Add($tb) | Out-Null
        $sep = [System.Windows.Controls.Separator]::new()
        $sep.Background = $brush.ConvertFromString('#3A3A3A')
        $sep.Margin     = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $panel.Children.Add($sep) | Out-Null
    }

    # Adds a single-line or wrapping text entry to the panel
    $addLine = {
        param([string]$Text, [string]$Color = 'WhiteSmoke')
        $tb = [System.Windows.Controls.TextBlock]::new()
        $tb.Text         = $Text
        $tb.Foreground   = $brush.ConvertFromString($Color)
        $tb.FontFamily   = $mono
        $tb.FontSize     = 11
        $tb.Margin       = [System.Windows.Thickness]::new(8, 1, 0, 1)
        $tb.TextWrapping = [System.Windows.TextWrapping]::Wrap
        $panel.Children.Add($tb) | Out-Null
    }

    if ($Plan.IsEmpty) {
        & $addLine 'Nothing to do -- all selected apps are already up to date.' '#888888'
        $dialog.FindName('BtnConfirm').IsEnabled = $false
    } else {
        if ($Plan.ToInstall.Count -gt 0) {
            & $addHeader "To Install ($($Plan.ToInstall.Count))" '#5CB8FF'
            foreach ($app in $Plan.ToInstall) {
                & $addLine $app.displayName
            }
        }

        if ($Plan.ToUpdate.Count -gt 0) {
            & $addHeader "To Update ($($Plan.ToUpdate.Count))" '#5CB8FF'
            foreach ($app in $Plan.ToUpdate) {
                $entry    = $Script:LastScanResults[$app.id]
                $instVer  = if ($entry) { $entry.InstalledVersion } else { '?' }
                $availVer = if ($entry) { $entry.AvailableVersion } else { '?' }
                & $addLine "$($app.displayName)  $instVer -> $availVer"
            }
        }

        if ($Plan.ImplicitDeps.Count -gt 0) {
            & $addHeader "Also required ($($Plan.ImplicitDeps.Count))" '#888888'
            foreach ($app in $Plan.ImplicitDeps) {
                & $addLine $app.displayName '#888888'
            }
        }

        if ($Plan.ToUninstall.Count -gt 0) {
            & $addHeader "To Uninstall ($($Plan.ToUninstall.Count))" '#E74856'
            foreach ($app in $Plan.ToUninstall) {
                & $addLine $app.displayName '#E74856'
            }
        }

        if ($Plan.OrphanedPrereqs.Count -gt 0) {
            & $addHeader "Orphaned Prerequisites ($($Plan.OrphanedPrereqs.Count))" '#FFB900'
            & $addLine 'No longer needed after the planned uninstall -- will also be removed:' '#FFB900'
            foreach ($app in $Plan.OrphanedPrereqs) {
                & $addLine $app.displayName '#FFB900'
            }
        }

        if ($Plan.HasChocolatey) {
            & $addHeader 'Chocolatey Required' '#FFB900'
            & $addLine ('One or more apps require Chocolatey. ' +
                        'It will be installed automatically if not found. ' +
                        'Confirm to proceed.') '#FFB900'
        }
    }

    $capturedDialog = $dialog
    $dialog.FindName('BtnConfirm').Add_Click({
        $capturedDialog.DialogResult = $true
    }.GetNewClosure())
    $dialog.FindName('BtnCancel').Add_Click({
        $capturedDialog.DialogResult = $false
    }.GetNewClosure())

    $dialog.Owner = $window
    return ($dialog.ShowDialog() -eq $true)
}

# -----------------------------------------------------------------------
# Commit -- shows the preview dialog then runs the install/uninstall plan
# -----------------------------------------------------------------------
$window.FindName('BtnCommit').Add_Click({
    $plan = Build-CommitPlan

    if ($plan.IsEmpty) {
        Write-Log -Message 'Nothing to do -- no changes needed for selected apps.' -Level WARN
        $window.FindName('StatusBar').Text = 'Nothing to do.'
        return
    }

    $confirmed = Show-CommitPreviewDialog -Plan $plan

    if (-not $confirmed) {
        Write-Log -Message 'Commit cancelled.' -Level INFO
        return
    }

    $appsToRun       = @($plan.ToInstall) + @($plan.ToUpdate)
    $appsToUninstall = @($plan.ToUninstall) + @($plan.OrphanedPrereqs)
    $upgradeIds      = @($plan.ToUpdate | ForEach-Object { $_.id })

    $msgParts = @()
    if ($plan.ToInstall.Count + $plan.ToUpdate.Count -gt 0) {
        $msgParts += "$($plan.ToInstall.Count) to install, $($plan.ToUpdate.Count) to update"
    }
    if ($appsToUninstall.Count -gt 0) {
        $msgParts += "$($appsToUninstall.Count) to uninstall"
    }
    Write-Log -Message "Commit confirmed: $(($msgParts -join ', '))." -Level INFO

    Run-UpdateInBackground -AppsToUpdate $appsToRun -AppsToUninstall $appsToUninstall `
                           -UpgradeIds $upgradeIds -AllowChocolatey $plan.HasChocolatey
}.GetNewClosure())

# -----------------------------------------------------------------------
# Helper: Show-USBBuilderDialog
# Modal WPF dialog for configuring and launching a USB kit build.
# Returns a PSCustomObject:
#   { Confirmed: bool, SelectedApps: object[], Destination: string,
#     FormatFirst: bool, FormatFilesystem: string }
# or $null if the user cancelled.
# -----------------------------------------------------------------------
function Show-USBBuilderDialog {
    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Build USB Kit"
        Width="780" Height="560"
        Background="#1E1E1E" Foreground="WhiteSmoke"
        WindowStartupLocation="CenterOwner"
        ResizeMode="CanResizeWithGrip">
  <Window.Resources>
    <!-- Override default button template so dark Background/Foreground are always respected -->
    <Style TargetType="Button">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.8"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Opacity" Value="0.6"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="Bd" Property="Opacity" Value="0.35"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="10"/>
        <ColumnDefinition Width="280"/>
      </Grid.ColumnDefinitions>

      <!-- Left: app checklist -->
      <DockPanel Grid.Column="0">
        <TextBlock DockPanel.Dock="Top" Text="Select apps to include:"
                   FontSize="11" Foreground="#5CB8FF" FontWeight="SemiBold"
                   Margin="0,0,0,6"/>
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel x:Name="USBAppPanel"/>
        </ScrollViewer>
      </DockPanel>

      <!-- Right: options -->
      <StackPanel Grid.Column="2">

        <TextBlock Text="Destination folder:" FontSize="11"
                   Foreground="#5CB8FF" FontWeight="SemiBold" Margin="0,0,0,4"/>
        <DockPanel Margin="0,0,0,8">
          <Button x:Name="BtnBrowse" Content="Browse" DockPanel.Dock="Right"
                  Padding="8,4" Margin="6,0,0,0"
                  Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
          <TextBox x:Name="TxtDestination" Background="#2D2D2D"
                   Foreground="WhiteSmoke" BorderBrush="#555555"
                   Padding="4,3" FontFamily="Consolas" FontSize="11"/>
        </DockPanel>

        <TextBlock x:Name="LblDriveInfo" Text="No destination selected."
                   FontSize="11" Foreground="#888888"
                   FontFamily="Consolas" Margin="0,0,0,8" TextWrapping="Wrap"/>

        <StackPanel x:Name="PnlFormat" Visibility="Collapsed" Margin="0,0,0,8">
          <CheckBox x:Name="ChkFormat" Content="Format drive before building"
                    Foreground="WhiteSmoke" FontSize="11" Margin="0,0,0,4"/>
          <DockPanel>
            <TextBlock Text="Filesystem:" VerticalAlignment="Center"
                       Foreground="#888888" FontSize="11" Margin="0,0,6,0"/>
            <ComboBox x:Name="CmbFormat" FontSize="11"
                      Background="#2D2D2D" Foreground="WhiteSmoke"
                      BorderBrush="#555555" Width="80">
              <ComboBoxItem Content="exFAT" IsSelected="True"/>
              <ComboBoxItem Content="FAT32"/>
            </ComboBox>
          </DockPanel>
        </StackPanel>

        <Separator Background="#3A3A3A" Margin="0,4,0,8"/>

        <TextBlock Text="Notes:" FontSize="11" Foreground="#5CB8FF"
                   FontWeight="SemiBold" Margin="0,0,0,4"/>
        <TextBlock FontSize="10" Foreground="#888888" TextWrapping="Wrap"
                   FontFamily="Consolas">
          <Run>- Winget apps: downloaded as offline manifests.</Run>
          <LineBreak/>
          <Run>- PSGallery modules: saved locally.</Run>
          <LineBreak/>
          <Run>- Direct downloads: installer files cached.</Run>
          <LineBreak/>
          <Run>- VS Code extensions: skipped (marketplace only).</Run>
          <LineBreak/>
          <Run>- WSL / Windows Features: skipped.</Run>
        </TextBlock>

      </StackPanel>
    </Grid>

    <!-- Bottom buttons -->
    <StackPanel Grid.Row="1" Orientation="Horizontal"
                HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnUSBBuild" Content="Build USB Kit" Width="120" Margin="0,0,8,0"
              Background="#3A3A3A" Foreground="White"
              BorderThickness="0" Padding="0,6" IsEnabled="False"/>
      <Button x:Name="BtnUSBCancel" Content="Cancel" Width="90"
              Background="#3A3A3A" Foreground="WhiteSmoke"
              BorderThickness="0" Padding="0,6"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $xmlDoc    = [System.Xml.XmlDocument]::new()
    $xmlDoc.LoadXml($dialogXaml)
    $xmlReader = [System.Xml.XmlNodeReader]::new($xmlDoc)
    $dialog    = [System.Windows.Markup.XamlReader]::Load($xmlReader)

    $usbAppPanel  = $dialog.FindName('USBAppPanel')
    $txtDest      = $dialog.FindName('TxtDestination')
    $lblDriveInfo = $dialog.FindName('LblDriveInfo')
    $pnlFormat    = $dialog.FindName('PnlFormat')
    $chkFormat    = $dialog.FindName('ChkFormat')
    $cmbFormat    = $dialog.FindName('CmbFormat')
    $btnBrowse    = $dialog.FindName('BtnBrowse')
    $btnBuild     = $dialog.FindName('BtnUSBBuild')
    $btnCancel    = $dialog.FindName('BtnUSBCancel')
    $brush        = [System.Windows.Media.BrushConverter]::new()

    # Populate app checklist -- USB-eligible apps only, pre-checked per main window
    $checkedInMain = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($cb in (Get-CheckBoxes)) {
        if ($cb.IsChecked -eq $true) { $checkedInMain.Add($cb.Tag) | Out-Null }
    }

    $allApps    = Get-ManifestApps
    $usbApps    = @($allApps | Where-Object { $_.includeInUSBKit -ne $false })
    $seenCats   = [System.Collections.Generic.HashSet[string]]::new()
    $usbCheckBoxes = [System.Collections.Generic.List[object]]::new()

    foreach ($app in $usbApps) {
        $cat = $app.category
        if (-not $seenCats.Contains($cat)) {
            $seenCats.Add($cat) | Out-Null
            if ($seenCats.Count -gt 1) {
                $sp = [System.Windows.Controls.TextBlock]::new()
                $sp.Height = 4
                $usbAppPanel.Children.Add($sp) | Out-Null
            }
            $hdr = [System.Windows.Controls.TextBlock]::new()
            $hdr.Text       = $cat
            $hdr.FontSize   = 11
            $hdr.FontWeight = [System.Windows.FontWeights]::SemiBold
            $hdr.Foreground = $brush.ConvertFromString('#5CB8FF')
            $hdr.Margin     = [System.Windows.Thickness]::new(0, 4, 0, 2)
            $usbAppPanel.Children.Add($hdr) | Out-Null
        }
        $cb = [System.Windows.Controls.CheckBox]::new()
        $cb.Content   = $app.displayName
        $cb.Tag       = $app.id
        $cb.IsChecked = $checkedInMain.Contains($app.id)
        $cb.Margin    = [System.Windows.Thickness]::new(8, 1, 0, 1)
        $cb.Foreground = [System.Windows.Media.Brushes]::WhiteSmoke
        $cb.FontSize   = 11
        $cb.ToolTip    = $app.description
        $usbAppPanel.Children.Add($cb) | Out-Null
        $usbCheckBoxes.Add($cb) | Out-Null
    }

    # Helper to refresh drive info and enable/disable format option
    $capturedTxtDest   = $txtDest
    $capturedLblInfo   = $lblDriveInfo
    $capturedPnlFormat = $pnlFormat
    $capturedBtnBuild  = $btnBuild

    $refreshDriveInfo = {
        $path = $capturedTxtDest.Text.Trim()
        if (-not $path -or $path.Length -lt 2) {
            $capturedLblInfo.Text      = 'No destination selected.'
            $capturedPnlFormat.Visibility = [System.Windows.Visibility]::Collapsed
            $capturedBtnBuild.IsEnabled   = $false
            return
        }
        try {
            $driveLetter = $path[0]
            $drive       = [System.IO.DriveInfo]::new($driveLetter)
            $freeGB      = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
            $driveType   = $drive.DriveType
            $capturedLblInfo.Text = "Drive: $($drive.Name)  Type: $driveType  Free: $freeGB GB"
            $capturedPnlFormat.Visibility = if ($driveType -eq 'Removable') {
                [System.Windows.Visibility]::Visible
            } else {
                [System.Windows.Visibility]::Collapsed
            }
            $capturedBtnBuild.IsEnabled = $true
        } catch {
            $capturedLblInfo.Text         = "Could not read drive info: $_"
            $capturedPnlFormat.Visibility = [System.Windows.Visibility]::Collapsed
            $capturedBtnBuild.IsEnabled   = $false
        }
    }

    $txtDest.Add_LostFocus({ & $refreshDriveInfo }.GetNewClosure())

    # Browse button -- FolderBrowserDialog
    $capturedDialog      = $dialog
    $capturedRefresh     = $refreshDriveInfo
    $capturedTxtForBrowse = $txtDest

    $btnBrowse.Add_Click({
        Add-Type -AssemblyName System.Windows.Forms
        $fbd = [System.Windows.Forms.FolderBrowserDialog]::new()
        $fbd.Description = 'Select USB Kit Destination Folder'
        if ($capturedTxtForBrowse.Text) { $fbd.SelectedPath = $capturedTxtForBrowse.Text }
        if ($fbd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $capturedTxtForBrowse.Text = $fbd.SelectedPath
            & $capturedRefresh
        }
    }.GetNewClosure())

    # Build / Cancel
    $capturedChkFormat  = $chkFormat
    $capturedCmbFormat  = $cmbFormat
    $capturedUsbCBs     = $usbCheckBoxes
    $capturedAllApps    = $allApps

    $btnBuild.Add_Click({
        $selected = @(
            $capturedUsbCBs |
            Where-Object { $_.IsChecked -eq $true } |
            ForEach-Object {
                $cbId = $_.Tag
                $capturedAllApps | Where-Object { $_.id -eq $cbId } | Select-Object -First 1
            }
        )
        if ($selected.Count -eq 0) {
            [System.Windows.MessageBox]::Show(
                'No apps selected.',
                'Build USB Kit',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }

        $dest       = $capturedTxtDest.Text.Trim()
        $formatFirst = $capturedChkFormat.IsChecked -eq $true
        $filesystem  = if ($capturedCmbFormat.SelectedItem) {
            $capturedCmbFormat.SelectedItem.Content
        } else { 'exFAT' }

        if ($formatFirst) {
            $confirm = [System.Windows.MessageBox]::Show(
                "WARNING: This will format the drive at $dest and erase all data. Continue?",
                'Format Drive',
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)
            if ($confirm -ne [System.Windows.MessageBoxResult]::Yes) { return }
        }

        $capturedDialog.Tag = [PSCustomObject]@{
            Confirmed      = $true
            SelectedApps   = $selected
            Destination    = $dest
            FormatFirst    = $formatFirst
            FormatFilesystem = $filesystem
        }
        $capturedDialog.DialogResult = $true
    }.GetNewClosure())

    $btnCancel.Add_Click({
        $capturedDialog.DialogResult = $false
    }.GetNewClosure())

    $dialog.Owner = $window
    $ok = $dialog.ShowDialog()

    if ($ok -eq $true -and $dialog.Tag) {
        return $dialog.Tag
    }
    return $null
}

# -----------------------------------------------------------------------
# Helper: Run-USBBuildInBackground
# Runs Invoke-USBBuild in a background runspace, polling with a
# DispatcherTimer for progress updates. Optionally formats the drive first.
# -----------------------------------------------------------------------
function Run-USBBuildInBackground {
    param(
        [object[]]$SelectedApps,
        [string]$Destination,
        [bool]$FormatFirst       = $false,
        [string]$FormatFilesystem = 'exFAT'
    )

    $progressItem    = $window.FindName('ProgressItem')
    $progressOverall = $window.FindName('ProgressOverall')
    $statusBar       = $window.FindName('StatusBar')

    $progressItem.Value    = 0
    $progressOverall.Value = 0
    $statusBar.Text        = "Building USB kit ($($SelectedApps.Count) apps eligible)..."

    # Optional drive format -- runs synchronously on UI thread before the build
    if ($FormatFirst) {
        try {
            $driveLetter = $Destination[0]
            Write-Log -Message "Formatting $driveLetter`: as $FormatFilesystem..." -Level INFO
            Format-Volume -DriveLetter $driveLetter -FileSystem $FormatFilesystem `
                          -Force -Confirm:$false | Out-Null
            Write-Log -Message "Drive formatted as $FormatFilesystem." -Level OK
        } catch {
            Write-Log -Message "Format failed: $_ -- build aborted." -Level ERROR
            $statusBar.Text = 'Format failed -- build aborted.'
            return
        }
    }

    $progressQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    $lp   = "$PSScriptRoot\Logger.ps1"
    $mp   = "$PSScriptRoot\ManifestManager.ps1"
    $ep   = "$PSScriptRoot\InstallEngine.ps1"
    $cp   = "$PSScriptRoot\UpdateChecker.ps1"
    $ub   = "$PSScriptRoot\USBBuilder.ps1"
    $mf   = $Script:ActiveManifestPath -replace "'", "''"
    $dest = $Destination
    $idList = ($SelectedApps | ForEach-Object { "'" + $_.id + "'" }) -join ','
    $total  = $SelectedApps.Count

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('progressQueue', $progressQueue)

    $scriptText = @"
. '$lp'
. '$mp'
. '$ep'
. '$cp'
. '$ub'
Initialize-Logger
Initialize-ManifestManager -ManifestPath '$mf'
`$allApps     = Get-ManifestApps
`$selectedIds = @($idList)
`$apps        = @(`$allApps | Where-Object { `$selectedIds -contains `$_.id })
`$onStart = { param(`$i,`$n,`$name)   `$progressQueue.Enqueue("START:`${i}:`${n}:`${name}") }
`$onDone  = { param(`$i,`$n,`$result) `$progressQueue.Enqueue("DONE:`${i}:`${n}:`${result}") }
Invoke-USBBuild -Apps `$apps -Destination '$dest' -OnItemStart `$onStart -OnItemDone `$onDone
"@

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript($scriptText)

    $output      = [System.Management.Automation.PSDataCollection[PSObject]]::new()
    $asyncResult = $ps.BeginInvoke(
                       [System.Management.Automation.PSDataCollection[PSObject]]::new(),
                       $output)

    $capturedTotal           = $total
    $capturedPs              = $ps
    $capturedRs              = $rs
    $capturedAr              = $asyncResult
    $capturedProgressItem    = $progressItem
    $capturedProgressOverall = $progressOverall
    $capturedStatusBar       = $statusBar
    $capturedQueue           = $progressQueue

    $timer          = [System.Windows.Threading.DispatcherTimer]::new()
    $timer.Interval = [System.TimeSpan]::FromMilliseconds(100)
    $capturedTimer  = $timer

    $timer.Add_Tick({
        $msg = $null
        while ($capturedQueue.TryDequeue([ref]$msg)) {
            $parts = $msg -split ':'
            if ($parts[0] -eq 'START') {
                $capturedProgressItem.Value    = 0
                $capturedProgressOverall.Value = if ($capturedTotal -gt 0) {
                    [int](([int]$parts[1] - 1) / $capturedTotal * 100)
                } else { 0 }
            } elseif ($parts[0] -eq 'DONE') {
                $capturedProgressItem.Value    = 100
                $capturedProgressOverall.Value = if ($capturedTotal -gt 0) {
                    [int]([int]$parts[1] / $capturedTotal * 100)
                } else { 100 }
            }
        }

        $state = $capturedPs.InvocationStateInfo.State
        if ($state -ne [System.Management.Automation.PSInvocationState]::Running) {
            $capturedTimer.Stop()
            try { $capturedPs.EndInvoke($capturedAr) } catch { Write-Log -Message "EndInvoke error (USB runspace): $_" -Level DEBUG }
            $capturedPs.Dispose()
            $capturedRs.Dispose()
            $capturedProgressItem.Value    = 100
            $capturedProgressOverall.Value = 100
            $capturedStatusBar.Text        = 'USB kit build complete.'
            Write-Log -Message 'USB kit build complete.' -Level OK
        }
    }.GetNewClosure())
    $timer.Start()
}

# -----------------------------------------------------------------------
# Build USB Kit -- shows the USB builder dialog then runs the build
# -----------------------------------------------------------------------
$window.FindName('BtnBuildUsb').Add_Click({
    $plan = Show-USBBuilderDialog

    if (-not $plan -or -not $plan.Confirmed) {
        Write-Log -Message 'USB kit build cancelled.' -Level INFO
        return
    }

    Write-Log -Message "USB kit build started: $($plan.SelectedApps.Count) apps -> $($plan.Destination)" -Level INFO

    Run-USBBuildInBackground `
        -SelectedApps     $plan.SelectedApps `
        -Destination      $plan.Destination `
        -FormatFirst      $plan.FormatFirst `
        -FormatFilesystem $plan.FormatFilesystem
}.GetNewClosure())

# -----------------------------------------------------------------------
# Helper: Search-WingetApps
# Runs winget search and returns an array of PSCustomObjects with
# Name, Id, Version fields. Returns @() on error or no results.
# -----------------------------------------------------------------------
function Search-WingetApps {
    param([Parameter(Mandatory)] [string]$Query)

    try {
        $raw = @(& winget search --name $Query --accept-source-agreements 2>$null)

        $headerIdx = -1
        $nameCol   = -1
        $idCol     = -1
        $verCol    = -1

        for ($i = 0; $i -lt $raw.Count; $i++) {
            $line = $raw[$i]
            if ($line -match '\bId\b' -and $line -match '\bName\b') {
                $headerIdx = $i
                $nameCol   = $line.IndexOf('Name',    [System.StringComparison]::OrdinalIgnoreCase)
                $idCol     = $line.IndexOf('Id',      [System.StringComparison]::OrdinalIgnoreCase)
                $verCol    = $line.IndexOf('Version', [System.StringComparison]::OrdinalIgnoreCase)
                break
            }
        }

        if ($headerIdx -lt 0 -or $idCol -lt 0) { return @() }

        $results = [System.Collections.Generic.List[PSCustomObject]]::new()

        for ($i = $headerIdx + 1; $i -lt $raw.Count; $i++) {
            $line = $raw[$i]
            if ($line -match '^[-\s]+$') { continue }
            if ($line.Length -le $idCol)  { continue }

            $name = if ($nameCol -ge 0 -and $idCol -gt $nameCol) {
                $line.Substring($nameCol, [Math]::Min($idCol - $nameCol, $line.Length - $nameCol)).Trim()
            } else { '' }

            $id = if ($verCol -gt $idCol) {
                $line.Substring($idCol, [Math]::Min($verCol - $idCol, $line.Length - $idCol)).Trim()
            } elseif ($line.Length -gt $idCol) {
                ($line.Substring($idCol).Trim() -split '\s+')[0]
            } else { '' }

            $ver = if ($verCol -ge 0 -and $line.Length -gt $verCol) {
                ($line.Substring($verCol).Trim() -split '\s+')[0]
            } else { '' }

            if ($id -and $id -notmatch '^-') {
                $results.Add([PSCustomObject]@{ Name = $name; Id = $id; Version = $ver })
            }
        }

        return $results.ToArray()
    } catch {
        return @()
    }
}

# -----------------------------------------------------------------------
# Helper: Save-UserManifest
# Merges NewApp into %APPDATA%\Loadout\user-manifest.json.
# Replaces any existing entry with the same id; preserves all others.
# -----------------------------------------------------------------------
function Save-UserManifest {
    param([Parameter(Mandatory)] [object]$NewApp)

    $userManifestPath = Join-Path $env:APPDATA 'Loadout\user-manifest.json'
    $dir = Split-Path $userManifestPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $existingApps = @()
    if (Test-Path $userManifestPath) {
        try {
            $raw  = Get-Content $userManifestPath -Raw -Encoding UTF8
            $data = $raw | ConvertFrom-Json
            $existingApps = @($data.apps | Where-Object { $_.id -ne $NewApp.id })
        } catch {
            Write-Log -Message "Could not read existing user-manifest.json -- will overwrite: $_" -Level WARN
        }
    }

    $manifest = [PSCustomObject]@{ apps = $existingApps + @($NewApp) }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $userManifestPath -Encoding UTF8
}

# -----------------------------------------------------------------------
# Helper: Add-CustomApp
# Saves NewApp to user-manifest.json, re-initializes ManifestManager,
# and rebuilds the app checklist, pre-checking the new app.
# -----------------------------------------------------------------------
function Add-CustomApp {
    param([Parameter(Mandatory)] [object]$AppObj)

    Save-UserManifest -NewApp $AppObj
    Write-Log -Message "Custom app saved: $($AppObj.displayName) (id: $($AppObj.id))" -Level OK

    # Preserve current checked state and pre-check the new app
    $checkedIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($cb in (Get-CheckBoxes)) {
        if ($cb.IsChecked -eq $true) { $checkedIds.Add($cb.Tag) | Out-Null }
    }
    $checkedIds.Add($AppObj.id) | Out-Null

    # Reload manifest to pick up the new user app
    if ($ManifestPath) {
        Initialize-ManifestManager -ManifestPath $ManifestPath
    } else {
        Initialize-ManifestManager
    }

    Rebuild-AppListPanel -PreCheckedIds $checkedIds
    $window.FindName('StatusBar').Text = "Custom app added: $($AppObj.displayName)"
}

# -----------------------------------------------------------------------
# Helper: Export-LoadoutConfig
# Saves current checkbox selections and custom apps to a portable JSON file.
# -----------------------------------------------------------------------
function Export-LoadoutConfig {
    Add-Type -AssemblyName System.Windows.Forms
    $sfd          = [System.Windows.Forms.SaveFileDialog]::new()
    $sfd.Title    = 'Export Loadout Config'
    $sfd.Filter   = 'JSON Config (*.json)|*.json'
    $sfd.FileName = 'loadout-config.json'
    if ($sfd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $checkedIds = @(Get-CheckBoxes |
        Where-Object { $_.IsChecked -eq $true } |
        ForEach-Object { $_.Tag })

    $userManifestPath = Join-Path $env:APPDATA 'Loadout\user-manifest.json'
    $customApps = @()
    if (Test-Path $userManifestPath) {
        try {
            $data       = Get-Content $userManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $customApps = @($data.apps)
        } catch { Write-Log -Message "Could not read user-manifest.json for export: $_" -Level WARN }
    }

    $config = [PSCustomObject]@{
        exportedBy  = 'Loadout'
        selectedIds = $checkedIds
        customApps  = $customApps
    }
    $config | ConvertTo-Json -Depth 10 | Set-Content -Path $sfd.FileName -Encoding UTF8
    Write-Log -Message "Config exported: $($checkedIds.Count) selected, $($customApps.Count) custom app(s) -> $($sfd.FileName)" -Level OK
}

# -----------------------------------------------------------------------
# Helper: Import-LoadoutConfig
# Loads a portable JSON config, merges custom apps into user-manifest.json,
# re-initializes ManifestManager, and restores checkbox selections.
# -----------------------------------------------------------------------
function Import-LoadoutConfig {
    Add-Type -AssemblyName System.Windows.Forms
    $ofd        = [System.Windows.Forms.OpenFileDialog]::new()
    $ofd.Title  = 'Import Loadout Config'
    $ofd.Filter = 'JSON Config (*.json)|*.json'
    if ($ofd.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return }

    $config = $null
    try {
        $config = Get-Content $ofd.FileName -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Log -Message "Failed to parse config file: $_" -Level ERROR
        return
    }

    # Merge imported custom apps into user-manifest.json
    $customApps = if ($config.customApps) { @($config.customApps) } else { @() }
    if ($customApps.Count -gt 0) {
        $userManifestPath = Join-Path $env:APPDATA 'Loadout\user-manifest.json'
        $dir = Split-Path $userManifestPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

        $existingApps = @()
        if (Test-Path $userManifestPath) {
            try {
                $existing   = Get-Content $userManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $importIds  = [System.Collections.Generic.HashSet[string]]::new()
                foreach ($a in $customApps) { $importIds.Add($a.id) | Out-Null }
                $existingApps = @($existing.apps | Where-Object { -not $importIds.Contains($_.id) })
            } catch { Write-Log -Message "Could not read existing user-manifest.json for import dedup: $_" -Level WARN }
        }

        $merged = [PSCustomObject]@{ apps = $existingApps + $customApps }
        $merged | ConvertTo-Json -Depth 10 | Set-Content -Path $userManifestPath -Encoding UTF8
    }

    # Reload manifest
    if ($ManifestPath) {
        Initialize-ManifestManager -ManifestPath $ManifestPath
    } else {
        Initialize-ManifestManager
    }

    # Restore selections
    $selectedSet = [System.Collections.Generic.HashSet[string]]::new()
    if ($config.selectedIds) {
        foreach ($id in $config.selectedIds) { $selectedSet.Add($id) | Out-Null }
    }

    Rebuild-AppListPanel -PreCheckedIds $selectedSet
    Write-Log -Message "Config imported: $($selectedSet.Count) selected, $($customApps.Count) custom app(s)." -Level OK
    $window.FindName('StatusBar').Text = "Config imported: $($selectedSet.Count) selected, $($customApps.Count) custom."
}

# -----------------------------------------------------------------------
# Helper: Show-CustomAppDialog
# Modal WPF form for adding a custom app entry. Supports winget search
# to auto-fill the winget ID. Returns the constructed app PSCustomObject
# if the user confirmed, or $null if cancelled.
# -----------------------------------------------------------------------
function Show-CustomAppDialog {
    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Add Custom App"
        Width="500" Height="560"
        MinHeight="420" MinWidth="400"
        Background="#1E1E1E" Foreground="WhiteSmoke"
        WindowStartupLocation="CenterOwner"
        ResizeMode="CanResizeWithGrip">
  <Window.Resources>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="WhiteSmoke"/>
      <Setter Property="Background" Value="#2D2D2D"/>
      <Setter Property="BorderBrush" Value="#555555"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <Border x:Name="border"
                      Background="{TemplateBinding Background}"
                      BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="{TemplateBinding BorderThickness}"/>
              <ToggleButton x:Name="toggleButton"
                            Background="Transparent" BorderThickness="0"
                            IsChecked="{Binding Path=IsDropDownOpen,Mode=TwoWay,RelativeSource={RelativeSource TemplatedParent}}"
                            ClickMode="Press">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Grid>
                      <Grid.ColumnDefinitions>
                        <ColumnDefinition/>
                        <ColumnDefinition Width="18"/>
                      </Grid.ColumnDefinitions>
                      <Border Background="Transparent" Grid.ColumnSpan="2"/>
                      <Path Grid.Column="1" Data="M 0 0 L 5 5 L 10 0"
                            Stroke="WhiteSmoke" StrokeThickness="1.5"
                            HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Grid>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter x:Name="contentSite"
                                Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                Margin="4,3,22,3" IsHitTestVisible="False"
                                VerticalAlignment="Center"
                                TextBlock.Foreground="{TemplateBinding Foreground}"/>
              <TextBox x:Name="PART_EditableTextBox"
                       Background="Transparent"
                       Foreground="{TemplateBinding Foreground}"
                       BorderThickness="0"
                       Margin="4,2,22,2"
                       Visibility="Hidden"
                       IsReadOnly="{TemplateBinding IsReadOnly}"/>
              <Popup x:Name="PART_Popup"
                     IsOpen="{TemplateBinding IsDropDownOpen}"
                     Placement="Bottom" AllowsTransparency="False"
                     Focusable="False">
                <Border Background="#2D2D2D" BorderBrush="#555555" BorderThickness="1"
                        MaxHeight="200">
                  <ScrollViewer>
                    <ItemsPresenter/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEditable" Value="True">
                <Setter TargetName="contentSite" Property="Visibility" Value="Hidden"/>
                <Setter TargetName="PART_EditableTextBox" Property="Visibility" Value="Visible"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="WhiteSmoke"/>
      <Setter Property="Background" Value="#2D2D2D"/>
      <Setter Property="Padding" Value="4,3"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border Background="{TemplateBinding Background}"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter TextBlock.Foreground="{TemplateBinding Foreground}"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter Property="Background" Value="#3A3A3A"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter Property="Background" Value="#404040"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>
  <DockPanel Margin="16">
    <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal"
                HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnSaveApp"   Content="Save"   Width="90" Margin="0,0,8,0"
              Background="#0078D4" Foreground="White"
              BorderThickness="0" Padding="0,6"/>
      <Button x:Name="BtnCancelApp" Content="Cancel" Width="90"
              Background="#3A3A3A" Foreground="WhiteSmoke"
              BorderThickness="0" Padding="0,6"/>
    </StackPanel>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <StackPanel>
        <TextBlock Text="Display Name *" FontSize="11" Foreground="#5CB8FF"
                   FontWeight="SemiBold" Margin="0,0,0,3"/>
        <TextBox x:Name="TxtDisplayName" Margin="0,0,0,10"
                 Background="#2D2D2D" Foreground="WhiteSmoke"
                 BorderBrush="#555555" Padding="4,3"/>
        <TextBlock Text="Description" FontSize="11" Foreground="#5CB8FF"
                   FontWeight="SemiBold" Margin="0,0,0,3"/>
        <TextBox x:Name="TxtDescription" Margin="0,0,0,10"
                 Background="#2D2D2D" Foreground="WhiteSmoke"
                 BorderBrush="#555555" Padding="4,3"/>
        <TextBlock Text="Category *" FontSize="11" Foreground="#5CB8FF"
                   FontWeight="SemiBold" Margin="0,0,0,3"/>
        <ComboBox x:Name="CmbCategory" IsEditable="True" Margin="0,0,0,10"
                  Background="#2D2D2D" Foreground="WhiteSmoke"
                  BorderBrush="#555555"/>
        <StackPanel x:Name="PnlMethodSelector">
          <TextBlock Text="Install Method *" FontSize="11" Foreground="#5CB8FF"
                     FontWeight="SemiBold" Margin="0,0,0,3"/>
          <ComboBox x:Name="CmbMethod" Margin="0,0,0,10"
                    Background="#2D2D2D" Foreground="WhiteSmoke"
                    BorderBrush="#555555">
            <ComboBoxItem Content="Winget" IsSelected="True"/>
            <ComboBoxItem Content="PSGallery"/>
            <ComboBoxItem Content="DirectDownload"/>
            <ComboBoxItem Content="Chocolatey"/>
            <ComboBoxItem Content="WSL Distro"/>
          </ComboBox>
        </StackPanel>
        <TextBlock x:Name="LblPrimaryId" Text="Winget ID *" FontSize="11"
                   Foreground="#5CB8FF" FontWeight="SemiBold" Margin="0,0,0,3"/>
        <TextBox x:Name="TxtPrimaryId" Margin="0,0,0,6"
                 Background="#2D2D2D" Foreground="WhiteSmoke"
                 BorderBrush="#555555" Padding="4,3"
                 FontFamily="Consolas" FontSize="11"/>
        <StackPanel x:Name="PnlWingetSearch" Margin="0,0,0,10">
          <DockPanel>
            <Button x:Name="BtnSearchWinget" Content="Search" DockPanel.Dock="Right"
                    Padding="10,4" Margin="6,0,0,0"
                    Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
            <TextBox x:Name="TxtSearch" Background="#2D2D2D" Foreground="WhiteSmoke"
                     BorderBrush="#555555" Padding="4,3"
                     FontFamily="Consolas" FontSize="11"/>
          </DockPanel>
          <TextBlock Text="Type a name and click Search to find the Winget ID."
                     FontSize="10" Foreground="#888888" Margin="0,3,0,0"/>
        </StackPanel>
        <StackPanel x:Name="PnlSearchResults" Visibility="Collapsed" Margin="0,0,0,10">
          <TextBlock Text="Search results -- click to select:" FontSize="11"
                     Foreground="#5CB8FF" FontWeight="SemiBold" Margin="0,0,0,3"/>
          <ListBox x:Name="LstSearchResults" Height="120"
                   Background="#2D2D2D" Foreground="WhiteSmoke"
                   BorderBrush="#555555" FontFamily="Consolas" FontSize="11"
                   ScrollViewer.HorizontalScrollBarVisibility="Auto"/>
        </StackPanel>
        <StackPanel x:Name="PnlSilentArgs" Visibility="Collapsed" Margin="0,0,0,10">
          <TextBlock Text="Silent Args" FontSize="11" Foreground="#5CB8FF"
                     FontWeight="SemiBold" Margin="0,0,0,3"/>
          <TextBox x:Name="TxtSilentArgs" Background="#2D2D2D" Foreground="WhiteSmoke"
                   BorderBrush="#555555" Padding="4,3"
                   FontFamily="Consolas" FontSize="11"/>
        </StackPanel>
        <StackPanel x:Name="PnlWslNote" Visibility="Collapsed" Margin="0,0,0,10">
          <Border Background="#2D2D2D" BorderBrush="#555555" BorderThickness="1"
                  Padding="8,6" CornerRadius="2">
            <TextBlock FontSize="10" Foreground="#888888" TextWrapping="Wrap"
                       FontFamily="Consolas">
              <Run>Installs using: wsl --install -d [Distro Name] --no-launch</Run>
              <LineBreak/>
              <Run>Run 'wsl --list --online' to see available distro names.</Run>
            </TextBlock>
          </Border>
        </StackPanel>
      </StackPanel>
    </ScrollViewer>
  </DockPanel>
</Window>
'@

    $xmlDoc   = [System.Xml.XmlDocument]::new()
    $xmlDoc.LoadXml($dialogXaml)
    $xmlReader = [System.Xml.XmlNodeReader]::new($xmlDoc)
    $dialog    = [System.Windows.Markup.XamlReader]::Load($xmlReader)

    $txtDisplayName   = $dialog.FindName('TxtDisplayName')
    $txtDescription   = $dialog.FindName('TxtDescription')
    $cmbCategory      = $dialog.FindName('CmbCategory')
    $cmbMethod        = $dialog.FindName('CmbMethod')
    $lblPrimaryId     = $dialog.FindName('LblPrimaryId')
    $txtPrimaryId     = $dialog.FindName('TxtPrimaryId')
    $pnlWingetSearch  = $dialog.FindName('PnlWingetSearch')
    $txtSearch        = $dialog.FindName('TxtSearch')
    $btnSearchWinget  = $dialog.FindName('BtnSearchWinget')
    $pnlSearchResults = $dialog.FindName('PnlSearchResults')
    $lstSearchResults = $dialog.FindName('LstSearchResults')
    $pnlMethodSelector = $dialog.FindName('PnlMethodSelector')
    $pnlSilentArgs    = $dialog.FindName('PnlSilentArgs')
    $txtSilentArgs    = $dialog.FindName('TxtSilentArgs')
    $pnlWslNote       = $dialog.FindName('PnlWslNote')
    $btnSaveApp       = $dialog.FindName('BtnSaveApp')
    $btnCancelApp     = $dialog.FindName('BtnCancelApp')

    # Populate category dropdown with existing manifest categories
    foreach ($cat in @(Get-ManifestApps | Select-Object -ExpandProperty category -Unique)) {
        [void]$cmbCategory.Items.Add($cat)
    }
    if ($cmbCategory.Items.Count -gt 0) { $cmbCategory.SelectedIndex = 0 }

    # Method selection handler -- updates label and shows/hides sub-panels
    $capturedCmbMethod          = $cmbMethod
    $capturedLblPrimaryId       = $lblPrimaryId
    $capturedPnlMethodSelector  = $pnlMethodSelector
    $capturedPnlWingetSearch    = $pnlWingetSearch
    $capturedPnlSilentArgs      = $pnlSilentArgs
    $capturedPnlSearchResults   = $pnlSearchResults
    $capturedPnlWslNote         = $pnlWslNote

    $updateMethodUI = {
        $m = $capturedCmbMethod.SelectedItem.Content
        $capturedLblPrimaryId.Text = switch ($m) {
            'Winget'         { 'Winget ID *' }
            'PSGallery'      { 'Module Name *' }
            'DirectDownload' { 'Installer URL *' }
            'Chocolatey'     { 'Chocolatey ID *' }
            'WSL Distro'     { 'Distro Name *' }
            default          { 'ID *' }
        }
        $capturedPnlMethodSelector.Visibility = [System.Windows.Visibility]::Visible
        $capturedPnlWingetSearch.Visibility = if ($m -eq 'Winget') {
            [System.Windows.Visibility]::Visible
        } else { [System.Windows.Visibility]::Collapsed }
        $capturedPnlSilentArgs.Visibility = if ($m -eq 'DirectDownload') {
            [System.Windows.Visibility]::Visible
        } else { [System.Windows.Visibility]::Collapsed }
        $capturedPnlWslNote.Visibility = if ($m -eq 'WSL Distro') {
            [System.Windows.Visibility]::Visible
        } else { [System.Windows.Visibility]::Collapsed }
        $capturedPnlSearchResults.Visibility = [System.Windows.Visibility]::Collapsed
    }

    $capturedUpdateMethodUI = $updateMethodUI
    $cmbMethod.Add_SelectionChanged({ & $capturedUpdateMethodUI }.GetNewClosure())

    # Winget search button + Enter key in TxtSearch
    $capturedTxtSearch        = $txtSearch
    $capturedTxtPrimaryId     = $txtPrimaryId
    $capturedLstSearchResults = $lstSearchResults
    $capturedPnlSrVisible     = $pnlSearchResults
    $capturedBtnSearch        = $btnSearchWinget

    $btnSearchWinget.Add_Click({
        $query = $capturedTxtSearch.Text.Trim()
        if (-not $query) { return }

        $capturedLstSearchResults.Items.Clear()
        $capturedLstSearchResults.Tag = $null
        $results = Search-WingetApps -Query $query

        if ($results.Count -eq 0) {
            $noItem = [System.Windows.Controls.ListBoxItem]::new()
            $noItem.Content = '(no results)'
            $noItem.IsEnabled = $false
            [void]$capturedLstSearchResults.Items.Add($noItem)
        } else {
            foreach ($r in $results) {
                $li = [System.Windows.Controls.ListBoxItem]::new()
                $li.Content = "$($r.Name)  ($($r.Id))"
                $li.Tag = $r.Id
                [void]$capturedLstSearchResults.Items.Add($li)
            }
            $capturedLstSearchResults.Tag = $results
        }
        $capturedPnlSrVisible.Visibility = [System.Windows.Visibility]::Visible
    }.GetNewClosure())

    $txtSearch.Add_KeyDown({
        param($s, $e)
        $null = $s  # sender unused; event args in $e
        if ($e.Key -eq [System.Windows.Input.Key]::Return) {
            $capturedBtnSearch.RaiseEvent(
                [System.Windows.RoutedEventArgs]::new(
                    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent))
        }
    }.GetNewClosure())

    # Clicking a search result auto-fills the ID box
    $lstSearchResults.Add_SelectionChanged({
        $item = $capturedLstSearchResults.SelectedItem
        if ($null -ne $item -and $null -ne $item.Tag) {
            $capturedTxtPrimaryId.Text = $item.Tag
        }
    }.GetNewClosure())

    # Save button -- validates, builds app object, closes with result
    $capturedDialog         = $dialog
    $capturedTxtDisplayName = $txtDisplayName
    $capturedTxtDescription = $txtDescription
    $capturedCmbCat         = $cmbCategory
    $capturedCmbMeth        = $cmbMethod
    $capturedTxtPrimary     = $txtPrimaryId
    $capturedTxtSilent      = $txtSilentArgs

    $btnSaveApp.Add_Click({
        $displayName = $capturedTxtDisplayName.Text.Trim()
        $method      = $capturedCmbMeth.SelectedItem.Content
        $primaryId   = $capturedTxtPrimary.Text.Trim()

        if (-not $displayName) {
            [System.Windows.MessageBox]::Show(
                'Display Name is required.',
                'Validation',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }
        if (-not $primaryId) {
            [System.Windows.MessageBox]::Show(
                'ID or URL is required.',
                'Validation',
                [System.Windows.MessageBoxButton]::OK,
                [System.Windows.MessageBoxImage]::Warning) | Out-Null
            return
        }

        $category = $capturedCmbCat.Text.Trim()
        if (-not $category) { $category = 'Custom' }

        # Sanitize the display name into a unique-enough ID
        $sanitized = $displayName.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-'
        $sanitized = $sanitized.Trim('-')
        $appId     = "custom-$sanitized"

        $appObj = [PSCustomObject]@{
            id               = $appId
            displayName      = $displayName
            description      = $capturedTxtDescription.Text.Trim()
            category         = $category
            isPrerequisite   = $false
            dependencies     = @()
            requiresReboot   = $false
            requiresElevation = $false
            includeInUSBKit  = $true
        }

        switch ($method) {
            'Winget' {
                $appObj | Add-Member -NotePropertyName wingetId -NotePropertyValue $primaryId
            }
            'PSGallery' {
                $appObj | Add-Member -NotePropertyName psGalleryModule -NotePropertyValue $primaryId
            }
            'DirectDownload' {
                $dd = [PSCustomObject]@{ url = $primaryId }
                $appObj | Add-Member -NotePropertyName directDownload -NotePropertyValue $dd
                $silentArgs = $capturedTxtSilent.Text.Trim()
                if ($silentArgs) {
                    $appObj | Add-Member -NotePropertyName silentArgs -NotePropertyValue $silentArgs
                }
            }
            'Chocolatey' {
                $appObj | Add-Member -NotePropertyName chocolateyId -NotePropertyValue $primaryId
            }
            'WSL Distro' {
                $appObj | Add-Member -NotePropertyName wslDistroName    -NotePropertyValue $primaryId
                $appObj | Add-Member -NotePropertyName requiresUserSetup -NotePropertyValue $true
            }
        }

        $capturedDialog.Tag          = $appObj
        $capturedDialog.DialogResult = $true
    }.GetNewClosure())

    $btnCancelApp.Add_Click({
        $capturedDialog.DialogResult = $false
    }.GetNewClosure())

    $dialog.Owner = $window
    $ok = $dialog.ShowDialog()

    if ($ok -eq $true -and $dialog.Tag) {
        return $dialog.Tag
    }
    return $null
}

# -----------------------------------------------------------------------
# Add Custom App -- opens the dialog; saves and refreshes UI on confirm
# -----------------------------------------------------------------------
$window.FindName('BtnAddCustomApp').Add_Click({
    $appObj = Show-CustomAppDialog
    if ($null -ne $appObj) {
        Add-CustomApp -AppObj $appObj
    }
}.GetNewClosure())

# -----------------------------------------------------------------------
# Select / Deselect All Updates -- toggle update checkboxes
# -----------------------------------------------------------------------
$window.FindName('BtnSelectAllUpdates').Add_Click({
    foreach ($rowEntry in $Script:AppRowElements.Values) {
        if ($rowEntry.UpdateCb.IsEnabled) {
            $rowEntry.UpdateCb.IsChecked = $true
        }
    }
}.GetNewClosure())

$window.FindName('BtnDeselectAllUpdates').Add_Click({
    foreach ($rowEntry in $Script:AppRowElements.Values) {
        $rowEntry.UpdateCb.IsChecked = $false
    }
}.GetNewClosure())

# -----------------------------------------------------------------------
# Helper: Show-CustomAppManagerDialog
# Lists all entries in user-manifest.json with a Delete button for each.
# Deletes remove the entry, re-initialize ManifestManager, and rebuild
# the app checklist.
# -----------------------------------------------------------------------
function Show-CustomAppManagerDialog {
    $userManifestPath = Join-Path $env:APPDATA 'Loadout\user-manifest.json'
    $customApps = @()
    if (Test-Path $userManifestPath) {
        try {
            $data = Get-Content $userManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $customApps = @($data.apps)
        } catch {
            Write-Log -Message "Could not read user-manifest.json: $_" -Level WARN
        }
    }
    if ($customApps.Count -eq 0) {
        Write-Log -Message 'No custom apps defined.' -Level INFO
        $window.FindName('StatusBar').Text = 'No custom apps to manage.'
        return
    }

    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Manage Custom Apps"
        Width="600" Height="420"
        Background="#1E1E1E" Foreground="WhiteSmoke"
        WindowStartupLocation="CenterOwner"
        ResizeMode="CanResizeWithGrip">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Custom Apps" FontSize="14" FontWeight="SemiBold"
               Foreground="#5CB8FF" Margin="0,0,0,10"/>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="CustomAppListPanel"/>
    </ScrollViewer>
    <Button Grid.Row="2" x:Name="BtnClose" Content="Close"
            HorizontalAlignment="Right" Padding="14,4" Margin="0,10,0,0"/>
  </Grid>
</Window>
'@

    $xd = [System.Xml.XmlDocument]::new()
    $xd.LoadXml($dialogXaml)
    $xr     = [System.Xml.XmlNodeReader]::new($xd)
    $dialog = [System.Windows.Markup.XamlReader]::Load($xr)
    $dialog.Owner = $window

    $listPanel = $dialog.FindName('CustomAppListPanel')
    $brush     = [System.Windows.Media.BrushConverter]::new()

    foreach ($app in $customApps) {
        $row            = [System.Windows.Controls.DockPanel]::new()
        $row.Margin     = [System.Windows.Thickness]::new(0, 2, 0, 2)
        $row.Background = $brush.ConvertFromString('#252525')

        $delBtn                  = [System.Windows.Controls.Button]::new()
        $delBtn.Content          = 'Delete'
        $delBtn.Padding          = [System.Windows.Thickness]::new(10, 2, 10, 2)
        $delBtn.Background       = $brush.ConvertFromString('#C42B1C')
        $delBtn.Foreground       = [System.Windows.Media.Brushes]::WhiteSmoke
        $delBtn.BorderThickness  = [System.Windows.Thickness]::new(0)
        $delBtn.Margin           = [System.Windows.Thickness]::new(6, 4, 6, 4)
        $delBtn.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        [System.Windows.Controls.DockPanel]::SetDock($delBtn, [System.Windows.Controls.Dock]::Right)
        $row.Children.Add($delBtn) | Out-Null

        $nameTb                   = [System.Windows.Controls.TextBlock]::new()
        $nameTb.Text              = "$($app.displayName)  [$($app.id)]"
        $nameTb.Foreground        = [System.Windows.Media.Brushes]::WhiteSmoke
        $nameTb.FontSize          = 12
        $nameTb.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        $nameTb.Margin            = [System.Windows.Thickness]::new(8, 4, 0, 4)
        $row.Children.Add($nameTb) | Out-Null

        $listPanel.Children.Add($row) | Out-Null

        $capturedAppId   = $app.id
        $capturedAppName = $app.displayName
        $capturedDialog  = $dialog

        $delBtn.Add_Click({
            $path = Join-Path $env:APPDATA 'Loadout\user-manifest.json'
            try {
                $existing = @()
                if (Test-Path $path) {
                    $d        = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
                    $existing = @($d.apps | Where-Object { $_.id -ne $capturedAppId })
                }
                $manifest = [PSCustomObject]@{ apps = $existing }
                $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                Write-Log -Message "Custom app deleted: $capturedAppName (id: $capturedAppId)" -Level OK
            } catch {
                Write-Log -Message "Failed to delete custom app: $_" -Level ERROR
                return
            }

            $checkedIds = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($cb in (Get-CheckBoxes)) {
                if ($cb.IsChecked -eq $true) { $checkedIds.Add($cb.Tag) | Out-Null }
            }
            [void]$checkedIds.Remove($capturedAppId)
            if ($ManifestPath) {
                Initialize-ManifestManager -ManifestPath $ManifestPath
            } else {
                Initialize-ManifestManager
            }
            Rebuild-AppListPanel -PreCheckedIds $checkedIds
            $window.FindName('StatusBar').Text = "Custom app deleted: $capturedAppName"
            $capturedDialog.Close()
        }.GetNewClosure())
    }

    $capturedDialogClose = $dialog
    $dialog.FindName('BtnClose').Add_Click({
        $capturedDialogClose.Close()
    }.GetNewClosure())

    $dialog.ShowDialog() | Out-Null
}

# -----------------------------------------------------------------------
# Manage Custom Apps -- opens the manager dialog
# -----------------------------------------------------------------------
$window.FindName('BtnManageApps').Add_Click({
    Show-CustomAppManagerDialog
}.GetNewClosure())

# -----------------------------------------------------------------------
# Export / Import config -- now accessed via the Backup dialog

# -----------------------------------------------------------------------
# Font size controls (A- / A+ in top bar)
# Capture all needed references as locals -- GetNewClosure() captures locals
# reliably; $Script: vars would resolve to their defining-script scope inside
# a closure and are not safe to modify there (see Logger.ps1 note).
# -----------------------------------------------------------------------
$capturedFontSizes     = $Script:FontSizes
$capturedFontLogPanel  = $window.FindName('LogPanel')
$capturedFontAppList   = $appListPanel
$capturedLblInstallCol = $window.FindName('LblInstallCol')
$capturedLblUpdateCol  = $window.FindName('LblUpdateCol')

$applyFontSize = {
    $capturedFontLogPanel.FontSize = $capturedFontSizes.Log
    # Cascade to all CheckBoxes and version text via WPF inheritance
    [System.Windows.Documents.TextElement]::SetFontSize($capturedFontAppList, $capturedFontSizes.Log)
    # Category toggle buttons
    foreach ($cp in $capturedFontAppList.Children) {
        if ($cp -isnot [System.Windows.Controls.StackPanel]) { continue }
        foreach ($ch in $cp.Children) {
            if ($ch -is [System.Windows.Controls.Button]) { $ch.FontSize = $capturedFontSizes.Cat }
        }
    }
    # Version text blocks (not part of WPF inheritance chain)
    foreach ($rowEntry in $Script:AppRowElements.Values) {
        $rowEntry.VersionTb.FontSize = $capturedFontSizes.Log
    }
    # Column headers and update checkbox widths scale with Header font size
    $hdrWidth = [Math]::Max(56, $capturedFontSizes.Header * 4)
    $capturedLblInstallCol.FontSize = $capturedFontSizes.Header
    $capturedLblUpdateCol.FontSize  = $capturedFontSizes.Header
    $capturedLblUpdateCol.Width     = $hdrWidth
    foreach ($rowEntry in $Script:AppRowElements.Values) {
        $rowEntry.UpdateSlot.MinWidth = $hdrWidth
    }
}

$capturedApplyFont = $applyFontSize

$window.FindName('BtnFontSmaller').Add_Click({
    if ($capturedFontSizes.Log -gt 8) {
        $capturedFontSizes.Log    -= 1
        $capturedFontSizes.Cat    -= 1
        $capturedFontSizes.Header -= 1
        & $capturedApplyFont
    }
}.GetNewClosure())

$window.FindName('BtnFontLarger').Add_Click({
    if ($capturedFontSizes.Log -lt 24) {
        $capturedFontSizes.Log    += 1
        $capturedFontSizes.Cat    += 1
        $capturedFontSizes.Header += 1
        & $capturedApplyFont
    }
}.GetNewClosure())

# -----------------------------------------------------------------------
# Helper: Export-PuttySessions
# Exports PuTTY session registry key to a timestamped .reg file under
# %APPDATA%\Loadout\SessionBackups\PuTTY\.
# Returns the output file path on success, or $null on failure.
# -----------------------------------------------------------------------
function Export-PuttySessions {
    if (-not (Test-Path 'HKCU:\Software\SimonTatham\PuTTY\Sessions')) {
        Write-Log -Message 'PuTTY session export: no Sessions key found in registry.' -Level WARN
        return $null
    }
    $date    = Get-Date -Format 'yyyy-MM-dd-HHmmss'
    $outDir  = Join-Path $env:APPDATA 'Loadout\SessionBackups\PuTTY'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $outFile = Join-Path $outDir "putty-sessions-$date.reg"
    & reg export "HKCU\Software\SimonTatham\PuTTY\Sessions" $outFile /y 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log -Message "PuTTY sessions exported: $outFile" -Level OK
        return $outFile
    }
    Write-Log -Message "PuTTY session export failed (exit code $LASTEXITCODE)." -Level ERROR
    return $null
}

# -----------------------------------------------------------------------
# Helper: Import-PuttySessions
# Imports a PuTTY session .reg file into the registry.
# Returns $true on success, $false on failure.
# -----------------------------------------------------------------------
function Import-PuttySessions {
    param([Parameter(Mandatory)] [string]$FilePath)
    & reg import $FilePath 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log -Message "PuTTY sessions imported from: $FilePath" -Level OK
        return $true
    }
    Write-Log -Message "PuTTY session import failed (exit code $LASTEXITCODE)." -Level ERROR
    return $false
}

# -----------------------------------------------------------------------
# Helper: Export-WinscpSessions
# Exports WinSCP sessions. Tries registry first, then AppData INI fallback.
# Returns the output file path on success, or $null on failure.
# -----------------------------------------------------------------------
function Export-WinscpSessions {
    $date   = Get-Date -Format 'yyyy-MM-dd-HHmmss'
    $outDir = Join-Path $env:APPDATA 'Loadout\SessionBackups\WinSCP'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    if (Test-Path 'HKCU:\Software\Martin Prikryl\WinSCP 2\Sessions') {
        $outFile = Join-Path $outDir "winscp-sessions-$date.reg"
        & reg export "HKCU\Software\Martin Prikryl\WinSCP 2\Sessions" $outFile /y 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "WinSCP sessions exported (registry): $outFile" -Level OK
            return $outFile
        }
        Write-Log -Message "WinSCP registry export failed (exit code $LASTEXITCODE)." -Level ERROR
        return $null
    }

    $iniSource = Join-Path $env:APPDATA 'WinSCP.ini'
    if (Test-Path $iniSource) {
        $outFile = Join-Path $outDir "WinSCP-$date.ini"
        Copy-Item $iniSource $outFile -Force
        Write-Log -Message "WinSCP config exported (INI): $outFile" -Level OK
        return $outFile
    }

    Write-Log -Message 'WinSCP session export: no registry sessions or WinSCP.ini found.' -Level WARN
    return $null
}

# -----------------------------------------------------------------------
# Helper: Import-WinscpSessions
# Imports WinSCP sessions from a .reg file (registry) or .ini file.
# Returns $true on success, $false on failure.
# -----------------------------------------------------------------------
function Import-WinscpSessions {
    param([Parameter(Mandatory)] [string]$FilePath)
    $ext = [System.IO.Path]::GetExtension($FilePath).ToLower()
    if ($ext -eq '.reg') {
        & reg import $FilePath 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Log -Message "WinSCP sessions imported (registry) from: $FilePath" -Level OK
            return $true
        }
        Write-Log -Message "WinSCP registry import failed (exit code $LASTEXITCODE)." -Level ERROR
        return $false
    }
    if ($ext -eq '.ini') {
        $dest = Join-Path $env:APPDATA 'WinSCP.ini'
        Copy-Item $FilePath $dest -Force
        Write-Log -Message "WinSCP config restored (INI) to: $dest" -Level OK
        return $true
    }
    Write-Log -Message "Unrecognized WinSCP backup file type: $ext" -Level WARN
    return $false
}

# -----------------------------------------------------------------------
# Helper: Export-MachineSnapshot
# Saves the current scan results as a JSON audit log under
# %APPDATA%\Loadout\SessionBackups\MachineSnapshot\.
# Returns the output file path on success, or $null if no scan data.
# -----------------------------------------------------------------------
function Export-MachineSnapshot {
    if ($Script:LastScanResults.Count -eq 0) {
        Write-Log -Message 'Machine snapshot: no scan data available. Run a scan first.' -Level WARN
        return $null
    }
    $date   = Get-Date -Format 'yyyy-MM-dd-HHmmss'
    $outDir = Join-Path $env:APPDATA 'Loadout\SessionBackups\MachineSnapshot'
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    $outFile = Join-Path $outDir "snapshot-$date.json"

    $snapApps = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($key in $Script:LastScanResults.Keys) {
        $entry = $Script:LastScanResults[$key]
        $snapApps.Add([PSCustomObject]@{
            id               = $key
            status           = $entry.Status
            installedVersion = $entry.InstalledVersion
            availableVersion = $entry.AvailableVersion
        })
    }

    $snapshot = [PSCustomObject]@{
        capturedAt = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        appCount   = $snapApps.Count
        apps       = $snapApps.ToArray()
    }
    $snapshot | ConvertTo-Json -Depth 5 | Set-Content $outFile -Encoding UTF8
    Write-Log -Message "Machine snapshot saved: $($snapApps.Count) app(s) -> $outFile" -Level OK
    return $outFile
}

# -----------------------------------------------------------------------
# Helper: Import-MachineSnapshot
# Loads a machine snapshot JSON file and pre-checks all apps whose status
# was Current or UpdateAvailable. Rebuilds the app checklist.
# Returns $true on success, $false on failure.
# -----------------------------------------------------------------------
function Import-MachineSnapshot {
    param([Parameter(Mandatory)] [string]$FilePath)
    $data = $null
    try {
        $data = Get-Content $FilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Log -Message "Failed to read snapshot file: $_" -Level ERROR
        return $false
    }

    if (-not $data.apps) {
        Write-Log -Message 'Snapshot file contains no apps array.' -Level WARN
        return $false
    }

    $preCheckIds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($app in $data.apps) {
        if ($app.status -eq 'Current' -or $app.status -eq 'UpdateAvailable') {
            $preCheckIds.Add($app.id) | Out-Null
        }
    }

    Rebuild-AppListPanel -PreCheckedIds $preCheckIds
    Write-Log -Message "Machine snapshot imported: $($preCheckIds.Count) app(s) pre-checked from $([System.IO.Path]::GetFileName($FilePath))." -Level OK
    return $true
}

# -----------------------------------------------------------------------
# Helper: Show-SessionBackupDialog
# Modal WPF dialog with three sections:
#   PuTTY Sessions, WinSCP Sessions, Machine Config Snapshot.
# Each section has Export and Import buttons. Status labels update inline
# after each operation. Does not return a value (Close button dismisses).
# -----------------------------------------------------------------------
function Show-SessionBackupDialog {
    # Compute backup directory paths
    $puttyBackupDir    = Join-Path $env:APPDATA 'Loadout\SessionBackups\PuTTY'
    $winscpBackupDir   = Join-Path $env:APPDATA 'Loadout\SessionBackups\WinSCP'
    $snapshotBackupDir = Join-Path $env:APPDATA 'Loadout\SessionBackups\MachineSnapshot'

    # Scriptblock: find the most recent backup file matching a filter
    $getLastBackup = {
        param([string]$Dir, [string]$Filter)
        if (-not (Test-Path $Dir)) { return 'No backups yet.' }
        $files = @(Get-ChildItem -LiteralPath $Dir -Filter $Filter `
                       -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending)
        if ($files.Count -gt 0) {
            return "Last: $($files[0].LastWriteTime.ToString('yyyy-MM-dd'))  ($($files[0].Name))"
        }
        return 'No backups yet.'
    }

    # Detect installed tools and build initial status strings
    $puttyDetected     = Test-Path 'HKCU:\Software\SimonTatham\PuTTY\Sessions'
    $winscpRegDetected = Test-Path 'HKCU:\Software\Martin Prikryl\WinSCP 2\Sessions'
    $winscpIniFile     = Join-Path $env:APPDATA 'WinSCP.ini'
    $winscpIniDetected = Test-Path $winscpIniFile
    $winscpDetected    = $winscpRegDetected -or $winscpIniDetected
    $scanAppCount      = $Script:LastScanResults.Count

    $winscpMode = if ($winscpRegDetected) { 'registry' } `
                  elseif ($winscpIniDetected) { 'INI' } `
                  else { 'not detected' }
    $winscpFilter = if ($winscpIniDetected -and -not $winscpRegDetected) { 'WinSCP-*.ini' } `
                    else { 'winscp-sessions-*.reg' }

    $puttyStatusText = if ($puttyDetected) {
        "PuTTY sessions found in registry.  $(& $getLastBackup $puttyBackupDir 'putty-sessions-*.reg')"
    } else {
        "No PuTTY sessions detected.  $(& $getLastBackup $puttyBackupDir 'putty-sessions-*.reg')"
    }

    $winscpStatusText = if ($winscpDetected) {
        "WinSCP sessions found ($winscpMode).  $(& $getLastBackup $winscpBackupDir $winscpFilter)"
    } else {
        "WinSCP sessions not detected.  $(& $getLastBackup $winscpBackupDir '*')"
    }

    $snapshotStatusText = if ($scanAppCount -gt 0) {
        "$scanAppCount app(s) in current scan.  $(& $getLastBackup $snapshotBackupDir 'snapshot-*.json')"
    } else {
        "No scan data yet. Run a scan first.  $(& $getLastBackup $snapshotBackupDir 'snapshot-*.json')"
    }

    $dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Session and Machine Backup"
        Width="500" Height="500"
        Background="#1E1E1E" Foreground="WhiteSmoke"
        WindowStartupLocation="CenterOwner"
        ResizeMode="CanResizeWithGrip">
  <DockPanel Margin="16">
    <StackPanel DockPanel.Dock="Bottom" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="BtnBackupClose" Content="Close" Width="90"
              Background="#3A3A3A" Foreground="WhiteSmoke"
              BorderThickness="0" Padding="0,6"/>
    </StackPanel>
    <ScrollViewer VerticalScrollBarVisibility="Auto">
      <StackPanel>

        <TextBlock Text="PuTTY Sessions" FontSize="13" FontWeight="SemiBold"
                   Foreground="#5CB8FF" Margin="0,0,0,4"/>
        <Separator Background="#3A3A3A" Margin="0,0,0,6"/>
        <TextBlock x:Name="LblPuttyStatus" Text="..."
                   FontFamily="Consolas" FontSize="10" Foreground="#888888"
                   TextWrapping="Wrap" Margin="0,0,0,6"/>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,20">
          <Button x:Name="BtnPuttyExport" Content="Export" Padding="12,4" Margin="0,0,8,0"
                  Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
          <Button x:Name="BtnPuttyImport" Content="Import" Padding="12,4"
                  Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
        </StackPanel>

        <TextBlock Text="WinSCP Sessions" FontSize="13" FontWeight="SemiBold"
                   Foreground="#5CB8FF" Margin="0,0,0,4"/>
        <Separator Background="#3A3A3A" Margin="0,0,0,6"/>
        <TextBlock x:Name="LblWinscpStatus" Text="..."
                   FontFamily="Consolas" FontSize="10" Foreground="#888888"
                   TextWrapping="Wrap" Margin="0,0,0,6"/>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,20">
          <Button x:Name="BtnWinscpExport" Content="Export" Padding="12,4" Margin="0,0,8,0"
                  Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
          <Button x:Name="BtnWinscpImport" Content="Import" Padding="12,4"
                  Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
        </StackPanel>

        <TextBlock Text="Machine Config Snapshot" FontSize="13" FontWeight="SemiBold"
                   Foreground="#5CB8FF" Margin="0,0,0,4"/>
        <Separator Background="#3A3A3A" Margin="0,0,0,6"/>
        <TextBlock Text="Saves installed app versions as a JSON audit log."
                   FontSize="10" Foreground="#888888" TextWrapping="Wrap" Margin="0,0,0,2"/>
        <TextBlock Text="Import pre-checks apps that were installed on the source machine."
                   FontSize="10" Foreground="#888888" TextWrapping="Wrap" Margin="0,0,0,6"/>
        <TextBlock x:Name="LblSnapshotStatus" Text="..."
                   FontFamily="Consolas" FontSize="10" Foreground="#888888"
                   TextWrapping="Wrap" Margin="0,0,0,6"/>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,20">
          <Button x:Name="BtnSnapshotExport" Content="Export" Padding="12,4" Margin="0,0,8,0"
                  Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
          <Button x:Name="BtnSnapshotImport" Content="Import" Padding="12,4"
                  Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
        </StackPanel>

        <TextBlock Text="Loadout Configuration" FontSize="13" FontWeight="SemiBold"
                   Foreground="#5CB8FF" Margin="0,0,0,4"/>
        <Separator Background="#3A3A3A" Margin="0,0,0,6"/>
        <TextBlock Text="Export saves your current checkbox selections and any custom apps to a JSON file."
                   FontSize="10" Foreground="#888888" TextWrapping="Wrap" Margin="0,0,0,2"/>
        <TextBlock Text="Import restores selections and merges custom apps from a previously exported file."
                   FontSize="10" Foreground="#888888" TextWrapping="Wrap" Margin="0,0,0,6"/>
        <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
          <Button x:Name="BtnConfigExport" Content="Export Config" Padding="12,4" Margin="0,0,8,0"
                  Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
          <Button x:Name="BtnConfigImport" Content="Import Config" Padding="12,4"
                  Background="#3A3A3A" Foreground="WhiteSmoke" BorderThickness="0"/>
        </StackPanel>

      </StackPanel>
    </ScrollViewer>
  </DockPanel>
</Window>
'@

    $xmlDoc    = [System.Xml.XmlDocument]::new()
    $xmlDoc.LoadXml($dialogXaml)
    $xmlReader = [System.Xml.XmlNodeReader]::new($xmlDoc)
    $dialog    = [System.Windows.Markup.XamlReader]::Load($xmlReader)

    # Set status text in code to avoid XML-escaping issues with embedded variables
    $lblPuttyStatus    = $dialog.FindName('LblPuttyStatus')
    $lblWinscpStatus   = $dialog.FindName('LblWinscpStatus')
    $lblSnapshotStatus = $dialog.FindName('LblSnapshotStatus')

    $lblPuttyStatus.Text    = $puttyStatusText
    $lblWinscpStatus.Text   = $winscpStatusText
    $lblSnapshotStatus.Text = $snapshotStatusText

    # Capture for use in event handlers (GetNewClosure() captures locals reliably)
    $capturedLblPutty    = $lblPuttyStatus
    $capturedLblWinscp   = $lblWinscpStatus
    $capturedLblSnapshot = $lblSnapshotStatus
    $capturedDialog      = $dialog
    $capturedPuttyDir    = $puttyBackupDir
    $capturedWinscpDir   = $winscpBackupDir
    $capturedSnapshotDir = $snapshotBackupDir

    # --- PuTTY Export ---
    $dialog.FindName('BtnPuttyExport').Add_Click({
        $result = Export-PuttySessions
        $capturedLblPutty.Text = if ($result) {
            "Export complete.  $([System.IO.Path]::GetFileName($result))"
        } else {
            'Export failed -- see log for details.'
        }
    }.GetNewClosure())

    # --- PuTTY Import ---
    # reg.exe blocks the UI thread and shows a success dialog before exiting.
    # Use Start-Process (non-blocking) + DispatcherTimer so WPF stays responsive.
    $dialog.FindName('BtnPuttyImport').Add_Click({
        $ofd                  = [Microsoft.Win32.OpenFileDialog]::new()
        $ofd.Title            = 'Select PuTTY Session Backup'
        $ofd.Filter           = 'Registry File (*.reg)|*.reg'
        $ofd.InitialDirectory = if (Test-Path $capturedPuttyDir) { $capturedPuttyDir } else { $env:APPDATA }
        if ($ofd.ShowDialog($capturedDialog) -ne $true) { return }

        $capturedFilePath2 = $ofd.FileName
        $capturedFileName2 = [System.IO.Path]::GetFileName($ofd.FileName)
        $capturedLblRef2   = $capturedLblPutty
        $capturedLblRef2.Text = 'Importing...'

        try {
            $proc = Start-Process -FilePath "$env:SystemRoot\System32\reg.exe" `
                        -ArgumentList 'import', "`"$capturedFilePath2`"" `
                        -PassThru -WindowStyle Hidden
        } catch {
            $capturedLblRef2.Text = 'Import failed: could not start reg.exe.'
            return
        }

        $capturedProc2    = $proc
        $puttyImportTimer = [System.Windows.Threading.DispatcherTimer]::new()
        $puttyImportTimer.Interval = [System.TimeSpan]::FromMilliseconds(200)
        $capturedPuttyTimer = $puttyImportTimer

        $puttyImportTimer.Add_Tick({
            if (-not $capturedProc2.HasExited) { return }
            $capturedPuttyTimer.Stop()
            $exitCode = $capturedProc2.ExitCode
            $capturedProc2.Dispose()
            if ($exitCode -eq 0) {
                Write-Log -Message "PuTTY sessions imported from: $capturedFilePath2" -Level OK
                $capturedLblRef2.Text = "Import complete from: $capturedFileName2"
            } else {
                Write-Log -Message "PuTTY session import failed (exit code $exitCode)." -Level ERROR
                $capturedLblRef2.Text = "Import failed (exit code $exitCode)."
            }
        }.GetNewClosure())
        $puttyImportTimer.Start()
    }.GetNewClosure())

    # --- WinSCP Export ---
    $dialog.FindName('BtnWinscpExport').Add_Click({
        $result = Export-WinscpSessions
        $capturedLblWinscp.Text = if ($result) {
            "Export complete.  $([System.IO.Path]::GetFileName($result))"
        } else {
            'Export failed -- see log for details.'
        }
    }.GetNewClosure())

    # --- WinSCP Import ---
    # .reg path uses Start-Process + DispatcherTimer (same reason as PuTTY above).
    # .ini path uses Copy-Item synchronously (no external process involved).
    $dialog.FindName('BtnWinscpImport').Add_Click({
        $ofd                  = [Microsoft.Win32.OpenFileDialog]::new()
        $ofd.Title            = 'Select WinSCP Session Backup'
        $ofd.Filter           = 'Registry File (*.reg)|*.reg|INI File (*.ini)|*.ini|All Files (*.*)|*.*'
        $ofd.InitialDirectory = if (Test-Path $capturedWinscpDir) { $capturedWinscpDir } else { $env:APPDATA }
        if ($ofd.ShowDialog($capturedDialog) -ne $true) { return }

        $capturedFilePath3 = $ofd.FileName
        $capturedFileName3 = [System.IO.Path]::GetFileName($ofd.FileName)
        $capturedLblRef3   = $capturedLblWinscp
        $ext               = [System.IO.Path]::GetExtension($ofd.FileName).ToLower()

        if ($ext -eq '.ini') {
            try {
                $dest = Join-Path $env:APPDATA 'WinSCP.ini'
                Copy-Item $capturedFilePath3 $dest -Force
                Write-Log -Message "WinSCP config restored (INI) to: $dest" -Level OK
                $capturedLblRef3.Text = "Import complete from: $capturedFileName3"
            } catch {
                $capturedLblRef3.Text = "Import failed: $_"
            }
            return
        }

        $capturedLblRef3.Text = 'Importing...'
        try {
            $proc = Start-Process -FilePath "$env:SystemRoot\System32\reg.exe" `
                        -ArgumentList 'import', "`"$capturedFilePath3`"" `
                        -PassThru -WindowStyle Hidden
        } catch {
            $capturedLblRef3.Text = 'Import failed: could not start reg.exe.'
            return
        }

        $capturedProc3      = $proc
        $winscpImportTimer  = [System.Windows.Threading.DispatcherTimer]::new()
        $winscpImportTimer.Interval = [System.TimeSpan]::FromMilliseconds(200)
        $capturedWinscpTimer = $winscpImportTimer

        $winscpImportTimer.Add_Tick({
            if (-not $capturedProc3.HasExited) { return }
            $capturedWinscpTimer.Stop()
            $exitCode = $capturedProc3.ExitCode
            $capturedProc3.Dispose()
            if ($exitCode -eq 0) {
                Write-Log -Message "WinSCP sessions imported (registry) from: $capturedFilePath3" -Level OK
                $capturedLblRef3.Text = "Import complete from: $capturedFileName3"
            } else {
                Write-Log -Message "WinSCP registry import failed (exit code $exitCode)." -Level ERROR
                $capturedLblRef3.Text = "Import failed (exit code $exitCode)."
            }
        }.GetNewClosure())
        $winscpImportTimer.Start()
    }.GetNewClosure())

    # --- Machine Snapshot Export ---
    $dialog.FindName('BtnSnapshotExport').Add_Click({
        $result = Export-MachineSnapshot
        $capturedLblSnapshot.Text = if ($result) {
            "Export complete.  $([System.IO.Path]::GetFileName($result))"
        } else {
            'Export failed -- no scan data or error. See log.'
        }
    }.GetNewClosure())

    # --- Machine Snapshot Import ---
    $dialog.FindName('BtnSnapshotImport').Add_Click({
        $ofd                  = [Microsoft.Win32.OpenFileDialog]::new()
        $ofd.Title            = 'Select Machine Config Snapshot'
        $ofd.Filter           = 'JSON Snapshot (*.json)|*.json'
        $ofd.InitialDirectory = if (Test-Path $capturedSnapshotDir) { $capturedSnapshotDir } else { $env:APPDATA }
        if ($ofd.ShowDialog($capturedDialog) -ne $true) { return }
        $ok = Import-MachineSnapshot -FilePath $ofd.FileName
        $capturedLblSnapshot.Text = if ($ok) {
            'Import complete. App list updated.'
        } else {
            'Import failed -- see log for details.'
        }
    }.GetNewClosure())

    # --- Loadout Config Export ---
    $dialog.FindName('BtnConfigExport').Add_Click({
        Export-LoadoutConfig
    }.GetNewClosure())

    # --- Loadout Config Import ---
    $dialog.FindName('BtnConfigImport').Add_Click({
        Import-LoadoutConfig
    }.GetNewClosure())

    # --- Close ---
    $dialog.FindName('BtnBackupClose').Add_Click({
        $capturedDialog.Close()
    }.GetNewClosure())

    $dialog.Owner = $window
    $dialog.ShowDialog() | Out-Null
}

# -----------------------------------------------------------------------
# Session Backup -- opens the session and machine backup dialog
# -----------------------------------------------------------------------
$window.FindName('BtnBackup').Add_Click({
    Show-SessionBackupDialog
}.GetNewClosure())

# -----------------------------------------------------------------------
# Show window -- blocks until user closes it
# -----------------------------------------------------------------------
$window.ShowDialog() | Out-Null

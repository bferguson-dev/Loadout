# UpdateChecker.ps1 -- Loadout app version scanner
# Scans all apps (or a provided subset) against installed versions on
# this machine and returns a status-per-app result hashtable.
#
# Public entry point: Invoke-AppScan [-Apps <object[]>]
# Requires: Logger.ps1 and ManifestManager.ps1 already dot-sourced.
#
# Deferred to later sessions:
#   Task Scheduler scan  (Session 18)
#   update-cache.json    (Session 18)
#   GUI badge wiring     (Session 7)
#
# ASCII-only file -- see Coding Standards in DESIGN.md.

# AUTO-SUPPRESS-PSScriptAnalyzer
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs','')]
param()

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------
# Script-scope cache -- populated once per Invoke-AppScan call
# -----------------------------------------------------------------------

# Winget installed-app table: wingetId.ToLower() -> PSCustomObject{Id, Version, Available}
# $null means the cache has not been built yet this run.
$Script:WingetCache = $null
# Indicates winget scan backend failure (command/parsing), so winget
# app statuses should be marked Failed rather than NotInstalled.
$Script:WingetCacheFailed = $false

# WSL installed distros: HashSet[string] (OrdinalIgnoreCase) of distro names.
# $null means the cache has not been built yet this run.
$Script:WslInstalledCache = $null

# VS Code installed extensions: HashSet[string] (OrdinalIgnoreCase) of extension IDs.
# $null means the cache has not been built yet this run.
$Script:VSCodeExtensionCache = $null

# -----------------------------------------------------------------------
# Private: Build-WslCache
# Runs 'wsl --list --quiet' once per scan, parses distro names into a
# case-insensitive HashSet for O(1) lookup. WSL outputs UTF-16LE; the
# console encoding is changed temporarily to decode it correctly.
# In DryRun mode: logs the command and leaves the cache empty.
# -----------------------------------------------------------------------
function Build-WslCache {

    $Script:WslInstalledCache = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    if ($Script:DryRun) {
        Write-Log -Message '  [DRY RUN] Would run: wsl --list --quiet' -Level DEBUG
        return
    }

    $prevEncoding = [Console]::OutputEncoding
    try {
        # WSL outputs UTF-16LE; override console encoding so PowerShell decodes it correctly
        [Console]::OutputEncoding = [System.Text.Encoding]::Unicode
        $lines = @(& wsl --list --quiet 2>$null)
    }
    catch {
        Write-Log -Message "  Build-WslCache: wsl --list failed -- $($_.Exception.Message)" -Level WARN
        return
    }
    finally {
        [Console]::OutputEncoding = $prevEncoding
    }

    foreach ($line in $lines) {
        # Strip residual null bytes and whitespace, skip empty lines
        $name = ($line -replace '\x00', '').Trim()
        if ($name) {
            [void]$Script:WslInstalledCache.Add($name)
        }
    }

    Write-Log -Message "  WSL cache built: $($Script:WslInstalledCache.Count) distro(s) found" -Level DEBUG
}

# -----------------------------------------------------------------------
# Private: Invoke-WSLScan
# Checks whether the distro named by app.wslDistroName is registered in
# WSL by consulting the $Script:WslInstalledCache built by Build-WslCache.
# WSL distros have no version concept -- installed = Current.
# -----------------------------------------------------------------------
function Invoke-WSLScan {
    param([Parameter(Mandatory)] [object]$App)

    if ($Script:WslInstalledCache.Contains($App.wslDistroName)) {
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = '(installed)'
            AvailableVersion = $null
        }
    }

    return [PSCustomObject]@{
        Status           = 'NotInstalled'
        InstalledVersion = $null
        AvailableVersion = $null
    }
}

# -----------------------------------------------------------------------
# Private: Build-VSCodeExtensionCache
# Runs 'code --list-extensions' once per scan and stores results in
# $Script:VSCodeExtensionCache (OrdinalIgnoreCase HashSet of extension IDs).
# In DryRun mode: logs the command and leaves the cache empty.
# -----------------------------------------------------------------------
function Build-VSCodeExtensionCache {

    $Script:VSCodeExtensionCache = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    if ($Script:DryRun) {
        Write-Log -Message '  [DRY RUN] Would run: code --list-extensions' -Level DEBUG
        return
    }

    try {
        $lines = @(& code --list-extensions 2>&1)
        foreach ($line in $lines) {
            $trimmed = $line.ToString().Trim()
            if ($trimmed -ne '') {
                [void]$Script:VSCodeExtensionCache.Add($trimmed)
            }
        }
        Write-Log -Message "  VS Code extension cache built -- $($Script:VSCodeExtensionCache.Count) extension(s) found" -Level DEBUG
    }
    catch {
        Write-Log -Message "  Build-VSCodeExtensionCache: code --list-extensions failed -- $($_.Exception.Message)" -Level WARN
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-VSCodeExtensionScan
# Checks whether the extension ID is in the VS Code extension cache.
# Returns Current/NotInstalled only (no version comparison with marketplace).
# -----------------------------------------------------------------------
function Invoke-VSCodeExtensionScan {
    param([Parameter(Mandatory)] [object]$App)

    if ($Script:VSCodeExtensionCache.Contains($App.vscodeExtensionId)) {
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = '(installed)'
            AvailableVersion = $null
        }
    }

    return [PSCustomObject]@{
        Status           = 'NotInstalled'
        InstalledVersion = $null
        AvailableVersion = $null
    }
}

# -----------------------------------------------------------------------
# Private: Get-ScanMethod
# Returns the scan method string for an app object.
# Priority order mirrors InstallEngine.Get-InstallMethod exactly.
# -----------------------------------------------------------------------
function Get-ScanMethod {
    param([Parameter(Mandatory)] [object]$App)

    if ($App.wslDistroName)        { return 'WSL' }
    if ($App.windowsFeatureMethod) { return 'WindowsFeature' }
    if ($App.registryPath)         { return 'Registry' }
    if ($App.vscodeExtensionId)    { return 'VSCodeExtension' }
    if ($App.wingetId)             { return 'Winget' }
    if ($App.psGalleryModule)      { return 'PSGallery' }
    if ($App.directDownload)       { return 'DirectDownload' }
    if ($App.chocolateyId)         { return 'Chocolatey' }
    if ($App.postInstallOnly -eq $true) { return 'PostInstallOnly' }
    if ($App.postInstallCommands -and $App.postInstallCommands.Count -gt 0) { return 'PostInstallOnly' }
    return 'Unknown'
}

# -----------------------------------------------------------------------
# Private: Get-ColumnValue
# Extracts a substring from a fixed-width table row between two column
# start positions, trimming whitespace. Returns '' if out of range.
# -----------------------------------------------------------------------
function Get-ColumnValue {
    param(
        [string]$Row,
        [int]$ColStart,
        [int]$ColEnd        # exclusive; pass $Row.Length if last column
    )

    if ($ColStart -ge $Row.Length) { return '' }
    $safeEnd = [Math]::Min($ColEnd, $Row.Length)
    if ($safeEnd -le $ColStart) { return '' }
    return $Row.Substring($ColStart, $safeEnd - $ColStart).Trim()
}

# -----------------------------------------------------------------------
# Private: Build-WingetCache
# Runs ONE 'winget list' call and parses the full output table into a
# hashtable keyed by winget App ID (lowercase) for O(1) lookup.
# In DryRun mode: logs the command and leaves the cache empty.
# -----------------------------------------------------------------------
function Build-WingetCache {

    $Script:WingetCache = @{}
    $Script:WingetCacheFailed = $false

    if ($Script:DryRun) {
        Write-Log -Message '  [DRY RUN] Would run: winget list --accept-source-agreements' -Level DEBUG
        return
    }

    Write-Log -Message 'UpdateChecker: Running winget list (single call)...' -Level DEBUG

    try {
        [string[]]$lines = & winget.exe list --accept-source-agreements 2>$null
    }
    catch {
        $Script:WingetCacheFailed = $true
        Write-Log -Message "UpdateChecker: winget list failed -- $($_.Exception.Message)" -Level WARN
        return
    }

    if (-not $lines -or $lines.Count -eq 0) {
        $Script:WingetCacheFailed = $true
        Write-Log -Message 'UpdateChecker: winget list returned no output' -Level WARN
        return
    }

    # Find the header row -- must contain Id, Version, and Available columns
    $headerIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '\bId\b' -and
            $lines[$i] -match '\bVersion\b' -and
            $lines[$i] -match '\bAvailable\b') {
            $headerIdx = $i
            break
        }
    }

    if ($headerIdx -lt 0) {
        $Script:WingetCacheFailed = $true
        Write-Log -Message 'UpdateChecker: Could not find winget list table header -- cache empty' -Level WARN
        return
    }

    $header = $lines[$headerIdx]

    # Determine fixed column start positions from keyword offsets in the header
    $colId        = $header.IndexOf('Id')
    $colVersion   = $header.IndexOf('Version')
    $colAvailable = $header.IndexOf('Available')
    $colSource    = $header.IndexOf('Source')

    if ($colId -lt 0 -or $colVersion -lt 0 -or $colAvailable -lt 0) {
        $Script:WingetCacheFailed = $true
        Write-Log -Message 'UpdateChecker: Missing required columns in winget header -- cache empty' -Level WARN
        return
    }

    # Determine the right edge for the Available column
    $availEnd = if ($colSource -gt $colAvailable) { $colSource } else { [int]::MaxValue }

    # Data rows start after the separator line (dashes)
    $dataStart = $headerIdx + 1
    if ($dataStart -lt $lines.Count -and $lines[$dataStart] -match '^[\-\s]+$') {
        $dataStart++
    }

    for ($i = $dataStart; $i -lt $lines.Count; $i++) {
        $row = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($row)) { continue }

        $idVal        = Get-ColumnValue -Row $row -ColStart $colId        -ColEnd $colVersion
        $versionVal   = Get-ColumnValue -Row $row -ColStart $colVersion   -ColEnd $colAvailable
        $availableVal = Get-ColumnValue -Row $row -ColStart $colAvailable  -ColEnd $availEnd

        if (-not $idVal) { continue }

        $Script:WingetCache[$idVal.ToLower()] = [PSCustomObject]@{
            Id        = $idVal
            Version   = $versionVal
            Available = $availableVal
        }
    }

    Write-Log -Message "UpdateChecker: Winget cache built -- $($Script:WingetCache.Count) installed entries" -Level DEBUG
}

# -----------------------------------------------------------------------
# Private: Invoke-WingetScan
# Looks up the app in the pre-built winget cache and returns status.
# -----------------------------------------------------------------------
function Invoke-WingetScan {
    param([Parameter(Mandatory)] [object]$App)

    if ($Script:WingetCacheFailed) {
        return [PSCustomObject]@{
            Status           = 'Failed'
            InstalledVersion = $null
            AvailableVersion = $null
        }
    }

    $key = $App.wingetId.ToLower()

    if (-not $Script:WingetCache.ContainsKey($key)) {
        return [PSCustomObject]@{
            Status           = 'NotInstalled'
            InstalledVersion = $null
            AvailableVersion = $null
        }
    }

    $entry     = $Script:WingetCache[$key]
    $installed = $entry.Version
    $available = $entry.Available

    if ($available) {
        return [PSCustomObject]@{
            Status           = 'UpdateAvailable'
            InstalledVersion = $installed
            AvailableVersion = $available
        }
    }

    return [PSCustomObject]@{
        Status           = 'Current'
        InstalledVersion = $installed
        AvailableVersion = $installed
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-PSGalleryScan
# Checks Get-InstalledModule vs Find-Module for the module version.
# -----------------------------------------------------------------------
function Invoke-PSGalleryScan {
    param([Parameter(Mandatory)] [object]$App)

    $modName = $App.psGalleryModule

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would check: Get-InstalledModule $modName vs Find-Module $modName" -Level DEBUG
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = '(dry-run)'
            AvailableVersion = '(dry-run)'
        }
    }

    $installed = Get-InstalledModule -Name $modName -ErrorAction SilentlyContinue
    if (-not $installed) {
        return [PSCustomObject]@{
            Status           = 'NotInstalled'
            InstalledVersion = $null
            AvailableVersion = $null
        }
    }

    $installedVer = $installed.Version.ToString()

    $available    = Find-Module -Name $modName -ErrorAction SilentlyContinue
    $availableVer = if ($available) { $available.Version.ToString() } else { $installedVer }

    # Use [Version] comparison to avoid false positives from string ordering
    try {
        $iv = [Version]$installedVer
        $av = [Version]$availableVer

        if ($av -gt $iv) {
            return [PSCustomObject]@{
                Status           = 'UpdateAvailable'
                InstalledVersion = $installedVer
                AvailableVersion = $availableVer
            }
        }
    }
    catch {
        # Non-semver: fall back to plain string comparison
        if ($availableVer -ne $installedVer) {
            return [PSCustomObject]@{
                Status           = 'UpdateAvailable'
                InstalledVersion = $installedVer
                AvailableVersion = $availableVer
            }
        }
    }

    return [PSCustomObject]@{
        Status           = 'Current'
        InstalledVersion = $installedVer
        AvailableVersion = $availableVer
    }
}

# -----------------------------------------------------------------------
# Private: Get-DirectDownloadInstalledVersion
# Reads DisplayVersion from the HKLM Uninstall registry path named by
# the directDownload.installedVersionPath manifest field.
# The path may be a parent key -- in that case subkeys are searched for
# a DisplayName matching the app's displayName.
# Returns $null if not found.
# -----------------------------------------------------------------------
function Get-DirectDownloadInstalledVersion {
    param([Parameter(Mandatory)] [object]$App)

    $regPath = $App.directDownload.installedVersionPath
    if (-not $regPath) { return $null }

    # Try direct key first (rare -- most manifests give the parent path)
    if (Test-Path $regPath) {
        $props = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
        if ($props -and $props.DisplayVersion) {
            return $props.DisplayVersion
        }
    }

    # Search subkeys of the parent path for a DisplayName match
    $subkeys = Get-ChildItem -Path $regPath -ErrorAction SilentlyContinue
    foreach ($key in $subkeys) {
        $props = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        if ($props.DisplayName -and
            $props.DisplayName -like "*$($App.displayName)*" -and
            $props.DisplayVersion) {
            return $props.DisplayVersion
        }
    }

    return $null
}

# -----------------------------------------------------------------------
# Private: Get-GitHubLatestVersion
# Calls the GitHub Releases API URL and returns the latest tag_name,
# stripping a leading 'v' prefix (e.g. 'v1.2.3' -> '1.2.3').
# -----------------------------------------------------------------------
function Get-GitHubLatestVersion {
    param([Parameter(Mandatory)] [string]$Url)

    $response = Invoke-RestMethod -Uri $Url -UseBasicParsing -ErrorAction Stop

    $tag = $response.tag_name
    if (-not $tag) {
        throw "github-api response did not contain 'tag_name' field"
    }

    return $tag.TrimStart('v')
}

# -----------------------------------------------------------------------
# Private: Get-JsonPathVersion
# Resolves a simple JSON path expression (e.g. '$.a.b[0].c') from a URL
# response and returns it as a string.
# -----------------------------------------------------------------------
function Get-JsonPathVersion {
    param(
        [Parameter(Mandatory)] [string]$Url,
        [Parameter(Mandatory)] [string]$Expression
    )

    $json = Invoke-RestMethod -Uri $Url -UseBasicParsing -ErrorAction Stop
    $expr = $Expression.Trim()
    if (-not $expr.StartsWith('$.')) {
        throw "json-path expression must start with '$.': $Expression"
    }

    $path = $expr.Substring(2)
    $segments = $path -split '\.'
    $current = $json

    foreach ($seg in $segments) {
        if (-not $seg) { continue }
        $m = [regex]::Match($seg, '^([^\[\]]+)(?:\[(\d+)\])?$')
        if (-not $m.Success) {
            throw "Unsupported json-path segment: $seg"
        }

        $name = $m.Groups[1].Value
        $idxText = $m.Groups[2].Value

        if ($null -eq $current) { throw "json-path did not resolve at '$seg'" }

        $next = $current.$name
        if ($null -eq $next) { throw "json-path property not found: $name" }

        if ($idxText -ne '') {
            $idx = [int]$idxText
            if ($next -is [System.Array] -or $next -is [System.Collections.IList]) {
                if ($idx -lt 0 -or $idx -ge $next.Count) {
                    throw "json-path index out of range: $seg"
                }
                $next = $next[$idx]
            } else {
                throw "json-path index used on non-array segment: $seg"
            }
        }

        $current = $next
    }

    if ($null -eq $current) { return $null }
    return [string]$current
}

# -----------------------------------------------------------------------
# Private: Invoke-DirectDownloadScan
# Checks the registry for the installed version and compares against the
# versionCheckUrl in the manifest. Supports 'github-api',
# 'github-release' (alias), and 'json-path'.
# -----------------------------------------------------------------------
function Invoke-DirectDownloadScan {
    param([Parameter(Mandatory)] [object]$App)

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would check registry for: $($App.displayName)" -Level DEBUG
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = '(dry-run)'
            AvailableVersion = $null
        }
    }

    $installedVer = Get-DirectDownloadInstalledVersion -App $App

    if (-not $installedVer) {
        return [PSCustomObject]@{
            Status           = 'NotInstalled'
            InstalledVersion = $null
            AvailableVersion = $null
        }
    }

    $method = $App.directDownload.versionCheckMethod
    $url    = $App.directDownload.versionCheckUrl

    # No version check URL configured -- assume Current
    if (-not $url -or -not $method) {
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = $installedVer
            AvailableVersion = $null
        }
    }

    if ($method -notin @('github-api', 'github-release', 'json-path')) {
        Write-Log -Message "[$($App.displayName)] versionCheckMethod '$method' not implemented -- skipping version check" -Level WARN
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = $installedVer
            AvailableVersion = $null
        }
    }

    $availableVer = if ($method -eq 'json-path') {
        $expr = $App.directDownload.versionCheckExpression
        if (-not $expr) {
            Write-Log -Message "[$($App.displayName)] json-path selected but no versionCheckExpression set -- skipping version check" -Level WARN
            $null
        } else {
            Get-JsonPathVersion -Url $url -Expression $expr
        }
    } else {
        Get-GitHubLatestVersion -Url $url
    }

    if (-not $availableVer) {
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = $installedVer
            AvailableVersion = $null
        }
    }

    # Compare versions; use [Version] first, fall back to string compare
    try {
        $iv = [Version]$installedVer
        $av = [Version]$availableVer

        if ($av -gt $iv) {
            return [PSCustomObject]@{
                Status           = 'UpdateAvailable'
                InstalledVersion = $installedVer
                AvailableVersion = $availableVer
            }
        }
    }
    catch {
        if ($availableVer -ne $installedVer) {
            return [PSCustomObject]@{
                Status           = 'UpdateAvailable'
                InstalledVersion = $installedVer
                AvailableVersion = $availableVer
            }
        }
    }

    return [PSCustomObject]@{
        Status           = 'Current'
        InstalledVersion = $installedVer
        AvailableVersion = $availableVer
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-ChocolateyScan
# Checks installed version via 'choco list --local-only'.
# Only runs if choco.exe is present on PATH.
# -----------------------------------------------------------------------
function Invoke-ChocolateyScan {
    param([Parameter(Mandatory)] [object]$App)

    $chocoExe = Get-Command 'choco.exe' -ErrorAction SilentlyContinue
    if (-not $chocoExe) {
        return [PSCustomObject]@{
            Status           = 'NotInstalled'
            InstalledVersion = $null
            AvailableVersion = $null
        }
    }

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would run: choco list --local-only $($App.chocolateyId)" -Level DEBUG
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = '(dry-run)'
            AvailableVersion = $null
        }
    }

    [string[]]$output = & choco.exe list --local-only $App.chocolateyId 2>$null

    # Choco output line format: "PackageName Version"
    $matchLine = $output | Where-Object { $_ -match "^$([regex]::Escape($App.chocolateyId))\s+" }

    if (-not $matchLine) {
        return [PSCustomObject]@{
            Status           = 'NotInstalled'
            InstalledVersion = $null
            AvailableVersion = $null
        }
    }

    $installedVer = ($matchLine -split '\s+', 2)[1]

    return [PSCustomObject]@{
        Status           = 'Current'
        InstalledVersion = $installedVer
        AvailableVersion = $null
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-WindowsFeatureScan
# Checks whether a Windows Feature or Capability is enabled/installed
# using Get-WindowsOptionalFeature or Get-WindowsCapability (DISM).
# Returns Current if enabled, NotInstalled if disabled/not present.
# No UpdateAvailable state -- features are either on or off.
# In DryRun mode: returns Current with '(dry-run)' versions.
# -----------------------------------------------------------------------
function Invoke-WindowsFeatureScan {
    param([Parameter(Mandatory)] [object]$App)

    $featureMethod = $App.windowsFeatureMethod
    $featureName   = $App.windowsFeatureName

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would check: $featureMethod -Online -FeatureName/-Name $featureName" -Level DEBUG
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = '(dry-run)'
            AvailableVersion = $null
        }
    }

    if ($featureMethod -eq 'Enable-WindowsOptionalFeature') {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $featureName -ErrorAction SilentlyContinue
        $enabled = $feature -and $feature.State -eq 'Enabled'
    }
    elseif ($featureMethod -eq 'Add-WindowsCapability') {
        $cap     = Get-WindowsCapability -Online -Name $featureName -ErrorAction SilentlyContinue
        $enabled = $cap -and $cap.State -eq 'Installed'
    }
    else {
        throw "Unknown windowsFeatureMethod '$featureMethod'"
    }

    if ($enabled) {
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = '(enabled)'
            AvailableVersion = $null
        }
    }

    return [PSCustomObject]@{
        Status           = 'NotInstalled'
        InstalledVersion = $null
        AvailableVersion = $null
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-RegistryScan
# Checks whether the registry value named by registryPath/registryName
# exists and equals registryValue. Returns Current if it matches,
# NotInstalled otherwise. No UpdateAvailable state.
# In DryRun mode: returns Current with '(dry-run)' version.
# -----------------------------------------------------------------------
function Invoke-RegistryScan {
    param([Parameter(Mandatory)] [object]$App)

    $regPath  = $App.registryPath
    $regName  = $App.registryName
    $regValue = $App.registryValue

    if ($Script:DryRun) {
        Write-Log -Message "  [DRY RUN] Would check: Get-ItemProperty '$regPath' -Name '$regName'" -Level DEBUG
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = '(dry-run)'
            AvailableVersion = $null
        }
    }

    $props = Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue

    if ($props -and $props.$regName -eq $regValue) {
        return [PSCustomObject]@{
            Status           = 'Current'
            InstalledVersion = '(set)'
            AvailableVersion = $null
        }
    }

    return [PSCustomObject]@{
        Status           = 'NotInstalled'
        InstalledVersion = $null
        AvailableVersion = $null
    }
}

# -----------------------------------------------------------------------
# Private: Invoke-SingleScan
# Dispatches a single app to the correct scan function and returns
# a PSCustomObject result. Catches all exceptions -> Status='Failed'.
# -----------------------------------------------------------------------
function Invoke-SingleScan {
    param([Parameter(Mandatory)] [object]$App)

    $method = Get-ScanMethod -App $App

    try {
        switch ($method) {

            'WSL'            { return Invoke-WSLScan             -App $App }
            'WindowsFeature' { return Invoke-WindowsFeatureScan  -App $App }
            'Registry'       { return Invoke-RegistryScan        -App $App }

            # PostInstallOnly apps (powercfg-style commands): no reliable state detection
            'PostInstallOnly' {
                return [PSCustomObject]@{
                    Status           = 'NotInstalled'
                    InstalledVersion = $null
                    AvailableVersion = $null
                }
            }

            'VSCodeExtension' { return Invoke-VSCodeExtensionScan -App $App }

            'Winget'         { return Invoke-WingetScan        -App $App }
            'PSGallery'      { return Invoke-PSGalleryScan      -App $App }
            'DirectDownload' { return Invoke-DirectDownloadScan -App $App }
            'Chocolatey'     { return Invoke-ChocolateyScan     -App $App }

            default {
                Write-Log -Message "[$($App.displayName)] Unknown scan method '$method' -- reporting NotInstalled" -Level WARN
                return [PSCustomObject]@{
                    Status           = 'NotInstalled'
                    InstalledVersion = $null
                    AvailableVersion = $null
                }
            }
        }
    }
    catch {
        Write-Log -Message "[$($App.displayName)] Scan failed -- $($_.Exception.Message)" -Level WARN
        return [PSCustomObject]@{
            Status           = 'Failed'
            InstalledVersion = $null
            AvailableVersion = $null
        }
    }
}

# -----------------------------------------------------------------------
# Public: Invoke-AppScan
# Main entry point. Accepts an optional array of app objects; if omitted,
# all apps from ManifestManager are scanned.
#
# Returns a hashtable: id -> PSCustomObject{Status, InstalledVersion, AvailableVersion}
#
# Status values (match GUI badge design from DESIGN.md Section 11):
#   'NotInstalled'    -- app not found on this machine
#   'Current'         -- installed, version matches latest
#   'UpdateAvailable' -- installed, newer version exists
#   'Failed'          -- scan threw an exception
# -----------------------------------------------------------------------
function Invoke-AppScan {
    [CmdletBinding()]
    param(
        [object[]]$Apps
    )

    if (-not $Apps) {
        $Apps = Get-ManifestApps
    }

    $modeLabel = if ($Script:DryRun) { ' (DRY RUN)' } else { '' }
    Write-Log -Message "UpdateChecker: Scanning $($Apps.Count) app(s)$modeLabel..." -Level INFO

    # Reset caches for this run
    $Script:WingetCache          = $null
    $Script:WingetCacheFailed    = $false
    $Script:WslInstalledCache    = $null
    $Script:VSCodeExtensionCache = $null

    # Build winget cache once if any winget-method apps are in scope
    $wingetCount = @($Apps | Where-Object { (Get-ScanMethod -App $_) -eq 'Winget' }).Count
    if ($wingetCount -gt 0) {
        Build-WingetCache
    }
    else {
        $Script:WingetCache = @{}
        $Script:WingetCacheFailed = $false
    }

    # Build WSL cache once if any WSL-method apps are in scope
    $wslCount = @($Apps | Where-Object { (Get-ScanMethod -App $_) -eq 'WSL' }).Count
    if ($wslCount -gt 0) {
        Build-WslCache
    }
    else {
        $Script:WslInstalledCache = [System.Collections.Generic.HashSet[string]]::new()
    }

    # Build VS Code extension cache once if any VSCodeExtension-method apps are in scope
    $vscodeCount = @($Apps | Where-Object { (Get-ScanMethod -App $_) -eq 'VSCodeExtension' }).Count
    if ($vscodeCount -gt 0) {
        Build-VSCodeExtensionCache
    }
    else {
        $Script:VSCodeExtensionCache = [System.Collections.Generic.HashSet[string]]::new()
    }

    $results = @{}

    foreach ($app in $Apps) {
        Write-Log -Message "  Scanning: $($app.displayName) [$(Get-ScanMethod -App $app)]" -Level DEBUG
        $results[$app.id] = Invoke-SingleScan -App $app
    }

    # Summary
    $notInstalled    = @($results.Keys | Where-Object { $results[$_].Status -eq 'NotInstalled' }).Count
    $current         = @($results.Keys | Where-Object { $results[$_].Status -eq 'Current' }).Count
    $updateAvailable = @($results.Keys | Where-Object { $results[$_].Status -eq 'UpdateAvailable' }).Count
    $failed          = @($results.Keys | Where-Object { $results[$_].Status -eq 'Failed' }).Count

    Write-Log -Message ("UpdateChecker: Scan complete -- " +
        "Not installed: $notInstalled  Current: $current  " +
        "Updates available: $updateAvailable  Failed: $failed") -Level INFO

    return $results
}

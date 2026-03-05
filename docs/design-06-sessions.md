## APPENDIX: IMPLEMENTATION LOG

Records what was actually built each session, decisions made during implementation, and anything the next session must know. Read the relevant entry before starting the next session.

---

### Session 17 -- GitHub Actions (DONE)

**Files produced:**
- `.github/workflows/validate-manifest.yml` -- runs on every push/PR
- `.github/workflows/manifest-update.yml` -- weekly (Mon 06:00 UTC) + manual dispatch
- `.github/workflows/release.yml` -- triggers on `v*.*.*` tag push
- `.github/schemas/manifest.schema.json` -- JSON Schema (draft-07) for manifest.json
- `.github/scripts/validate-manifest.py` -- schema validation + structural checks
- `.github/scripts/check-manifest-versions.py` -- version checks + ID validation

**What each workflow does:**

validate-manifest.yml:
- Runs on every push and PR (fast, no network calls)
- Validates manifest.json against `.github/schemas/manifest.schema.json` (jsonschema)
- Checks: no duplicate IDs, all dependency references resolve, every app has an install method field
- Fails the build if any check fails

manifest-update.yml:
- Triggered weekly (Monday) and on manual dispatch
- Checks `versionCheckUrl` for every direct-download app; updates `url` from `urlTemplate` if version changed
- Validates all `wingetId` fields against the microsoft/winget-pkgs GitHub repo (using GITHUB_TOKEN)
- Validates all `psGalleryModule` fields against the PSGallery OData API
- Warnings do NOT fail the build -- surfaced in the run log for human review
- Auto-commits and pushes if manifest.json was updated; re-validates after commit

release.yml:
- Triggers on `v*.*.*` tag push
- Parses version from tag, updates version.json (version + releaseUrl), commits to main
- Builds a release zip (src/, manifest.json, version.json, bootstrap.ps1)
- Validates manifest before uploading
- Creates GitHub Release with the zip and auto-generated notes

**Implementation notes:**
- `jsonpath-ng` required for `versionCheckMethod: "json-path"` -- installed in manifest-update job
- Winget ID validation splits on the first `.` to derive publisher/package path (works for multi-dot IDs like `Python.Python.3`)
- PSGallery check looks for `<entry>` in OData feed; 0 entries = not found
- Warnings only (no build failure) for winget/PSGallery -- transient network errors should not block the weekly job
- `additionalProperties: true` on app objects in the schema -- new fields don't require schema update
- Validated locally: `python3 .github/scripts/validate-manifest.py` -- PASSED (72 apps)

**Next session:** Session 18 -- Custom App Feature (docs/design-01-overview.md row 15)

---

### Session 18 -- Custom App Feature (DONE)

**Files modified:**
- `src/Loadout.ps1` -- all new functions and button handlers added here; no new .ps1 files created

**Functions added to Loadout.ps1:**
- `Rebuild-AppListPanel` -- replaces the static startup build; called at startup and after any manifest change
- `Search-WingetApps` -- runs `winget search --name` and parses tabular output into PSCustomObjects
- `Save-UserManifest` -- merges a single app object into `%APPDATA%\Loadout\user-manifest.json`
- `Add-CustomApp` -- calls Save-UserManifest, reloads ManifestManager, rebuilds the panel with new app pre-checked
- `Show-CustomAppDialog` -- embedded XAML modal form: Display Name, Description, Category (editable ComboBox seeded from manifest), Install Method (Winget/PSGallery/DirectDownload/Chocolatey/WSL Distro), ID/URL field, Winget search box + results ListBox, Silent Args (DirectDownload only), WSL note
- `Export-LoadoutConfig` -- SaveFileDialog -> JSON with `{ exportedBy, selectedIds, customApps }`
- `Import-LoadoutConfig` -- OpenFileDialog -> merge custom apps into user-manifest.json, reload, Rebuild-AppListPanel

**Button wiring added:**
- `BtnAddCustomApp` -> Show-CustomAppDialog -> Add-CustomApp
- `BtnExport` -> Export-LoadoutConfig
- `BtnImport` -> Import-LoadoutConfig

**Tests:**
- `tests/verify-session15.ps1` -- static assertions (GUI controls, function names, wiring, APPDATA path)
- `tests/test-custom-app.ps1` -- functional: XAML validation, Search-WingetApps parser (canned output + error cases), Save-UserManifest round-trip I/O

**Implementation notes:**
- Winget search: column positions parsed from the header row (`Name`, `Id`, `Version`) to handle variable-width output
- Category ComboBox uses `IsEditable="True"` so users can type a new category not in the list
- Method switch uses `Add-Member -NotePropertyName` to add the install-method field dynamically so the PSCustomObject schema matches the main manifest format exactly
- App ID sanitized from Display Name: `.ToLower() -replace '[^a-z0-9]', '-'` then prefixed with `custom-`
- user-manifest IDs override matching main manifest IDs (same-ID entries are replaced, not duplicated)

---

### Session 19 -- Import/Export + Session Backup (DONE)

**Files modified:**
- `src/Loadout.ps1` -- all new functions added here

**Functions added to Loadout.ps1:**
- `Export-PuttySessions` -- `reg export HKCU\Software\SimonTatham\PuTTY\Sessions` to timestamped .reg file under `%APPDATA%\Loadout\SessionBackups\PuTTY\`
- `Import-PuttySessions` -- `reg import` of a selected .reg file (not used directly from dialog; dialog uses Start-Process approach)
- `Export-WinscpSessions` -- registry export if reg key found; falls back to copying `%APPDATA%\WinSCP.ini` if present
- `Import-WinscpSessions` -- .reg path uses `reg import`; .ini path uses `Copy-Item` (not used directly from dialog)
- `Export-MachineSnapshot` -- writes `$Script:LastScanResults` to a timestamped `snapshot-YYYY-MM-DD.json` under `%APPDATA%\Loadout\SessionBackups\MachineSnapshot\`
- `Import-MachineSnapshot` -- loads a snapshot JSON, pre-checks apps whose status was Current or UpdateAvailable, calls `Rebuild-AppListPanel`
- `Show-SessionBackupDialog` -- embedded XAML modal with three sections (PuTTY, WinSCP, Machine Snapshot), each with Export and Import buttons and inline status labels

**Button wiring added:**
- `BtnBackup` -> Show-SessionBackupDialog

**Tests:**
- `tests/verify-session16.ps1` -- static assertions (BtnBackup in GUI.xaml, all 7 functions defined, button wiring, registry paths, reg export/import usage, snapshot filename, Rebuild-AppListPanel call, ASCII-only check)

**Implementation notes:**
- PuTTY and WinSCP import use `Start-Process reg.exe -PassThru` + a DispatcherTimer polling loop instead of calling `reg import` synchronously -- reg.exe shows its own confirmation dialog before returning, which would freeze the WPF message pump if run synchronously
- WinSCP detection checks registry first (`HKCU:\Software\Martin Prikryl\WinSCP 2\Sessions`), then `%APPDATA%\WinSCP.ini` as fallback for portable installs
- Dialog status labels are set in code (not in XAML) to avoid XML-escaping issues with embedded path variables
- `Show-SessionBackupDialog` does not return a value; Close button calls `$dialog.Close()` not `$dialog.DialogResult`

---

### Session 20 -- README + GitHub Pages (DONE)

**Files produced/modified:**
- `README.md` -- full content written from stub (was 2 lines)
- `docs/index.html` -- already complete from Session 2; no changes needed

**README.md sections:**
- MIT license badge (shields.io)
- Project name and description
- Install one-liner (`irm https://bferguson-dev.github.io/Loadout/install | iex`) prominently at top
- Screenshots placeholder (noted as pending first public release)
- Features table
- Full app list by category (Development, VS Code Extensions, Remote Access, Browsers, Infrastructure & Cloud, API & Testing, PowerShell Modules, Network & Diagnostics, Security & Credentials, Disk & Storage, System Utilities, Windows Features, Windows Settings, WSL Distros)
- How to use USB Kit Builder (step-by-step)
- How to add custom apps (step-by-step, including winget search, export/import)
- Architecture overview (folder tree + technology notes)
- Development section (run from source, run tests, manifest validation)
- MIT license reference

---

### Session 21 -- Testing + Dry Run (DONE)

**Files produced:**
- `tests/test-config-export-import.ps1` -- round-trip functional tests for Export-LoadoutConfig / Import-LoadoutConfig
- `tests/run-all-tests.ps1` -- master runner that executes all 11 test suites in sequence

**test-config-export-import.ps1 coverage:**
- Extracts Save-UserManifest, Export-LoadoutConfig, Import-LoadoutConfig from Loadout.ps1 via AST
- Stubs Get-CheckBoxes, Get-ManifestApps, Rebuild-AppListPanel, Initialize-ManifestManager to avoid WPF dependency
- Test 1: Export with 3 selected IDs + 1 custom app -> verifies JSON fields (exportedBy, selectedIds, customApps)
- Test 2: Import round-trip -> verifies selectedIds survive JSON round-trip; verifies custom apps written to user-manifest.json
- Test 3: Export with no custom apps -> verifies empty customApps array

**run-all-tests.ps1:**
- Runs all 11 suites: parse-check, verify-logger, verify-session6, verify-session15, verify-session16, test-logger, test-install-engine, test-update-checker, test-usb-builder, test-custom-app, test-config-export-import
- Prints per-suite PASSED/FAILED lines with exit code
- Final summary: ALL N SUITES PASSED or list of failures
- Exit code 0 = all passed, non-zero = at least one suite failed
- All 11 suites pass as of this session

**Implementation notes:**
- PS 5.1 quirk: `$x = if (...) { ... } else { ... }` ternary-style assignment is valid but `@($collection)` wrapping is required after ConvertFrom-Json for single-element arrays (PS5.1 returns a PSCustomObject, not an array, for 1-element JSON arrays)
- Test isolation: each test redirects `$env:APPDATA` to a temp GUID-named directory; always restored in a `finally` block and cleaned up with `Remove-Item -Recurse -Force`

**Next session:** Project complete. Remaining work before first public release:
- Enable GitHub Pages in repo settings (source: docs/ folder on main branch)
- Push all untracked files to main branch
- Tag v1.0.0 to trigger release.yml workflow

---

### Session 1 -- manifest.json (DONE)

- 72 app entries, all required fields present
- Extended fields added beyond the spec (documented in DESIGN.md Section 6):
  - `vscodeExtensionId` for VS Code Extensions
  - `wslDistroName`, `packageManager`, `postInstallPackages`, `requiresUserSetup` for WSL Distros
  - `windowsFeatureMethod`, `windowsFeatureName` for Windows Features
  - `registryPath`, `registryName`, `registryValue`, `registryType` for Windows Settings
- Known issues to revisit: VMRC URL is version-specific (needs GitHub Actions). WSL Manager winget ID needs verification.

---

### Session 2 -- bootstrap.ps1 (DONE)

- Files: bootstrap.ps1 (repo root), version.json, docs/index.html, docs/install
- All 10 bootstrap steps implemented. Step 9 shortcuts use Read-Host stub -- WPF dialog deferred to Session 6.
- bootstrap.ps1 is standalone. It has its own Write-Status helper and never dot-sources Logger.ps1. Do not change this.
- Step 4 (winget install) sequence: GitHub API -> download msixbundle + VCLibs + UI.Xaml NuGet -> Add-AppxPackage in order.
- ASCII-only rule was discovered and enforced during this session. See Coding Standards appendix.

---

### Session 3 -- Logger.ps1 (DONE)

**Files produced:**
- `src/Logger.ps1` -- the module
- `tests/verify-logger.ps1` -- 33 spec-driven assertions, all pass

**Public API (do not change signatures):**
```powershell
Initialize-Logger [-DryRun]
Write-Log -Message <string> [-Level <INFO|OK|WARN|ERROR|DEBUG>] [-NoNewline]
```

**Script-scope state:**
```
$Script:LogFilePath  -- set by Initialize-Logger; full path to the open log file
$Script:LogPanel     -- null until Session 7 wires in the WPF control
$Script:DryRun       -- set by Initialize-Logger from the -DryRun switch
```

**Implementation decisions made during this session:**

- `$Script:LevelPad` hashtable pads all level names to 5 chars for column alignment: `'OK' -> 'OK   '`
- `$Script:LevelColor` hashtable maps levels to Write-Host foreground colors: OK=Green, WARN=Yellow, ERROR=Red, DEBUG=Gray, INFO=White
- DryRun header line gets Yellow console color (vs White for a normal session header)
- `-NoNewline` disk path uses `[System.IO.File]::AppendAllText()` to bypass `Add-Content` which always appends a newline
- WPF Dispatcher.Invoke uses `GetNewClosure()` to capture local variables (`$capturedLine`, `$capturedNoNewline`) before the scriptblock is marshaled to the UI thread. Without `GetNewClosure()` the closure captures variables by reference and they may be stale on the UI thread.
- WPF panel uses `AppendText()` + `ScrollToEnd()` -- compatible with TextBox and RichTextBox. Color-per-level in the GUI panel requires a RichTextBox and is deferred to Session 7.
- DEBUG messages are suppressed from console and GUI when `$Script:DryRun` is false, but always written to disk unconditionally. The early-return after the disk write handles this.
- Guard at top of Write-Log: if called before Initialize-Logger, warns to console and continues -- does not throw.

**What Session 4 inherits from here:**

Dot-source Logger.ps1 at the top of every new src/ module:
```powershell
# InstallEngine.ps1 does NOT dot-source Logger -- Loadout.ps1 dot-sources all modules
# in order. Logger is dot-sourced first so $Script:LogFilePath is ready.
```
All output from InstallEngine.ps1 must go through `Write-Log`. No bare `Write-Host` calls in src/.

---

### Session 4 -- Install Engine (DONE)

**Files produced:**
- `src/ManifestManager.ps1` -- manifest loading, merging, querying, plan resolution
- `src/InstallEngine.ps1` -- 5-phase install engine
- `tests/test-install-engine.ps1` -- dry-run test, all paths verified

**Public API -- ManifestManager (do not change signatures):**
```powershell
Initialize-ManifestManager [-ManifestPath <string>] [-UserManifestPath <string>]
Get-ManifestApps
Get-AppById -Id <string>
Get-AppsByCategory -Category <string>
Get-PrerequisiteApps
Resolve-InstallPlan -SelectedIds <string[]>
```

**Public API -- InstallEngine (do not change signatures):**
```powershell
Invoke-InstallPlan -Apps <object[]>   # returns hashtable: id -> 'Success'|'Failed'|'Skipped'|'Deferred'
Get-InstallResults                    # returns hashtable from most recent run
```

**Script-scope state (InstallEngine):**
```
$Script:InstallResults   -- id -> result string, reset each Invoke-InstallPlan call
$Script:FailedPrereqIds  -- HashSet of prereq IDs that failed; used to skip dependents
```

**Phase summary:**
```
Phase 1 -- isPrerequisite:true apps (any install method), silent
Phase 2 -- non-prereq Winget + PSGallery + Chocolatey apps
Phase 3 -- non-prereq DirectDownload apps
Phase 4 -- WSL distros (DEFERRED to Session 10)
Phase 5 -- postInstallCommands for all Success apps
```

**Implementation decisions made during this session:**

- `Get-InstallMethod` determines primary install method with this priority:
  WSL > WindowsFeature > Registry > VSCodeExtension > Winget > PSGallery > DirectDownload > Chocolatey
- `$Script:DryRun` is NOT defined in InstallEngine -- it is read from Logger's script-scope
  (shared scope after dot-sourcing). Initialize-Logger must be called first.
- `Resolve-InstallPlan` uses a nested recursive function `Resolve-AppById` + a `$visited` hashtable
  to do depth-first dependency expansion. Modifying the hashtable from the inner function works
  because we call `.Item()` on the existing object (reference type) -- not a variable rebind.
- `Test-DependenciesMet` checks both `$Script:FailedPrereqIds` (for prereq failures) and
  `$Script:InstallResults[$depId] -eq 'Failed'` (for non-prereq dependency failures).
- Chocolatey: skipped with WARN until GUI confirmation is implemented in Session 8.
  If a Chocolatey app is also `isPrerequisite:true`, its ID IS added to `$Script:FailedPrereqIds`
  so its dependents are correctly skipped.
- Phase 5 filter: only runs postInstallCommands for `'Success'` results.
  `-or $Script:DryRun` was deliberately NOT used -- dry-run apps are marked 'Success' by
  Invoke-SingleApp so the filter already catches them.
- `ManifestPath` default: `Join-Path (Split-Path $PSScriptRoot -Parent) 'manifest.json'`.
  Works correctly whether called from `src/` (Loadout.ps1) or `tests/` (test scripts)
  because $PSScriptRoot in PS5.1 reflects the calling script's directory at invocation time.
- Deferred methods (WSL, WindowsFeature, Registry, VSCodeExtension) result in 'Deferred',
  not 'Failed' or 'Skipped', so the failure report can distinguish them.

**Bugs found and fixed during verification:**
- Chocolatey prereq skip returned before the `if ($App.isPrerequisite)` block in `catch` --
  fixed by adding the `FailedPrereqIds` check directly in the Chocolatey switch arm.
- Phase 5 used `-or $Script:DryRun` which would run post-install for Deferred/Skipped apps -- removed.
- `$IsPrerequisitePhase` parameter was declared but never read -- removed.

**What Session 5 must know:**

Session 5 builds `src/UpdateChecker.ps1`. It needs ManifestManager loaded before it runs.
See "What Session 5 inherits" section below.

---

### What Session 5 inherits from Sessions 1-4

Session 5 builds the Update Checker (`src/UpdateChecker.ps1`). Read Section 10 of this document
before starting. Key points:

**What to build:**
Create `src/UpdateChecker.ps1` with one public entry point:
```powershell
Invoke-AppScan [-Apps <object[]>]   # if omitted, scans all apps from ManifestManager
```
Returns a hashtable: `id -> [PSCustomObject]@{ Status='...'; InstalledVersion='...'; AvailableVersion='...' }`

Status values (match the GUI badge design from Section 11 exactly):
```
'NotInstalled'   -- app not found on this machine
'Current'        -- installed, version matches latest
'UpdateAvailable' -- installed, newer version exists
'Failed'         -- check threw an exception
```

**Per-method scan logic (from Section 10):**

| Method | How to check |
|---|---|
| Winget | `winget list --id <ID>` -- parse output for installed/available version columns |
| PSGallery | `Get-InstalledModule -Name <mod>` vs `Find-Module -Name <mod>` |
| DirectDownload | Read installedVersionPath (registry uninstall key) vs versionCheckUrl in manifest |
| Chocolatey | `choco list --local-only <id>` -- only if choco.exe exists |
| Deferred methods | Return 'NotInstalled' without checking (WSL/Feature/Registry/VSCodeExtension handled in later sessions) |

**Winget output parsing note:**
`winget list --id <ID>` writes a table to stdout. The columns are Name, Id, Version, Available,
Source. Parse with a regex or split -- the 'Available' column is empty if up to date.
Winget may write progress/spinner chars to stderr; redirect stderr to $null.
Run as: `winget list --id <ID> --accept-source-agreements 2>$null`

**DirectDownload version check:**
The `installedVersionPath` field in the manifest is a registry path under
`HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\` (or the Wow6432Node equivalent).
Read the `DisplayVersion` value. Compare against whatever `versionCheckUrl` returns
(method in `versionCheckMethod` field: github-api, json-path, regex, or version-file).
For Session 5, implement github-api and skip the others with a WARN.

**Performance note:**
Winget is slow to start. Run one `winget list` call for ALL winget apps (no --id filter) and
parse the full output table once, rather than spawning winget once per app. Cache the result
in a script-scope variable for the run.

**Test script:**
Create `tests/test-update-checker.ps1`. Dot-source Logger, ManifestManager, UpdateChecker.
Initialize-Logger -DryRun. Scan a small subset of apps (4-5: one winget, one PSGallery,
one DirectDownload, one deferred method). Print the status table. No actual network calls
needed if you mock or skip versionCheckUrl lookups -- just test that the scan runs and
returns the correct structure without throwing.

**Do NOT build in Session 5:**
- Scheduled Task Scheduler scan (Session 18)
- update-cache.json writing/reading (Session 18)
- GUI status badge wiring (Session 7)
- UpdateAll / UpdateSelected button logic (Session 7)

---

### Session 5 Implementation Log (Update Checker -- COMPLETE)

**Files produced:**
- `src/UpdateChecker.ps1`
- `tests/test-update-checker.ps1`

**Public API -- UpdateChecker (do not change signatures):**
```powershell
Invoke-AppScan [-Apps <object[]>]
# Returns hashtable: id -> PSCustomObject@{ Status; InstalledVersion; AvailableVersion }
# Status values: 'NotInstalled' | 'Current' | 'UpdateAvailable' | 'Failed'
# If -Apps omitted, calls Get-ManifestApps automatically.
```

**Script-scope state (UpdateChecker):**
```
$Script:WingetCache  -- id.ToLower() -> PSCustomObject{Id, Version, Available}
                        $null until Build-WingetCache runs; reset to $null at start of each Invoke-AppScan call
```

**Implementation decisions made during this session:**

- `Get-ScanMethod` mirrors `Get-InstallMethod` from InstallEngine exactly -- same priority order.
  WSL > WindowsFeature > Registry > VSCodeExtension > Winget > PSGallery > DirectDownload > Chocolatey > Unknown
- `$Script:DryRun` is NOT defined in UpdateChecker -- read from Logger's shared script-scope after dot-sourcing.
- Winget: ONE `winget list --accept-source-agreements 2>$null` call per `Invoke-AppScan`. Output is a
  fixed-width table. Parser finds the header row (contains Id, Version, Available), derives column start
  positions via `String.IndexOf`, then extracts fields with `Get-ColumnValue` (uses `[Math]::Min` to bound
  Substring safely). Result cached in `$Script:WingetCache` keyed by `wingetId.ToLower()`.
  `Available` column non-empty = UpdateAvailable; empty = Current.
- PSGallery: `Get-InstalledModule` vs `Find-Module`. Comparison uses `[Version]` cast first; falls back
  to string compare if version string is non-semver.
- DirectDownload: `installedVersionPath` in manifest is the HKLM Uninstall parent path, not a direct key.
  `Get-DirectDownloadInstalledVersion` tries the path directly first, then searches subkeys matching
  `DisplayName -like "*$($App.displayName)*"` and reads `DisplayVersion`.
  Only `versionCheckMethod = 'github-api'` is implemented; others log WARN and report Current.
  `Get-GitHubLatestVersion` calls `Invoke-RestMethod`, reads `tag_name`, strips leading 'v'.
- Chocolatey: gated on `Get-Command 'choco.exe'`; parses `choco list --local-only` output (format: "Id Version").
  Upgrade detection NOT implemented (choco scan only reports NotInstalled vs Current -- no Available version).
- Deferred methods (WSL, WindowsFeature, Registry, VSCodeExtension): return `NotInstalled` with no registry
  or network calls. These will be revisited when their respective sessions implement scanning.
- DryRun: all external calls (winget, PSGallery network, registry, choco) skipped in each scan function.
  Winget: cache left as empty `@{}`. PSGallery/DirectDownload/Choco: return Current with '(dry-run)' versions.
- `Invoke-SingleScan` wraps each dispatch in try/catch -- any unhandled exception becomes Status='Failed'.

**Bugs found and fixed during verification:**
- Inline `if`/`elseif` expression inside a `-f` format operator call in the test script caused a
  `ParserError: Missing closing ')'`. PowerShell cannot parse a conditional block as an inline argument.
  Fixed by pre-computing the method label on its own line before the format call.
- Inline `pwsh -Command "..."` from bash: `$` in PowerShell variable names was expanded by bash before
  reaching pwsh. Fixed by writing verification logic to a temporary `.ps1` file and using `pwsh -File`.

---

### Session 6 Implementation Log (WPF GUI Shell -- COMPLETE)

**Files produced:**
- `src/GUI.xaml` -- WPF window layout
- `src/Loadout.ps1` -- entry point script
- `tests/verify-session6.ps1` -- 32 static assertions (no window needed), all pass

**Named controls (do not rename -- Session 7+ reference these by x:Name):**
```
BtnCheckUpdates    -- top bar, triggers update scan (Session 7)
LblVersion         -- top bar, populated from version.json at startup
StatusBar          -- very bottom strip, TextBlock
ProgressItem       -- item-level progress bar (Session 7)
ProgressOverall    -- overall progress bar (Session 7)
BtnSelectAll       -- bottom bar
BtnDeselectAll     -- bottom bar
BtnUpdateAll       -- bottom bar (Session 7)
BtnUpdateSelected  -- bottom bar (Session 7)
BtnCommit          -- bottom bar, triggers commit flow (Session 8)
BtnBuildUsb        -- bottom bar (Session 16)
AppListPanel       -- StackPanel inside ScrollViewer, left panel
LogPanel           -- TextBox (ReadOnly, Consolas 11pt), right panel
```
Settings button is also present in the XAML bottom bar but has no x:Name (deferred past Session 10).

**Layout structure:**
```
Window (DockPanel root)
  Border [Top]       -- top bar: title, LblVersion, BtnCheckUpdates
  Border [Bottom]    -- StatusBar
  Border [Bottom]    -- progress area: ProgressItem, ProgressOverall with labels
  Border [Bottom]    -- button bar: all 6 named buttons + Settings
  Grid (fills remaining space)
    Column 0         -- ScrollViewer > StackPanel[AppListPanel]
    Column 1         -- GridSplitter (draggable, 3px)
    Column 2         -- TextBox[LogPanel]
```

**App checklist population (Loadout.ps1):**
- Uses a `HashSet[string]` to track seen categories and emit each header exactly once
- Category order follows manifest order (first occurrence wins) -- NOT alphabetical
- Per category: TextBlock header (blue #5CB8FF, SemiBold 12pt) + Separator
- Per app: CheckBox with `Content=displayName`, `Tag=app.id`, `ToolTip=app.description`
- Spacer TextBlock (Height=6) inserted before every category header except the first

**XAML loading pattern (locked in -- do not change):**
```powershell
Add-Type -AssemblyName PresentationFramework
$xaml = [System.Xml.XmlDocument]::new()
$xaml.Load("$PSScriptRoot\GUI.xaml")
$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)
```

**Logger wiring (already done -- do not redo):**
```powershell
$Script:LogPanel = $window.FindName('LogPanel')
```
This line in Loadout.ps1 activates the WPF output path in Logger.ps1. From this point on,
every `Write-Log` call appends to the TextBox via `Dispatcher.Invoke`. No change needed in Logger.ps1.

**Module dot-source order (do not change):**
```powershell
. "$PSScriptRoot\Logger.ps1"
. "$PSScriptRoot\ManifestManager.ps1"
. "$PSScriptRoot\InstallEngine.ps1"
. "$PSScriptRoot\UpdateChecker.ps1"
```
Logger must be first. The other three read `$Script:DryRun` from Logger's shared scope.

**Implementation decisions made during this session:**
- `LogPanel` is the TextBox itself (no ScrollViewer wrapper) -- Logger calls `AppendText()` and
  `ScrollToEnd()` which are TextBox methods. The TextBox has its own built-in scroll.
- `BrushConverter.ConvertFromString('#5CB8FF')` used for category header color -- avoids
  hardcoding a media color name and makes it easy to change the palette later.
- `$window.ShowDialog()` used (not `Show()`) -- blocks the script thread until the window closes,
  which is correct for a single-window PS5.1 application with no background runspace yet.
- Dark theme colors: Window bg #1E1E1E, panel bg #2D2D2D, borders #3A3A3A, log bg #141414.
  These are not in a resource dictionary -- they are inline. Centralizing into a ResourceDictionary
  is possible but not worth the complexity for a single-window app.

**Bugs found and fixed during verification:**
- `verify-session6.ps1` initially used `$content.IndexOf('ManifestManager.ps1')` to check module
  order, which matched the comment text before the actual dot-source line. Fixed by searching for
  dot-source lines specifically with `Select-String '^\. .*ModuleName\.ps1'`.
- Inline `(if (...) { } else { })` as a `-ForegroundColor` argument value causes a parser error in
  PowerShell. Fixed by assigning the result to `$color` first, then passing `$color`.

---

### What Session 7 inherits from Sessions 1-6

Session 7 wires the GUI shell to the Install Engine and Update Checker. Read Section 11 and the
Session 4, 5, and 6 implementation logs before starting.

**What to build:**

All wiring lives in `src/Loadout.ps1`. Do NOT modify `GUI.xaml` or any other src/ module.
Add event handlers and startup logic after the existing checklist population block.

**1. Startup scan:**

On window load (`$window.Add_Loaded`), run `Invoke-AppScan` in a PowerShell background runspace
(not a job -- use `[System.Management.Automation.PowerShell]::Create()`). When the scan completes,
marshal results back to the UI thread via `$window.Dispatcher.Invoke` and:
- Pre-check each `CheckBox` in `AppListPanel` whose scan result is `Current` or `UpdateAvailable`
  (i.e., the app is already installed)
- Update `StatusBar` text: "X updates available" (or "All apps up to date")

**2. Select All / Deselect All:**

```powershell
$window.FindName('BtnSelectAll').Add_Click({
    foreach ($child in $appListPanel.Children) {
        if ($child -is [System.Windows.Controls.CheckBox]) { $child.IsChecked = $true }
    }
})
```
Mirror for BtnDeselectAll (`$false`).

**3. Update All / Update Selected:**

- Update All: check every CheckBox whose scan Status is `UpdateAvailable`, then run Invoke-InstallPlan
  with those apps. Use a background runspace (same pattern as scan). Wire ProgressOverall and
  ProgressItem to engine callbacks (see point 5 below).
- Update Selected: same, but only for apps that are both checked AND `UpdateAvailable`.

**4. Check for Updates button (BtnCheckUpdates):**

Re-runs `Invoke-AppScan` on demand (same runspace pattern as startup scan). Updates StatusBar and
CheckBox pre-checks when done.

**5. Progress bar wiring:**

`Invoke-InstallPlan` does not currently have progress callbacks -- you will need to add them.
Add two optional scriptblock parameters to `Invoke-InstallPlan`:
```powershell
param(
    [object[]]$Apps,
    [scriptblock]$OnItemStart,   # called with ($appIndex, $totalApps, $appDisplayName)
    [scriptblock]$OnItemDone     # called with ($appIndex, $totalApps, $result)
)
```
In Loadout.ps1, pass scriptblocks that dispatch to the UI thread and update `ProgressItem` and
`ProgressOverall`. ProgressItem resets to 0 at the start of each app; pulses to 100 on completion.

**6. Log panel color per level (RichTextBox upgrade):**

Logger.ps1 currently uses `AppendText()` which works on both TextBox and RichTextBox.
To get color-per-level output, swap `LogPanel` from TextBox to RichTextBox in GUI.xaml and update
Logger.ps1's WPF path to append `System.Windows.Documents.Run` elements with foreground color.
Color map: INFO=White, OK=#00D26A, WARN=#FFB900, ERROR=#E74856, DEBUG=#888888.
If this adds significant complexity, defer and keep the plain TextBox for now.

**Do NOT build in Session 7:**
- Commit button / commit preview dialog (Session 8)
- Uninstall model (Session 9)
- Settings gear (deferred past Session 10)
- USB Kit builder (Session 16)

**Test:**
No separate test script. Run `src/Loadout.ps1`, verify:
1. Window opens, scan runs in background, CheckBoxes pre-check for installed apps
2. StatusBar shows correct update count
3. Select All / Deselect All work
4. BtnCheckUpdates triggers a re-scan and updates the UI

---

### Session 7 Implementation Log

**Files modified:**
- `src/InstallEngine.ps1` -- added progress callback support
- `src/GUI.xaml` -- upgraded LogPanel from TextBox to RichTextBox
- `src/Logger.ps1` -- updated WPF path to append colored Run elements
- `src/Loadout.ps1` -- wired all GUI event handlers and background runspace helpers

**Public API changes:**

`Invoke-InstallPlan` now accepts two optional scriptblock parameters:
```powershell
Invoke-InstallPlan -Apps <object[]> [-OnItemStart <scriptblock>] [-OnItemDone <scriptblock>]
```
- `OnItemStart` called before each app: `($index, $total, $displayName)`
- `OnItemDone` called after each app: `($index, $total, $result)`
- Callbacks stored in `$Script:OnItemStart`, `$Script:OnItemDone`, `$Script:ProgressIndex`, `$Script:ProgressTotal` (reset each run)
- Existing callers with no callbacks continue to work unchanged (verified by all Session 4 tests passing)

**Script-scope state added to Loadout.ps1:**
- `$Script:LastScanResults` -- hashtable from the most recent `Invoke-AppScan` call; used by Update All / Update Selected handlers

**Helper functions added to Loadout.ps1:**
- `Get-CheckBoxes` -- returns all CheckBox children of AppListPanel
- `Apply-ScanResults` -- unwraps PSObject, caches to `$Script:LastScanResults`, pre-checks installed apps, updates StatusBar
- `Start-BackgroundRunspace` -- launches a PS runspace async and polls with a 250ms DispatcherTimer; calls `$OnComplete` with last output PSObject on the UI thread
- `Build-ScanScriptText` -- returns the scan runspace script string (dot-sources all modules, runs Invoke-AppScan)
- `Run-UpdateInBackground` -- builds install runspace with progress queue injected via SessionStateProxy; 100ms DispatcherTimer drains queue and updates ProgressItem/ProgressOverall

**Implementation decisions made during this session:**

1. **DispatcherTimer polling instead of AsyncCallback**: `PowerShell.BeginInvoke()` overloads with `AsyncCallback` require generics that are awkward to call from PS5.1. The DispatcherTimer approach polls every 250ms (scan) / 100ms (install), runs entirely on the UI thread, and avoids all cross-thread marshaling complexity.

2. **ConcurrentQueue for progress messages**: The background install runspace cannot call `Dispatcher.Invoke` (no `$window` in scope). The queue is injected via `$rs.SessionStateProxy.SetVariable('progressQueue', ...)`, then referenced as `$progressQueue` inside the script string. The UI timer drains it.

3. **RichTextBox LogPanel**: Swapped `TextBox` to `RichTextBox` in GUI.xaml. Logger.ps1 now builds `System.Windows.Documents.Run` elements with per-level hex foreground colors and appends to `$Script:LogPanel.Document.Blocks[0]`. `BrushConverter` is instantiated inline in the dispatcher scriptblock (not at module-load time) to avoid loading WPF types before `Add-Type` runs in Loadout.ps1.

4. **PSObject unwrapping in Apply-ScanResults**: The scan hashtable passes through the runspace output pipeline and arrives wrapped in a PSObject. `Apply-ScanResults` checks `$ScanResults.BaseObject` to unwrap it before calling `.ContainsKey()`.

5. **GetNewClosure() on Add_Loaded and BtnCheckUpdates**: These handlers reference `$window` and the helper functions defined earlier in the script. `GetNewClosure()` is used to ensure variable capture if the event fires in a different scope context.

6. **First installText assignment removed**: The initial `$installText` variable (using `$args[0]`) was dead code immediately overwritten. Removed to avoid reader confusion.

**Bugs found and fixed during implementation:**
- `$Script:BrushConverter = [System.Windows.Media.BrushConverter]::new()` at Logger.ps1 module scope would execute before `Add-Type -AssemblyName PresentationCore` in Loadout.ps1, causing a type-not-found error. Fixed by removing the module-scope init and instantiating `BrushConverter` inline inside the Dispatcher callback (which only runs after the GUI is loaded).
- Dead `$installText` block with wrong `$args[0]` approach removed.
- `Join-Path` with 3 path args fails in PS5.1 (requires PS6+). Fixed in parse-check.ps1 helper by nesting two `Join-Path` calls.
- `[double]::MaxValue` is rejected by `FlowDocument.PageWidth` validation. Fixed by using `10000` (device-independent units, ~104 inches).
- `$Script:LogPanel` inside a `GetNewClosure()` closure resolves to Logger.ps1's OWN script scope (where it is `$null`), not Loadout.ps1's scope where it was assigned. This caused `Dispatcher.Invoke` to throw "You cannot call a method on a null-valued expression" silently caught and falling through to console. Fixed by capturing `$Script:LogPanel` as a local variable (`$capturedPanel`) before the closure -- `GetNewClosure()` captures locals reliably. This same bug existed in Session 6 but was not detected because the Session 6 test did not verify log panel output.
- RichTextBox `<RichTextBox.Document>` inline XAML with a named `Paragraph` and `GetFirstBlock` pipeline approach was unreliable. Simplified to: let WPF create the default FlowDocument, set `PageWidth`/`PagePadding` in code, and append a fresh `Paragraph` per `Write-Log` call instead of finding the first block.

**What Session 8 inherits / needs to know:**
- `$Script:LastScanResults` is populated after each scan; use it in the Commit preview to show current vs available versions
- `BtnCommit` click handler is not yet wired -- Session 8 adds the commit preview dialog
- `Run-UpdateInBackground` uses `Initialize-Logger` (not DryRun) in the runspace; real winget calls will fire in non-DryRun mode
- The RichTextBox LogPanel uses `Document.Blocks | Select-Object -First 1` to get the paragraph; if the document is ever reset, this reference stays valid as long as a Paragraph is present
- Progress bars reset to 0 at the start of each update run and pulse to 100 on completion; no persistent state between runs

---

### Session 8 Implementation Log

**Files modified:**
- `src/InstallEngine.ps1` -- added `$Script:AllowChocolatey`, `Invoke-ChocolateyInstall`, `-AllowChocolatey` param to `Invoke-InstallPlan`; replaced Chocolatey stub
- `src/Loadout.ps1` -- added `Build-CommitPlan`, `Show-CommitPreviewDialog`; wired `BtnCommit`; extended `Run-UpdateInBackground` with `-AllowChocolatey`

**Public API changes:**

`Invoke-InstallPlan` now accepts an optional boolean parameter:
```powershell
Invoke-InstallPlan -Apps <object[]> [-OnItemStart <scriptblock>] [-OnItemDone <scriptblock>] [-AllowChocolatey <bool>]
```
- `AllowChocolatey` defaults to `$false`; existing callers are unchanged
- When `$true`, Chocolatey apps are installed via `Invoke-ChocolateyInstall` rather than skipped

**Script-scope state added to InstallEngine.ps1:**
- `$Script:AllowChocolatey` -- gates Chocolatey installs; set from `Invoke-InstallPlan` param each run

**Functions added to Loadout.ps1:**
- `Build-CommitPlan` -- inspects checked checkboxes and `$Script:LastScanResults`; calls `Resolve-InstallPlan`; returns `PSCustomObject{ToInstall, ToUpdate, ImplicitDeps, FullPlan, HasChocolatey, IsEmpty}`
- `Show-CommitPreviewDialog -Plan` -- creates a dark-themed WPF modal Window from inline XAML; populates sections (To Install, To Update, Also required, Chocolatey warning) using scriptblock helpers; returns `$true` on Confirm, `$false` on Cancel/close

**`Run-UpdateInBackground` changes:**
- Added `[bool]$AllowChocolatey = $false` parameter
- Injects `$allowChocolatey` into the runspace via `SessionStateProxy.SetVariable`
- Passes `-AllowChocolatey $allowChocolatey` to `Invoke-InstallPlan` in the script string

**Implementation decisions made during this session:**

1. **`Build-CommitPlan` splits by scan status**: Checked apps with `UpdateAvailable` go to ToUpdate; `NotInstalled`/`Failed`/no-data go to ToInstall; `Current` are silently skipped. The full plan (with deps) is resolved once for the preview and the dep partition appears as `ImplicitDeps`.

2. **Commit button passes only ToInstall+ToUpdate to `Run-UpdateInBackground`**: The runspace re-runs `Resolve-InstallPlan` on those IDs, re-deriving the same dep set. This is intentionally idempotent rather than serializing the full pre-resolved plan.

3. **`$AllowChocolatey` injected via SessionStateProxy**: The same pattern used for `$progressQueue`. The bool is injected before the runspace script runs and referenced as `$allowChocolatey` (unescaped) inside the script string.

4. **WPF dialog built from inline XAML string (here-string)**: No separate .xaml file. Keeps the dialog self-contained in Loadout.ps1. The panel is populated in code after loading via `XamlReader::Load`, consistent with the Session 6 main window pattern.

5. **`DialogResult` pattern for modal result**: `BtnConfirm.Add_Click` sets `$dialog.DialogResult = $true` (which auto-closes the window); `BtnCancel` sets `$false`. `ShowDialog()` return value is compared to `$true` and the bool result is returned to the caller.

6. **Chocolatey warning is informational only**: The commit preview shows the warning but does not require a separate checkbox or extra confirm step. If `HasChocolatey` is `$true` and the user clicks Confirm, the Chocolatey gate opens for that run.

**Bugs found and fixed during implementation:**
- None; parse check and install engine test suite passed on first attempt.

**What Session 9 inherits / needs to know:**
- `BtnCommit` is fully wired; Session 9 adds the **uninstall model** (unchecked installed apps shown in commit preview as "To Uninstall"; `winget uninstall` or `Remove-Module` called)
- `Build-CommitPlan` currently ignores unchecked apps that are installed (Current status); Session 9 adds a `ToUninstall` partition to the commit plan
- `Invoke-ChocolateyInstall` is a thin wrapper; it does not bootstrap Chocolatey itself -- if `choco.exe` is absent, it throws. A Chocolatey bootstrapper step (download + install from chocolatey.org) may be needed before Session 9 or deferred alongside the uninstall model
- `Run-UpdateInBackground` is the shared entry point for all installs/updates -- its signature must remain stable for Session 9 additions

---

### Session 9 Implementation Log

**Files modified:**
- `src/InstallEngine.ps1` -- added `$Script:UninstallResults`; private uninstall helpers `Invoke-WingetUninstall`, `Invoke-PSGalleryUninstall`, `Invoke-DirectDownloadUninstall`, `Invoke-ChocolateyUninstall`, `Invoke-SingleAppUninstall`; public `Invoke-UninstallPlan` and `Get-UninstallResults`
- `src/Loadout.ps1` -- extended `Build-CommitPlan` with `ToUninstall` + `OrphanedPrereqs` partitions; added ToUninstall/OrphanedPrereqs sections to `Show-CommitPreviewDialog`; rewrote `Run-UpdateInBackground` to support `AppsToUninstall` param with phase-switching progress; updated `BtnCommit` handler
- `tests/test-install-engine.ps1` -- added `Invoke-UninstallPlan` dry-run section with per-method assertions

**Public API added to InstallEngine.ps1:**
```powershell
Invoke-UninstallPlan -Apps <object[]> [-OnItemStart <scriptblock>] [-OnItemDone <scriptblock>]
Get-UninstallResults
```
- `Invoke-UninstallPlan` resets `$Script:UninstallResults`, `$Script:ProgressIndex`, `$Script:ProgressTotal`, `$Script:OnItemStart/OnItemDone` (shared with install engine); returns `id -> result` hashtable
- Supported methods: Winget (`winget uninstall --id <ID> --silent --accept-source-agreements`), PSGallery (`Uninstall-Module -AllVersions -Force`), DirectDownload (reads `QuietUninstallString` or `UninstallString` from HKLM Uninstall registry, parses exe+args), Chocolatey (`choco uninstall <ID> -y`)
- Deferred methods (WSL, WindowsFeature, Registry, VSCodeExtension): logged as WARN + result = `Skipped`

**Script-scope state added to InstallEngine.ps1:**
- `$Script:UninstallResults` -- id -> `Success` | `Failed` | `Skipped`; reset at the start of each `Invoke-UninstallPlan` call

**`Build-CommitPlan` changes:**
- Added `ToUninstall` partition: unchecked checkboxes whose scan status is `Current` or `UpdateAvailable`
- Added `OrphanedPrereqs` partition: installed prereqs that no remaining installed app will depend on after the planned uninstall (computed from manifest dependency data + `$Script:LastScanResults`)
- `IsEmpty` now requires `ToInstall + ToUpdate + ToUninstall + OrphanedPrereqs` all empty
- `Resolve-InstallPlan` only called when `$combinedIds.Count > 0`; returns `@()` otherwise
- Added `ToUninstall` and `OrphanedPrereqs` fields to returned `PSCustomObject`

**`Show-CommitPreviewDialog` changes:**
- Added "To Uninstall" section (`#E74856` red) after ImplicitDeps
- Added "Orphaned Prerequisites" section (`#FFB900` yellow) after ToUninstall

**`Run-UpdateInBackground` changes:**
- Added `[object[]]$AppsToUninstall = @()` param
- Now accepts empty `$AppsToUpdate` (pure uninstall runs are valid)
- Builds `$uninstallBlock` and `$installBlock` as separate script strings embedded in a shared here-string; either may be empty
- Enqueues `PHASE:N` between uninstall and install phases so the progress denominator switches correctly
- `$capturedTotalRef` is a single-element array (mutable from within `GetNewClosure()`) initialized to whichever phase runs first; updated on `PHASE` message
- Status bar text summarizes both phases; completion message changed from "Update complete." to "Operation complete."

**`BtnCommit` handler changes:**
- `$appsToUninstall = @($plan.ToUninstall) + @($plan.OrphanedPrereqs)` passed to `Run-UpdateInBackground -AppsToUninstall`
- Commit log message now includes uninstall count

**Implementation decisions made during this session:**

1. **DryRun in `Invoke-DirectDownloadUninstall`**: Registry lookup is skipped entirely in DryRun mode (early return before any `Get-ItemProperty` call). This avoids false failures in test environments where the app is not installed and keeps DryRun behavior consistent with `Invoke-DirectDownloadInstall` (which also skips all I/O).

2. **`QuietUninstallString` preferred over `UninstallString`**: If the registry entry has a `QuietUninstallString`, it is used (already includes silent flags). Otherwise `UninstallString` is used as-is. No additional silent args are appended to avoid conflicting flags.

3. **Orphaned prereq computation is deterministic and shown in the commit preview**: Rather than a post-execution prompt (as the design doc implied with "after uninstall"), orphaned prereqs are computed up front in `Build-CommitPlan` using `$Script:LastScanResults` and manifest dependency data. This lets the user see and confirm the full scope of removals in one dialog. The computation is: installed prereqs whose ID does not appear in the dependency list of any app that will remain installed after the planned uninstall.

4. **`$capturedTotalRef` mutable array pattern**: The DispatcherTimer closure captures variables by value at `GetNewClosure()` time. Using a single-element array `@(N)` allows the timer tick handler to update the progress denominator when a `PHASE:N` message arrives, without requiring a `[ref]` parameter or script-scope variable that would be invisible from within the closure.

5. **`Run-UpdateInBackground` signature change is backwards-compatible**: Both `$AppsToUpdate` and `$AppsToUninstall` default to `@()`. Existing callers (`BtnUpdateAll`, `BtnUpdateSelected`) that pass only `-AppsToUpdate` are unaffected.

**Bugs found and fixed during implementation:**
- None; parse check and test suite passed on first attempt.

**What Session 10 inherits / needs to know:**
- `Invoke-UninstallPlan` is the counterpart to `Invoke-InstallPlan`; both share `$Script:ProgressIndex/Total/OnItemStart/OnItemDone` state (reset at the start of each call)
- WSL uninstall returns `Skipped` with a warning; Session 10 adds both WSL install and WSL uninstall (`wsl --unregister <distroName>`)
- The `BtnCommit` flow is now fully wired for install + update + uninstall; Session 10 adds only the WSL implementation behind the existing deferred guard

---

### Session 10 Implementation Log

**Files modified:**
- `src/InstallEngine.ps1` -- added `Invoke-WSLPostInstall`, `Invoke-WSLInstall`, `Invoke-WSLUninstall`; removed WSL from `$deferredMethods` in `Invoke-SingleApp`; added WSL case to `Invoke-SingleApp` switch; added WSL to `$uninstallable` and switch in `Invoke-SingleAppUninstall`; replaced Phase 4 deferred stub with real loop
- `src/UpdateChecker.ps1` -- added `$Script:WslInstalledCache`, `Build-WslCache`, `Invoke-WSLScan`; wired WSL in `Invoke-SingleScan`; reset and build WSL cache in `Invoke-AppScan`
- `tests/test-install-engine.ps1` -- updated WSL uninstall assertion from `Skipped` to `Success`; updated comments

**Private functions added to InstallEngine.ps1:**

`Invoke-WSLPostInstall -App`:
- Builds update + install argument arrays for `apt` or `dnf` depending on `$App.packageManager`
- Runs `wsl -d <distroName> -u root -- <pm> update` then `wsl -d <distroName> -u root -- <pm> install -y <packages>`
- Packages taken from `$App.postInstallPackages` (string array in manifest)
- DryRun: logs both commands and returns early

`Invoke-WSLInstall -App`:
- Runs `wsl --set-default-version 2` (non-fatal if exit code != 0 -- logs WARN and continues)
- Runs `wsl --install -d <wslDistroName> --no-launch` (throws on non-zero exit)
- If `postInstallPackages` present: calls `Invoke-WSLPostInstall`
- DryRun: logs all three steps (calling `Invoke-WSLPostInstall` in DryRun also logs package commands)

`Invoke-WSLUninstall -App`:
- Runs `wsl --unregister <wslDistroName>` (throws on non-zero exit)
- DryRun: logs command and returns early

**Private functions added to UpdateChecker.ps1:**

`Build-WslCache`:
- Temporarily sets `[Console]::OutputEncoding = Unicode` to handle WSL's UTF-16LE output
- Runs `wsl --list --quiet`, strips residual null bytes, builds `$Script:WslInstalledCache` (HashSet, OrdinalIgnoreCase)
- DryRun: logs command and leaves cache empty

`Invoke-WSLScan -App`:
- Checks `$Script:WslInstalledCache.Contains($App.wslDistroName)`
- Installed: returns `Current` with `InstalledVersion = '(installed)'`
- Not installed: returns `NotInstalled`
- No UpdateAvailable state -- WSL distros are rolling, no version comparison

**Invoke-AppScan changes:**
- Resets `$Script:WslInstalledCache = $null` at start of each scan
- Calls `Build-WslCache` if any WSL-method apps are in scope; otherwise initializes to empty HashSet

**Implementation decisions made during this session:**

1. **`--no-launch` flag**: Used with `wsl --install -d <name>` to prevent the first-time setup wizard from opening in a non-interactive background runspace. On older WSL versions that don't support `--no-launch`, the install will fail with a clear error message (caught by `Invoke-SingleApp`'s try/catch).

2. **Post-install packages run as root (-u root)**: Fresh WSL distros allow root login via `wsl -d <name> -u root` before user setup is complete. All `postInstallPackages` are installed this way, avoiding the `requiresUserSetup` blocking issue.

3. **`wsl --set-default-version 2` is non-fatal**: If it fails (e.g., on a system where WSL is not yet fully enabled), a WARN is logged and the distro install continues. The distro install itself will fail if WSL isn't available, producing the real error.

4. **WSL cache encoding**: `wsl --list --quiet` outputs UTF-16LE. Temporarily overriding `[Console]::OutputEncoding` to `Unicode` before the call ensures correct decoding in PS5.1 background runspaces where the console encoding may not be set.

5. **WSL scan returns `Current` (not `UpdateAvailable`)**: WSL distros don't have discrete version numbers. Once registered, the distro is considered `Current`. Updates happen inside the distro via its package manager, not via Loadout.

6. **`Invoke-WSLPostInstall` called directly from `Invoke-WSLInstall`**: Rather than going through Phase 5 (`Invoke-PhasePostInstall`), WSL post-install packages are installed during Phase 4 as part of the WSL setup flow. `Invoke-PhasePostInstall` only processes `postInstallCommands`; WSL distros use `postInstallPackages` instead and all have `requiresUserSetup: true`.

**Bugs found and fixed during implementation:**
- None; parse check and test suite passed on first attempt.

**What Session 11 inherits / needs to know:**
- WSL install and uninstall are fully implemented; the deferred guard list in `Invoke-SingleApp` now contains only `WindowsFeature`, `Registry`, `VSCodeExtension`
- `Invoke-WSLScan` returns `Current`/`NotInstalled` only; the commit preview will treat installed WSL distros correctly (unchecked = ToUninstall, unchecked = not shown as needing update)
- Session 11: implement `WindowsFeature` (Enable-WindowsOptionalFeature / Add-WindowsCapability) and `Registry` (Set-ItemProperty) install + scan

---

### Session 11 Implementation Log

**Files modified:**
- `src/InstallEngine.ps1` -- added `Invoke-WindowsFeatureInstall`, `Invoke-WindowsFeatureUninstall`, `Invoke-RegistryInstall`; added `PostInstallOnly` detection in `Get-InstallMethod`; removed `WindowsFeature` and `Registry` from `$deferredMethods`; added all three methods to install switch; added `WindowsFeature` to `$uninstallable` and uninstall switch; added Phase 5 partition + log header; renamed post-install to Phase 6
- `src/UpdateChecker.ps1` -- added `Invoke-WindowsFeatureScan`, `Invoke-RegistryScan`; added `PostInstallOnly` to `Get-ScanMethod`; wired `WindowsFeature` and `Registry` in `Invoke-SingleScan`; replaced combined deferred catch-all with per-method cases
- `tests/test-install-engine.ps1` -- added `feature-openssh`, `setting-fileextensions`, `setting-highperformance` to install + uninstall test plans; added install assertions (4 checks) and updated uninstall assertions (7 checks total)

**Private functions added to InstallEngine.ps1:**

`Invoke-WindowsFeatureInstall -App`:
- `Enable-WindowsOptionalFeature`: calls `Enable-WindowsOptionalFeature -Online -FeatureName <name> -NoRestart | Out-Null`
- `Add-WindowsCapability`: calls `Add-WindowsCapability -Online -Name <name> | Out-Null`
- Throws on unknown `windowsFeatureMethod` value
- DryRun: logs command, returns early

`Invoke-WindowsFeatureUninstall -App`:
- `Enable-WindowsOptionalFeature`: calls `Disable-WindowsOptionalFeature -Online -FeatureName <name> -NoRestart | Out-Null`
- `Add-WindowsCapability`: calls `Remove-WindowsCapability -Online -Name <name> | Out-Null`
- Throws on unknown `windowsFeatureMethod` value
- DryRun: logs command, returns early

`Invoke-RegistryInstall -App`:
- Creates registry key via `New-Item -Force | Out-Null` if `Test-Path` returns false
- Calls `Set-ItemProperty -Path -Name -Value -Type` using manifest fields
- DryRun: logs command, returns early

**Private functions added to UpdateChecker.ps1:**

`Invoke-WindowsFeatureScan -App`:
- `Enable-WindowsOptionalFeature`: `Get-WindowsOptionalFeature -Online -FeatureName <name>`; checks `.State -eq 'Enabled'`
- `Add-WindowsCapability`: `Get-WindowsCapability -Online -Name <name>`; checks `.State -eq 'Installed'`
- Enabled/Installed -> `Current` with `InstalledVersion = '(enabled)'`; otherwise `NotInstalled`
- No `UpdateAvailable` state -- features are on/off only
- DryRun: returns `Current` with `'(dry-run)'`

`Invoke-RegistryScan -App`:
- Calls `Get-ItemProperty -Path <registryPath> -Name <registryName> -ErrorAction SilentlyContinue`
- Compares `.registryName` property value to manifest `registryValue` with `-eq`
- Match -> `Current` with `InstalledVersion = '(set)'`; otherwise `NotInstalled`
- No `UpdateAvailable` state -- settings are either applied or not
- DryRun: returns `Current` with `'(dry-run)'`

**`Get-InstallMethod` / `Get-ScanMethod` changes:**
- Added `PostInstallOnly` detection: if `postInstallCommands.Count > 0` and no other method field is present, returns `'PostInstallOnly'`
- This covers `setting-highperformance` and `setting-nosleep` (powercfg-only apps in manifest)

**`Invoke-SingleApp` changes:**
- `$deferredMethods` now only contains `'VSCodeExtension'`
- New early return for `PostInstallOnly`: logs "No installation required -- post-install commands will run in Phase 6", sets result to `Success`, fires `OnItemDone`, returns. Phase 6 then runs the `postInstallCommands`.
- Install switch gained `'WindowsFeature'` and `'Registry'` arms

**`Invoke-SingleAppUninstall` changes:**
- `$uninstallable` gained `'WindowsFeature'`; uninstall switch gained `'WindowsFeature'` arm
- `Registry` and `PostInstallOnly` are NOT in `$uninstallable` -- they fall through to "not yet supported" path (`Skipped`)
  - Registry: no `defaultValue` field in manifest, cannot revert
  - PostInstallOnly: powercfg calls are not reversible without knowing original state

**Phase numbering update:**
- Phase 5 (new): Windows Features, Registry Settings, PostInstallOnly -- processed from `$features` partition
- Phase 6 (was Phase 5): Post-install commands via `Invoke-PhasePostInstall`

**`Invoke-InstallPlan` partition changes:**
- New `$features` partition: non-prereq apps with method in `('WindowsFeature', 'Registry', 'PostInstallOnly')`
- `$deferred` partition reduced to: non-prereq apps with method `'VSCodeExtension'` only

**Implementation decisions made during this session:**

1. **`PostInstallOnly` method for powercfg-style apps**: `setting-highperformance` and `setting-nosleep` have no registry or feature fields -- only `postInstallCommands`. Without a primary install method, they would be `Unknown` and get `Skipped`. Adding `PostInstallOnly` detection in `Get-InstallMethod` (last check before `Unknown`) allows the engine to mark them `Success` immediately so Phase 6 picks up their commands. This is correct and idempotent.

2. **Registry uninstall deferred (no default value)**: The manifest has no `registryDefaultValue` or `revertValue` field. Without knowing what to revert to, `Invoke-RegistryInstall` in reverse is ambiguous. Registry apps return `Skipped` on uninstall with a WARN. This is consistent with the declarative model -- the GUI should prevent unchecking a settings app without user understanding of implications.

3. **`PostInstallOnly` scan returns `NotInstalled`**: There is no reliable way to detect whether a powercfg setting was previously applied without querying `powercfg /query` and parsing output. These apps will always appear as `NotInstalled` in the GUI, making them always available to re-apply. This is safe since they are idempotent.

4. **Feature scan uses DISM cmdlets directly**: `Get-WindowsOptionalFeature` and `Get-WindowsCapability` require elevation (DISM) but Loadout runs elevated. The per-app calls are acceptable for 4 features; no cache needed since there are few feature apps and DISM caches internally.

5. **`| Out-Null` on feature cmdlets**: `Enable-WindowsOptionalFeature` returns a `WindowsOptionalFeature` object with `RestartNeeded`; `Add-WindowsCapability` returns a `WindowsCapability` object. Piping to `Out-Null` suppresses pipeline output (which would otherwise appear in the runspace output queue or console). The `requiresReboot` field in the manifest already communicates restart expectations to the GUI.

**Bugs found and fixed during implementation:**
- None; test suite passed on first attempt.

**What Session 12 inherits / needs to know:**
- `VSCodeExtension` is the only remaining deferred method in `$deferredMethods`
- `Invoke-SingleApp` switch needs a `'VSCodeExtension'` arm: `code --install-extension <vscodeExtensionId>`
- `Invoke-SingleScan` already has a `'VSCodeExtension'` case returning `NotInstalled`; Session 12 should implement real detection via `code --list-extensions`
- The phase structure is now complete (Phases 1-6); Session 12 adds only the VSCodeExtension arm inside the existing framework

---

### Session 12 Implementation Log

**Files modified:**
- `src/InstallEngine.ps1` -- added `Invoke-VSCodeExtensionInstall` and `Invoke-VSCodeExtensionUninstall`; removed `$deferredMethods` block from `Invoke-SingleApp`; added `VSCodeExtension` arm to both install and uninstall switches; promoted deferred block to Phase 6 (VS Code Extensions); renamed post-install to Phase 7; removed Deferred count from summary

---

### Session 15 -- Custom App Feature (DONE)

**Files modified:**
- `src/GUI.xaml` -- added BtnAddCustomApp ("Add App"), BtnExport, BtnImport to bottom button bar; added BtnFontSmaller ("T-") and BtnFontLarger ("T+") to top bar
- `src/Loadout.ps1` -- major additions (see below)

**Files created:**
- `tests/verify-session15.ps1` -- 25 static assertions (parse check, GUI controls, function names, button wiring, APPDATA path, startup call, winget flag, dialog control names)
- `tests/test-custom-app.ps1` -- 57 functional assertions (dialog XAML validity, FindName/x:Name cross-check, Search-WingetApps parser with canned output, Save-UserManifest file I/O round-trip)

**New functions in Loadout.ps1:**

`Rebuild-AppListPanel [-PreCheckedIds <HashSet>]`:
- Clears and repopulates `$appListPanel` from the current manifest
- Nested structure: `appListPanel > catPanel (StackPanel) > headerBtn (Button) + sep + appsContainer (StackPanel) > CheckBox`
- All categories start **collapsed** (`">  Category"`); `Expand-CategoriesWithInstalledApps` expands them after a scan
- Category header buttons store the category name in `.Tag` for later lookup
- Uses `$Script:FontSizes.Cat` for header button `FontSize`; CheckBoxes inherit panel FontSize via WPF property inheritance

`Expand-CategoriesWithInstalledApps -ScanResults <hashtable>`:
- Called from `Apply-ScanResults` after scan completes
- Iterates catPanels; finds headerBtn (Button child) and appsContainer (StackPanel child)
- Expands any category that contains at least one app with `Status = Current` or `UpdateAvailable`
- Sets button content to `"v  $($headerBtn.Tag)"`

`Get-CheckBoxes`:
- Traverses two levels of StackPanel: `appListPanel > catPanel > appsContainer > CheckBox`
- Skips TextBlock spacers (direct children of appListPanel) and Separators (direct children of catPanel)

`Search-WingetApps -Query <string>`:
- Runs `winget search --name $Query --accept-source-agreements 2>$null`
- Parses the fixed-width table by finding the header row containing both `Id` and `Name`, deriving column offsets with `IndexOf`
- Returns `@(PSCustomObject{ Name; Id; Version })` or `@()` on error/no results

`Save-UserManifest -NewApp <object>`:
- Saves to `$env:APPDATA\Loadout\user-manifest.json`
- Loads existing file, strips any entry with matching `.id`, appends new app, saves -- non-destructive merge
- Creates directory if missing

`Add-CustomApp -AppObj <object>`:
- Calls `Save-UserManifest`, re-initializes `ManifestManager`, preserves current checked IDs (adds new app ID), calls `Rebuild-AppListPanel`

`Export-LoadoutConfig` / `Import-LoadoutConfig`:
- `SaveFileDialog` / `OpenFileDialog` via `System.Windows.Forms`
- Export: `{ exportedBy, selectedIds[], customApps[] }` JSON
- Import: merges custom apps into user-manifest.json (import IDs replace existing by ID), restores checked selections, calls `Rebuild-AppListPanel`

`Show-CustomAppDialog`:
- Inline XAML dialog (`@'...'@` here-string, parsed at call time)
- `Window.Resources` style for `ComboBoxItem` (Foreground + Background) fixes dark-mode dropdown text visibility
- Method dropdown: Winget, PSGallery, DirectDownload, Chocolatey, WSL Distro
- `PnlMethodSelector` wraps the method label + ComboBox; collapses entirely when "WSL Distro" is selected (only one install path)
- `PnlWingetSearch` visible for Winget only; `PnlSilentArgs` visible for DirectDownload only; `PnlWslNote` visible for WSL Distro only
- WSL Distro saves `wslDistroName` + `requiresUserSetup: true` on the app object
- `$updateMethodUI` scriptblock drives all visibility changes; called on `SelectionChanged` via `GetNewClosure()`

**Font size controls:**

`$Script:FontSizes = @{ Log = 11; Cat = 12 }` -- shared mutable reference container; set before `Rebuild-AppListPanel` is first called.

BtnFontSmaller / BtnFontLarger handlers:
- Capture `$capturedFontSizes = $Script:FontSizes` (reference to same hashtable), `$capturedFontLogPanel`, `$capturedFontAppList` as locals before `GetNewClosure()`
- Modify `$capturedFontSizes.Log` and `.Cat` directly (hashtable is a reference type -- no scope issues)
- Set `$capturedFontLogPanel.FontSize` for the RichTextBox log panel
- Call `[System.Windows.Documents.TextElement]::SetFontSize($capturedFontAppList, ...)` to cascade font size to all CheckBox children via WPF property inheritance
- Iterate catPanels to set explicit `FontSize` on each header Button (which has its own explicit value and therefore doesn't inherit)
- Range: min 8, max 24

`[System.Windows.Documents.TextElement]::SetFontSize()` is required for StackPanel because StackPanel does not expose `FontSize` as a direct property (it is a Control/TextElement property); the attached property setter works on any FrameworkElement and participates in WPF inheritance.

**Implementation decisions:**

1. **`GetNewClosure()` and `$Script:` variables**: Inside a `GetNewClosure()` closure, `$Script:` resolves to the defining script's module scope -- safe to READ, but writing can be unreliable and calls to functions that reference script-scope variables (like `$appListPanel`) may fail silently if WPF swallows the exception. Pattern: always capture needed objects as named local variables (`$capturedX = $x`) before the scriptblock, use those captures inside. See Logger.ps1 for the original note on this.

2. **`user-manifest.json` location**: `$env:APPDATA\Loadout\user-manifest.json`. `ManifestManager.Initialize-ManifestManager` merges this file with `manifest.json` at repo root automatically when the file exists.

3. **Collapsible categories**: Starting all categories collapsed avoids visual overload on first launch. `Apply-ScanResults` expands categories with installed apps, so the most relevant section opens automatically on startup scan completion. Categories added after a custom-app add or import remain collapsed until next scan.

4. **WSL Distro method selector hide**: Once "WSL Distro" is selected in the method dropdown, `PnlMethodSelector` (containing the label + ComboBox) collapses. There is no alternative install method for WSL distros so the selector adds no value. The user must Cancel and re-open to pick a different method.

**Bugs found and fixed during this session:**

- **Dark mode ComboBox text invisible**: WPF ComboBoxItem dropdown uses system theme colors which are black-on-white in dark mode. Fixed by adding `Window.Resources > Style TargetType="ComboBoxItem"` with explicit `Foreground="WhiteSmoke"` and `Background="#2D2D2D"` to the dialog XAML.
- **Font size buttons did nothing**: `Set-UIFontSize` function used `$Script:` variables and `$appListPanel` inside a `GetNewClosure()` context -- both unreliable. Fixed by removing `Set-UIFontSize` and rewriting handlers with explicit captured references and a hashtable for mutable state.
- **StackPanel.FontSize throws `PropertyAssignmentException`**: `StackPanel` does not have a `FontSize` property. Fixed by using `[System.Windows.Documents.TextElement]::SetFontSize($panel, $size)` which sets the inherited attached property on any FrameworkElement.

**What Session 16 must know:**

- `Get-CheckBoxes` traverses two StackPanel levels -- do not add direct children to `appListPanel` other than TextBlock spacers and catPanel StackPanels
- `Rebuild-AppListPanel -PreCheckedIds` accepts a `HashSet[string]`; pass `$null` to leave all unchecked, or pass a set to restore checked state
- All three button handlers (BtnAddCustomApp, BtnExport, BtnImport) are wired with `GetNewClosure()`
- Next session: **Session 16 -- Import/Export & Session Backup** (docs/design-04-features.md Section 19)
- `src/UpdateChecker.ps1` -- added `$Script:VSCodeExtensionCache`; added `Build-VSCodeExtensionCache` and `Invoke-VSCodeExtensionScan`; wired cache reset + conditional build in `Invoke-AppScan`; replaced deferred stub in `Invoke-SingleScan`
- `tests/test-install-engine.ps1` -- updated `ext-powershell` install check from Deferred to Success; added `ext-powershell` to uninstall selection and checks

**Public API unchanged.** No new public functions; all additions are private.

**Script-scope state added to UpdateChecker.ps1:**
- `$Script:VSCodeExtensionCache` -- OrdinalIgnoreCase HashSet of installed extension IDs; built once per `Invoke-AppScan` call via `code --list-extensions`; `$null` between runs

**Phase numbering (final):**
- Phase 1: Prerequisites
- Phase 2: Standard (winget + PSGallery)
- Phase 3: Direct downloads
- Phase 4: WSL distros
- Phase 5: Windows Features, Registry, PostInstallOnly
- Phase 6: VS Code Extensions
- Phase 7: Post-install commands

**Implementation decisions made during this session:**

1. **Cache pattern mirrors WSL**: `Build-VSCodeExtensionCache` is lazy (called once in `Invoke-AppScan` if any VSCodeExtension apps are in scope), OrdinalIgnoreCase HashSet, skipped in DryRun. `Invoke-VSCodeExtensionScan` just does `$cache.Contains(...)`.

2. **No version comparison**: `code --list-extensions --show-versions` returns `id@version` but there is no offline source for available marketplace versions. Status is `Current`/`NotInstalled` only (same as WSL distros). This avoids network calls during scan.

3. **`code` CLI assumed on PATH**: winget installs VS Code with shell integration; `code` is on PATH for any new shell after install. If VS Code is not installed, `Build-VSCodeExtensionCache` catches the exception, logs WARN, and leaves cache empty (all extensions report NotInstalled). The extension install will also fail with a clear error if `code` is absent.

4. **`$deferredMethods` removed entirely**: With VSCodeExtension implemented, there are no remaining deferred install methods. The block in `Invoke-SingleApp` was removed rather than left as an empty array.

**Bugs found and fixed during implementation:**
- `Invoke-PhasePostInstall` comment and log message still said "Phase 5" and "Phase 6" respectively after the numbering shift; corrected to "Phase 7" in both.

**What Session 13 inherits / needs to know:**
- All install methods (Winget, PSGallery, DirectDownload, Chocolatey, WSL, WindowsFeature, Registry, VSCodeExtension, PostInstallOnly) are fully implemented
- All scan methods are fully implemented
- All uninstall methods are implemented except Registry (Skipped + WARN) and PostInstallOnly (Skipped + WARN)
- Phase structure (Phases 1-7) is final; no more deferred installs

---

### Session 13 Implementation Log

**Files modified:**
- `tests/parse-check.ps1` -- added ManifestManager.ps1, UpdateChecker.ps1, USBBuilder.ps1 to parse check list
- `tests/test-usb-builder.ps1` -- added Tests 9-11 (WindowsFeature skip, Registry skip, Chocolatey skip); renumbered old Tests 9-10 to 12-13
- `src/USBBuilder.ps1` -- minor log message fix: "Destination: $usbRoot" -> "Output: $usbRoot" (line 371)

**Files unchanged:** src/USBBuilder.ps1 (logic), src/Loadout.ps1, src/GUI.xaml, src/InstallEngine.ps1, src/UpdateChecker.ps1, src/Logger.ps1, src/ManifestManager.ps1

**Note:** src/USBBuilder.ps1, src/Loadout.ps1 (Show-USBBuilderDialog, Run-USBBuildInBackground, BtnBuildUsb handler), and src/GUI.xaml (BtnBuildUsb control) were all fully implemented in a prior session. Session 13 added only gap tests and maintenance fixes.

**Public API (do not change signatures):**
```powershell
Invoke-USBBuild -Apps <object[]> -Destination <string> [-OnItemStart <scriptblock>] [-OnItemDone <scriptblock>]
# Returns: hashtable id -> 'Success' | 'WingetOnly' | 'Skipped' | 'Failed'

Get-USBBuildResults
# Returns: hashtable from last Invoke-USBBuild call
```

**Status values from Invoke-USBDownloadSingle:**
- `Success` -- installer downloaded or module saved (or DryRun simulation)
- `WingetOnly` -- winget app but `winget download` failed; app will install online from main GUI
- `Skipped` -- method not USB-applicable: VSCodeExtension, WSL, WindowsFeature, Registry, Chocolatey, or excluded via `includeInUSBKit = false`
- `Failed` -- PSGallery Save-Module failed or DirectDownload threw

**Test results:** 39 passed, 0 failed (tests/test-usb-builder.ps1)

**What Session 14 inherits / needs to know:**
- USB Kit Builder is complete and fully tested
- BtnBuildUsb is wired in Loadout.ps1; no GUI changes needed for Session 14
- manifest-local.json localInstaller/localModulePath/localWingetManifest fields are injected by New-LocalManifest in USBBuilder.ps1
- Loadout-Offline.ps1 (written by Copy-LoadoutFiles) passes -ManifestPath to Loadout.ps1 so ManifestManager loads manifest-local.json
- The drive format safety gate (DriveType == Removable) is enforced in Show-USBBuilderDialog before any format operation
- Session 14: Self-updater (read docs/design-04-features.md, Self-update section)

---

### Session 14 Implementation Log

**Files produced:**
- `src/SelfUpdater.ps1` -- new module with three public functions
- `src/Update-Helper.ps1` -- standalone update-swap helper script

**Files modified:**
- `src/Loadout.ps1` -- dot-source SelfUpdater.ps1; capture `$localVersion`; add update check to `Add_Loaded` handler
- `tests/parse-check.ps1` -- added SelfUpdater.ps1 and Update-Helper.ps1 to parse check list

**Public functions added to SelfUpdater.ps1:**

`Get-RemoteVersionInfo`:
- Fetches `https://raw.githubusercontent.com/bferguson-dev/Loadout/main/version.json`
- Uses `-UseBasicParsing -TimeoutSec 5`; returns `$null` on any error (offline, firewall, etc.)
- Returns `PSCustomObject{ version: string; releaseUrl: string }`

`Test-NewerVersion -Local <string> -Remote <string>`:
- Splits both strings on `.`, compares integer parts left-to-right
- Returns `$true` if Remote is strictly newer; `$false` on equal or parse error

`Invoke-SelfUpdate -ReleaseUrl <string> -RepoRoot <string> -ProcessId <int>`:
- Downloads zip to `%TEMP%\Loadout-Update\Loadout-update.zip`
- Extracts to `%TEMP%\Loadout-Update\extracted\`; detects single top-level folder from GitHub zip format
- Prefers `Update-Helper.ps1` from the new release; falls back to current install
- Launches `Update-Helper.ps1` via `Start-Process powershell.exe -WindowStyle Normal`
- Returns `$true` if helper launched; `$false` on any exception (caller should NOT close window on `$false`)

**Update-Helper.ps1 (standalone -- no dot-sources, no module imports):**
- Accepts params: `-MainPid`, `-SourceDir`, `-SourceDir`, `-RepoRoot`, `-LaunchScript`
- Polls `Get-Process -Id $MainPid` every 500 ms; gives up after 30 s and proceeds anyway (WARN logged)
- `Copy-Item -Path "$SourceDir\*" -Destination $RepoRoot -Recurse -Force`
- Cleans up `Split-Path $SourceDir -Parent` (the `Loadout-Update` temp dir)
- Relaunches `powershell.exe -ExecutionPolicy Bypass -File $LaunchScript`
- All errors go to `Read-Host` pause so the user can see the message; exits 1 on fatal error
- `$ErrorActionPreference = 'Continue'` (not Stop) -- swap errors must not silently kill the script

**Loadout.ps1 changes:**

1. Added `. "$PSScriptRoot\SelfUpdater.ps1"` to module imports (after USBBuilder.ps1)

2. Version.json block now captures `$localVersion` (initialized to `'0.0.0'` before the try block in case the file is missing):
   ```powershell
   $localVersion = '0.0.0'
   try { ... $localVersion = $versionData.version ... } catch { ... }
   ```

3. Before `Add_Loaded`, three captured variables are set for use inside the closure:
   - `$capturedPID = $PID`
   - `$capturedLocalVer = $localVersion`
   - `$capturedRepoRoot = Split-Path $PSScriptRoot -Parent`

4. `Add_Loaded` handler now runs the self-update check synchronously before starting the app scan:
   - Calls `Get-RemoteVersionInfo` (5 s timeout; returns `$null` on failure -> check is skipped)
   - Calls `Test-NewerVersion` to compare versions
   - If newer: shows `MessageBox` (YesNo) with version info
   - If Yes: calls `Invoke-SelfUpdate`; on `$true`, calls `$window.Close()` and `return`
   - If No or `Invoke-SelfUpdate` returns `$false`: falls through to normal scan startup

**Implementation decisions made during this session:**

1. **Synchronous version check in `Add_Loaded`**: The check blocks the UI thread for up to 5 seconds (the `-TimeoutSec` value) only when the server is unreachable. For reachable servers the GitHub raw CDN returns in well under 100 ms. This is simpler than a background runspace and avoids showing the prompt mid-scan.

2. **`$PID` captured explicitly**: `$PID` is an automatic variable but is captured via `$capturedPID` before `GetNewClosure()` to avoid any ambiguity about which scope's `$PID` the closure sees.

3. **`Update-Helper.ps1` uses `$ErrorActionPreference = 'Continue'`**: File copy failures should not silently terminate the script. The catch block prints to the console and pauses so the user can read the error before the window closes.

4. **Update-Helper prefers new release's own copy of itself**: If the downloaded release zip contains an `src\Update-Helper.ps1`, that version is used. This allows future sessions to ship an updated helper without the old helper being the bottleneck.

5. **GitHub zip top-level folder detection**: `[System.IO.Compression.ZipFile]::ExtractToDirectory` places all files inside the zip's top-level folder. Session 14 detects one child directory in `extracted\` and uses it as `$sourceDir`. If the zip is flat (unusual), `extractDir` itself is used.

6. **No DryRun guard on update check**: Loadout.ps1 does not expose a `-DryRun` param in its public interface (DryRun is internal to the engine runspace only). The self-update check is benign on any system.

**Bugs found and fixed during implementation:**
- None; parse check passed on first attempt (9 files: all src/*.ps1 + GUI.xaml).

**What Session 15 inherits / needs to know:**
- Self-updater is fully wired; no further changes to SelfUpdater.ps1 or Update-Helper.ps1 expected
- `Get-RemoteVersionInfo`, `Test-NewerVersion`, `Invoke-SelfUpdate` are public API -- do not rename
- `version.json` at repo root is the canonical "baked-in" version; `$Script:RemoteVersionUrl` in SelfUpdater.ps1 is the GitHub raw URL to check
- Session 15: Custom App feature (read docs/design-04-features.md, Section 18)

---

### Session 15 Implementation Log (Custom App Feature -- COMPLETE)

**Files modified:**
- `src/GUI.xaml` -- added BtnAddCustomApp, BtnExport, BtnImport buttons (with separator) to the bottom button bar after BtnBuildUsb
- `src/Loadout.ps1` -- extracted inline population into Rebuild-AppListPanel; added Search-WingetApps, Save-UserManifest, Add-CustomApp, Export-LoadoutConfig, Import-LoadoutConfig, Show-CustomAppDialog; wired three new button handlers

**Files produced:**
- `tests/verify-session15.ps1` -- 25 static assertions, all pass
- `tests/test-custom-app.ps1` -- 55 functional assertions: dialog XAML validity, FindName/x:Name cross-check, Search-WingetApps parser with canned output, Save-UserManifest round-trip I/O

**New functions in Loadout.ps1:**

`Rebuild-AppListPanel [-PreCheckedIds <HashSet[string]>]`:
- Clears AppListPanel and re-adds all apps from current `Get-ManifestApps`
- Same header/separator/checkbox layout as the original inline block
- Pre-checks any IDs in `PreCheckedIds` (if not $null)
- Replaces the original inline `foreach ($app in $apps)` block at startup
- Also called after Add-CustomApp and Import-LoadoutConfig

`Search-WingetApps -Query <string>`:
- Runs `winget search --name <query> --accept-source-agreements` synchronously
- Parses fixed-width table: finds header row (contains both 'Id' and 'Name'), derives column offsets via `String.IndexOf`, extracts Name/Id/Version per row
- Returns array of `PSCustomObject{ Name; Id; Version }`, or `@()` on no results/error
- Called from the BtnSearchWinget click handler inside Show-CustomAppDialog

`Save-UserManifest -NewApp <object>`:
- Loads existing `%APPDATA%\Loadout\user-manifest.json` (if present), strips any entry with the same id, appends NewApp, saves
- Creates `%APPDATA%\Loadout\` directory if it does not exist

`Add-CustomApp -AppObj <object>`:
- Calls Save-UserManifest, re-initializes ManifestManager, rebuilds AppListPanel
- Pre-checks current selections plus the new app

`Export-LoadoutConfig`:
- Opens SaveFileDialog (*.json), writes `{ exportedBy, selectedIds[], customApps[] }` to chosen file
- customApps sourced from user-manifest.json (empty array if not present)

`Import-LoadoutConfig`:
- Opens OpenFileDialog (*.json), merges `customApps` into user-manifest.json (non-destructive -- keeps existing IDs not in the import), re-initializes ManifestManager, rebuilds AppListPanel, restores `selectedIds`

`Show-CustomAppDialog`:
- Inline XAML dialog (500x560): DisplayName, Description, Category (editable ComboBox pre-filled with existing categories), Install Method (Winget/PSGallery/DirectDownload/Chocolatey), primary ID field (label changes per method), Winget search panel (TxtSearch + BtnSearchWinget + LstSearchResults ListBox, 120px height), Silent Args panel (DirectDownload only)
- PnlWingetSearch visible only when Winget selected; PnlSilentArgs visible only for DirectDownload; PnlSearchResults collapsed until first search
- LstSearchResults: each ListBoxItem.Content = "Id   Name   Version", .Tag = winget ID; selection auto-fills TxtPrimaryId
- Save validation: DisplayName and primary ID are required
- Custom app ID generated as `custom-<sanitized-displayname>` (lowercase, non-alphanumeric -> hyphens)
- Returns built PSCustomObject on confirm, $null on cancel

**New GUI buttons:**
```
... [Build USB Kit] | [Add App] [Export] [Import]   [Settings]
```
All three buttons use `FindName`/`Add_Click`/`GetNewClosure()` pattern.

**Implementation decisions:**

1. **`Rebuild-AppListPanel` instead of incremental add**: After saving a custom app, re-initializing ManifestManager merges the new app into `$Script:ManifestApps`. Rather than trying to insert a checkbox at the right position (which would require finding the category section), clearing and rebuilding is simpler and guarantees consistent ordering. The pre-check preservation ensures the user does not lose their selections.

2. **`Search-WingetApps` is synchronous**: The function runs from the modal dialog's button click. The UI freezes for a few seconds (typical winget startup overhead), which is acceptable for a user-initiated search. A background runspace is not needed since the dialog is already a blocking ShowDialog.

3. **Category editable ComboBox**: Items pre-filled from `Get-ManifestApps | Select-Object -ExpandProperty category -Unique`. User can also type a new category name. `.Text` is used to read the value (works for both selected items and typed values).

4. **winget ID sanitization**: `'custom-' + ($displayName.ToLower() -replace '[^a-z0-9]', '-' -replace '-+', '-').Trim('-')` produces a stable, URL-safe ID. If two apps have the same sanitized name, the second Save-UserManifest call replaces the first (same id). The user can re-run Add-CustomApp to overwrite with corrected data.

5. **No DryRun guard on Save-UserManifest / Import-LoadoutConfig**: These write to APPDATA, not to system paths. DryRun mode only applies to the install engine background runspace, not to the main GUI window.

6. **Export includes `exportedBy` field**: Acts as a magic marker for future validation. Currently unused but allows a future Import to detect non-Loadout JSON files before attempting to parse `selectedIds`.

**Bugs found and fixed during implementation:**
- None; parse check passed on first attempt (25 assertions passed).

**What Session 16 inherits / needs to know:**
- `Rebuild-AppListPanel` is now the canonical way to refresh the app list; call it with a HashSet of IDs to pre-check after any manifest change
- `user-manifest.json` path: `Join-Path $env:APPDATA 'Loadout\user-manifest.json'`
- Export/Import config format: `{ exportedBy, selectedIds[], customApps[] }` -- do not change
- Session 16: Import/Export & Session Backup (docs/design-04-features.md, Section 19) -- PuTTY/WinSCP session backup, Machine Config Snapshot

---

### Session 16 Implementation Log

**Files modified:**
- `src/GUI.xaml` -- added BtnBackup ("Backup") after BtnImport in the bottom button bar; added Margin to BtnImport for spacing
- `src/Loadout.ps1` -- added Export-PuttySessions, Import-PuttySessions, Export-WinscpSessions, Import-WinscpSessions, Export-MachineSnapshot, Import-MachineSnapshot, Show-SessionBackupDialog; wired BtnBackup

**Files created:**
- `tests/verify-session16.ps1` -- 36 static assertions, all pass

**New functions added to Loadout.ps1:**

`Export-PuttySessions`:
- Guards on `Test-Path 'HKCU:\Software\SimonTatham\PuTTY\Sessions'`; returns $null with WARN if key absent
- Runs `& reg export "HKCU\Software\SimonTatham\PuTTY\Sessions" $outFile /y 2>$null`
- Output: `%APPDATA%\Loadout\SessionBackups\PuTTY\putty-sessions-YYYY-MM-DD.reg`
- Returns output path on success, $null on failure

`Import-PuttySessions -FilePath`:
- Runs `& reg import $FilePath 2>$null`; checks `$LASTEXITCODE`
- Returns $true/$false

`Export-WinscpSessions`:
- Tries registry first: `HKCU:\Software\Martin Prikryl\WinSCP 2\Sessions` via `reg export`
- Falls back to `$env:APPDATA\WinSCP.ini` if registry key absent (Copy-Item)
- Output: `%APPDATA%\Loadout\SessionBackups\WinSCP\winscp-sessions-YYYY-MM-DD.reg` or `WinSCP-YYYY-MM-DD.ini`
- Returns $null with WARN if neither source found

`Import-WinscpSessions -FilePath`:
- Dispatches on extension: `.reg` -> `reg import`; `.ini` -> `Copy-Item` to `$env:APPDATA\WinSCP.ini`
- Returns $true/$false; WARN on unrecognized extension

`Export-MachineSnapshot`:
- Guards on `$Script:LastScanResults.Count -eq 0`; returns $null with WARN if no scan data
- Builds `[PSCustomObject]@{ capturedAt; appCount; apps[] }` from `$Script:LastScanResults`
- Each app entry: `{ id; status; installedVersion; availableVersion }`
- Output: `%APPDATA%\Loadout\SessionBackups\MachineSnapshot\snapshot-YYYY-MM-DD.json`

`Import-MachineSnapshot -FilePath`:
- Reads JSON snapshot, builds HashSet of IDs where `status` is `Current` or `UpdateAvailable`
- Calls `Rebuild-AppListPanel -PreCheckedIds $preCheckIds` to restore selections
- Returns $true/$false

`Show-SessionBackupDialog`:
- Modal WPF dialog with three sections: PuTTY Sessions, WinSCP Sessions, Machine Config Snapshot
- Status labels set in code after `XamlReader.Load` (not in XAML string) to avoid XML-escaping issues
- `$getLastBackup` local scriptblock scans the backup subfolder for the most recent matching file
- Initial status text shows detection state and last backup date for each section
- All six buttons use GetNewClosure() with captured label references
- Export buttons update their status label with filename on success
- Import buttons open `OpenFileDialog` (InitialDirectory defaults to `$env:APPDATA` if backup dir absent)
- Machine Snapshot import calls `Rebuild-AppListPanel`; dialog stays open so user sees the result
- `BtnBackupClose` calls `$capturedDialog.Close()` (not `DialogResult`) since no confirmation needed
- `$dialog.ShowDialog() | Out-Null` (return value discarded)

**Implementation decisions:**

1. **No DryRun gating**: Session backup helpers follow the same pattern as `Export-LoadoutConfig`/`Import-LoadoutConfig` (Session 15) -- they write to APPDATA, not system paths. DryRun only applies to the install engine background runspace.

2. **WinSCP detection priority**: Registry checked first (most common for installed version); `%APPDATA%\WinSCP.ini` checked second. Portable WinSCP installations using a non-standard INI location are not auto-detected; the user can manually browse to the file via the Import button.

3. **`reg export` / `reg import` via `& reg`**: Called with `2>$null` to suppress console output from the GUI context. Exit code checked via `$LASTEXITCODE` to detect failure.

4. **Machine Snapshot import does not overwrite scan results**: `Import-MachineSnapshot` only pre-checks checkboxes; it does not update `$Script:LastScanResults`. The live scan data remains valid. This is intentional -- the snapshot reflects a previous machine state, not a live scan.

5. **Status label updates are in-place**: After export or import, the status `TextBlock.Text` is updated inline in the dialog. The dialog stays open so the user can see the result and perform multiple operations before closing.

6. **No async needed**: All backup operations (reg export/import, file copy, JSON write) are fast enough to run synchronously on the UI thread inside a modal dialog. No DispatcherTimer or runspace required.

**Bugs found and fixed during verification:**
- Test regex patterns initially used `\\\\` (four backslashes = matches two literal `\`) instead of `\\` (two backslashes = matches one literal `\` in single-quoted regex string). Fixed in verify-session16.ps1.
- PuTTY and WinSCP import handlers initially used `System.Windows.Forms.OpenFileDialog` inside a nested WPF `ShowDialog()` (main window -> backup dialog -> WinForms picker). Switching to `Microsoft.Win32.OpenFileDialog` with `ShowDialog($capturedDialog)` fixed a crash on file selection.
- PuTTY and WinSCP import handlers called `& reg import` directly on the UI thread. `reg.exe import` shows a Win32 "successfully imported" MessageBox before exiting, which blocks `reg.exe` from returning, which blocks the UI thread, which freezes WPF. Windows marks the app "not responding" and the user force-closes it. Fixed by switching to `Start-Process reg.exe -PassThru -WindowStyle Hidden` (non-blocking) + a `DispatcherTimer` that polls `HasExited` and updates the status label when done. Machine Snapshot import is not affected because it uses pure PowerShell (no external process).

**Rule established:** Never call `& external.exe` from a WPF event handler on the UI thread if the external process may block (show a dialog, wait for input, or take more than ~100ms). Always use `Start-Process -PassThru` + `DispatcherTimer` in that context.

**What Session 17 must know:**
- Backup directories: `%APPDATA%\Loadout\SessionBackups\{PuTTY|WinSCP|MachineSnapshot}\`
- `Export-MachineSnapshot` reads `$Script:LastScanResults` directly; ensure scan has run before calling
- `Import-MachineSnapshot` calls `Rebuild-AppListPanel`; always safe to call on the UI thread
- Session 17: GitHub Actions (docs/design-04-features.md, Section 20)

---

### Post-Release Bugfix Session -- Visual Testing Fixes (DONE)

Bugs surfaced during first live visual test run after all 21 sessions were complete.
No new features -- all changes are in `src/Loadout.ps1` and `src/GUI.xaml`.

**Bugs fixed:**

1. **ComboBox white background in Custom App dialog**
   - `Show-CustomAppDialog` embedded XAML had no `<Style TargetType="ComboBox">`.
   - Fixed: added `<Style TargetType="ComboBox">` and `<Style TargetType="ComboBoxItem">` with dark
     theme colours to the dialog's `Window.Resources`.

2. **WSL Distro selection locked the method selector**
   - `$updateMethodUI` collapsed `PnlMethodSelector` when method was WSL Distro, making it
     impossible to switch away without closing and reopening the dialog.
   - Fixed: removed the conditional; `PnlMethodSelector` is always `Visible`.

3. **Enter key did not trigger winget search**
   - `TxtSearch` had no `KeyDown` handler.
   - Fixed: added `$txtSearch.Add_KeyDown` handler that calls
     `$capturedBtnSearch.RaiseEvent(...)` when `Key -eq Return`.

4. **Log panel did not word-wrap**
   - `$Script:LogPanel.Document.PageWidth = 10000` disabled wrapping at runtime.
   - `HorizontalScrollBarVisibility="Auto"` in GUI.xaml allowed horizontal expansion.
   - Fixed: removed the PageWidth line; changed attribute to `"Disabled"` in GUI.xaml.

5. **Winget search returned no results for searches like "Git.Git"**
   - `String.IndexOf('Name')` / `IndexOf('Id')` / `IndexOf('Version')` on the header row
     are case-sensitive; some winget builds emit "ID" (uppercase).
   - Fixed: all three calls now pass `[System.StringComparison]::OrdinalIgnoreCase`.

6. **Winget search result display was unreadable**
   - List items showed `"Id   Name   Version"` -- ID first made scanning difficult.
   - Fixed: changed to `"Name  (Id)"` -- name is now prominent.

7. **Startup scan always ran in DryRun mode**
   - `Build-ScanScriptText` hardcoded `Initialize-Logger -DryRun`, so winget never actually
     ran during the startup scan. All Winget/WSL apps reported as NotInstalled; Registry,
     WindowsFeature, PSGallery, and PostInstallOnly apps reported Current (DryRun mock).
     This produced both false positives and false negatives in the checklist.
   - Fixed: changed to `Initialize-Logger` (no flag) so the scan runs for real.

8. **Install failures silently showed "Operation complete"**
   - Timer callback used `try { EndInvoke } catch { }` which swallowed all errors.
   - Fixed: errors from `EndInvoke` and `$capturedPs.Streams.Error` are now captured;
     each error is logged at ERROR level; status bar shows "Operation failed" if any
     errors were captured.

9. **Progress queue string interpolation crash**
   - Install/USB builder background runspace scripts contained:
     `$progressQueue.Enqueue("START:$i:$n:$name")`
     PowerShell parses `$n:$name` as a scope-qualified variable (like `$env:PATH`),
     which is invalid syntax. The runspace threw a parse error immediately on start,
     producing "Operation complete" with no install activity and no log file.
   - Fixed: changed to `"START:${i}:${n}:${name}"` (and `DONE` variant) in both the
     install runspace script (Run-UpdateInBackground) and the USB builder runspace script.
   - Same fix applied to the uninstall PHASE enqueue line for consistency.

**Files changed:** `src/Loadout.ps1`, `src/GUI.xaml`
**Tests:** parse-check.ps1 passes; all other suites unaffected (DryRun still used in test suites).

---

### Visual Testing Bugfix Session 2 -- Multi-Round UI Polish (DONE)

Second live visual testing pass after the post-release bugfix session. Covered three rounds
of user-reported bugs/requests. Files changed: `src/Loadout.ps1`, `src/GUI.xaml`,
`src/InstallEngine.ps1`.

**Round 1 fixes:**

1. **Column header text/font** -- header read "install/app" at small FontSize; changed to
   "Install / Uninstall" (LblInstallCol) with proper casing.
2. **Version display** -- installed versions now shown for Current apps (grey) and
   UpdateAvailable apps ("v1.0 -> v1.1" in yellow), not just update cases.
3. **Update CB opacity** -- initial Opacity=0.3 (greyed); set to 1.0 when UpdateAvailable.
4. **Stale scan state** -- after uninstall+rescan the wrong apps appeared in install plan
   because LastScanResults was wiped on empty scan return. Fixed: Apply-ScanResults null/empty
   hash guard -- preserves LastScanResults if scan returns no data.
5. **Auto-rescan after commit** -- Run-UpdateInBackground now rescans after every completion.
6. **WinSCP winget upgrade** -- added fallback from `winget upgrade` to `winget install` on
   non-zero exit code.
7. **Settings button** -- wired up (no-op initially, opens settings dialog shell).
8. **BtnBuildUsb dark styling** -- was rendering white; fixed with explicit Background="#3A3A3A";
   later reverted to default button style per user request.
9. **Export/Import consolidated** -- separate BtnExport/BtnImport removed; functionality moved
   into Backup dialog under "Loadout Config Export/Import" section; BtnBackup renamed
   "Import/Export".
10. **Commit moved to far right** -- BtnCommit docked right in bottom bar DockPanel.
11. **Admin elevation check** -- startup checks WindowsPrincipal.IsInRole(Administrator);
    offers RunAs relaunch if not elevated.
12. **Background runspace log forwarding** -- background scripts override Write-Log to enqueue
    "LOG:LEVEL:MESSAGE" strings; timer tick routes them to the GUI log panel. Uses 3-part
    `$msg -split ':', 3` to preserve colons in message text.

**Round 2 fixes (from user feedback):**

13. **Settings to top bar** -- moved from bottom bar to top bar, right of T+/T- buttons.
14. **"No scan results" message** -- updated to "click Scan first."
15. **BtnBuildUsb styling** -- reverted to default WPF button style (matches all other buttons).

**Round 3 fixes (current session):**

16. **Title and header font sizes** -- Loadout title 20px->30px; LblInstallCol/LblUpdateCol
    headers 11px->20px; LblUpdateCol Width 56->80. Headers now scale with T+/T- (Header key
    in $Script:FontSizes, same increment as Log/Cat). UpdateCb.Width = max(56, Header*4).
17. **Removed Update All / Update Selected buttons** -- these are superseded by Commit, which
    handles updates when both install CB and update CB are checked.
18. **Added Select All Updates / Deselect All Updates** -- toggle all enabled update CBs.
19. **Custom App Manager** -- `Show-CustomAppManagerDialog` lists user-manifest.json entries
    with a Delete button per app. On delete: removes from user-manifest.json, re-inits
    ManifestManager, rebuilds app list. If app was installed, it stays installed -- Loadout
    simply stops managing it (no auto-uninstall). BtnManageApps wired in bottom bar.
20. **winget second fallback** -- after `winget upgrade` fails -> `winget install --architecture x64`
    fails -> now retries `winget install` without `--architecture` flag. Fixes 32-bit-only apps
    like WinSCP that return -1978335189 (APPINSTALLER_ERROR_NO_APPLICABLE_UPGRADE) with the
    arch flag.

**Known remaining issue (defer to next session):**
- Update checkbox column does not visually right-align after the font/width change.
  The "Update" header (LblUpdateCol, DockPanel.Dock=Right, Width=80) is not lining up
  above the per-row UpdateCb controls (DockPanel.Dock=Right, Width=80). Likely a
  padding/margin difference between the header Border (Padding="10,4,10,4") and the
  AppListPanel (Margin="10,8,10,8") combined with the ScrollViewer. Fix: adjust the
  column header padding or use a shared Grid instead of matching fixed widths.

**Files changed:** `src/Loadout.ps1`, `src/GUI.xaml`, `src/InstallEngine.ps1`
**Tests:** parse-check.ps1 passes.

---

---

### Parked Feature -- Custom App Deletion Confirmation + Optional Uninstall

**Status:** Not yet implemented. Implement in the next session that touches Show-CustomAppManagerDialog.

**Motivation:** When a user deletes a custom app entry via Manage Apps, the app remains installed
on the system. Loadout will no longer scan, update, or uninstall it. The user may not realize this.

**Agreed design:**
- Before removing the entry, show a confirmation dialog with two choices:
  1. "Remove from Loadout only" -- deletes the manifest entry; app stays installed
  2. "Remove from Loadout and uninstall" -- deletes the manifest entry AND runs
     `Invoke-UninstallPlan` for that app
- The dialog must include a warning: "Loadout will no longer be able to scan, update, or
  uninstall this program if you proceed."
- If the user chooses uninstall, show the standard progress/log feedback (same as a normal
  uninstall commit) before closing the manager dialog.
- If uninstall is not possible (e.g. no wingetId, or app type is WindowsFeature/Registry),
  the "Remove from Loadout and uninstall" option should be disabled or hidden, with a tooltip
  explaining why (e.g. "Automatic uninstall not supported for this app type").
- The dialog should support batch deletion: each row gets a checkbox (not a Delete button).
  A "Delete Selected" button at the bottom acts on all checked rows at once.
  The confirmation dialog fires once for the whole batch, not once per app.
  The dialog stays open after the batch is processed so the user can make further selections.
- The "Close" button closes the manager dialog; no confirmation needed on close.

**Implementation notes:**
- `Show-CustomAppManagerDialog` is in `src/Loadout.ps1`
- The per-row Delete button click handler is the right place to intercept and show the confirmation
- `Invoke-UninstallPlan` is the existing uninstall entry point in `src/InstallEngine.ps1`
- App type is available on the app object (`$app.installMethod` or `$app.type`); check before
  offering the uninstall option

*End of Loadout Design Document*
*github.com/bferguson-dev/Loadout*

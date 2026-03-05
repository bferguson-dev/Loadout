## SECTION 24: TESTING STRATEGY

### VM Testing Environment

- Use Hyper-V or VMware Workstation with clean Windows VM
- Take snapshot of clean state before each test run
- Revert to snapshot between tests
- Test Windows 10 (1903+) and Windows 11 VMs separately
- Test Server OS to confirm WSL section hidden

### Dry Run

- Launch: `.\Loadout.ps1 -DryRun`
- [DRY RUN] banner in GUI
- All logic executes — only actual commands skipped
- Full log written for review

### Key Test Scenarios Per Session

- Session 2 (bootstrapper): Restricted policy, no admin, winget missing
- Session 4 (install engine): dry run full install, prerequisite failure handling
- Session 10 (WSL): Home edition block, reboot-resume on Win10 VM
- Session 13 (USB builder): FAT32/exFAT format, non-removable drive rejection

---

## APPENDIX: QUICK REFERENCE

### Key Registry Paths

| Path | Purpose |
|---|---|
| HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run | Reboot-resume launcher (temp, self-removing) |
| HKCU:\Software\SimonTatham\PuTTY\Sessions | PuTTY saved sessions |
| HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall | Uninstall strings for direct-download apps |

### Decisions That Are Final — Do Not Re-Litigate

- PowerShell + WPF — not Python, not Electron, not C#
- winget first → PSGallery → direct download → Chocolatey last resort
- No toast notifications — status bar only
- No code signing certificate
- WSL 2 only — WSL 1 not offered
- wsl --install for distros — never winget
- WSL hidden on all Server OS
- Text only in app list — no icons
- Single GitHub repo
- AppData as install location
- Declarative uninstall model — uncheck and commit
- Commit preview diff before any action
- MIT license
- Semantic versioning from v1.0.0
- Minimum Windows 10 build 1903
- No Fedora or CentOS Stream WSL
- 64-bit default with per-app override
- No toast notifications (worth repeating)

---

## APPENDIX: CODING STANDARDS

These rules were discovered during implementation and apply to every .ps1 file in the project. Do not violate them.

### ASCII-Only Rule for .ps1 Files

PowerShell 5.1 reads .ps1 script files as ANSI (Windows-1252) by default when no UTF-8 BOM is present. The Write tool (used by Claude Code) writes UTF-8 without BOM. Multi-byte UTF-8 sequences for non-ASCII characters are misinterpreted character-by-character under ANSI:

- The em dash (U+2014, UTF-8: E2 80 94) is read as three ANSI chars. Byte 0x94 maps to a right double-quote in Windows-1252, which silently closes any open string literal and breaks parsing with a misleading "Missing closing '}'" error.
- Box-drawing characters (used in ASCII banners) have the same problem — many contain 0x94 bytes.

**Rule:** Every .ps1 file must use ASCII-only characters (codepoints 0x00–0x7F). Specifically:
- Use `--` instead of em dashes in strings and comments
- Use plain `=====` or similar for decorative banners instead of box-drawing characters
- Use straight quotes only — no curly quotes
- This rule does NOT apply to .json, .md, .html, or .xaml files

### Script-Scope Variable Convention

All module-level state is stored in `$Script:` scoped variables. Never use global scope. Functions within a module read and write `$Script:` vars; callers never access internal state directly.

### Error Handling Convention

All src/ modules use `$ErrorActionPreference = 'Stop'` at the top so cmdlet errors become terminating exceptions. Wrap external calls (winget, network, registry) in try/catch. Let unhandled exceptions propagate to the caller — the GUI or Install Engine is responsible for top-level error display.

### Module Loading Convention

All src/ modules are dot-sourced by Loadout.ps1 at startup:
```powershell
. "$PSScriptRoot\src\Logger.ps1"
. "$PSScriptRoot\src\ManifestManager.ps1"
# etc.
```
Never use Import-Module for project files. Never assume CWD — always use $PSScriptRoot for relative paths within src/.

---

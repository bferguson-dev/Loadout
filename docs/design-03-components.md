## SECTION 7: BOOTSTRAPPER

### One-Liner

```powershell
irm https://bferguson-dev.github.io/Loadout/install | iex
```

GitHub Pages docs/index.html serves or redirects to bootstrap.ps1. This URL never changes.

### Bootstrap Sequence

| Step | Action | Notes |
|---|---|---|
| 1 | Check execution policy | If Restricted or AllSigned: show dialog, set -Scope Process -ExecutionPolicy Bypass only. Never touch machine policy. |
| 2 | Check elevation | If not admin: relaunch with Start-Process -Verb RunAs |
| 3 | Check PowerShell version | Log version. Note if only 5.1. Prefer PS7 if present. |
| 4 | Check winget availability | If missing: download and install from GitHub before proceeding |
| 5 | Check Windows build | If < 1903: non-blocking warning. Do not prevent use. |
| 6 | Check if Loadout already installed | If %APPDATA%\Loadout exists: run self-update check instead of fresh install |
| 7 | Download latest release | Pull zip from GitHub releases using version.json |
| 8 | Extract to AppData | %APPDATA%\Loadout\ |
| 9 | Offer shortcuts | Two independent checkboxes: Add Desktop shortcut / Add Start Menu entry |
| 10 | Launch Loadout.ps1 | Bootstrap exits. Loadout takes over. |

### Execution Policy Notes

- Detection: Get-ExecutionPolicy checked at both CurrentUser and LocalMachine scope
- Scope used: Process only — machine and user policy untouched
- No code signing certificate — not practical for this project
- User sees clear dialog on first run. Silent on subsequent runs if policy is already permissive.

---

## SECTION 8: LOGGER

Logger.ps1 is built first because everything else calls it. Handles two output streams simultaneously: WPF GUI live log panel and timestamped log file on disk.

### Log File Location

`%APPDATA%\Loadout\Logs\Loadout-YYYY-MM-DD-HHmmss.log` — one file per run

### Log Entry Format

```
[2026-02-26 14:23:01] [INFO ] Installing VS Code via winget...
```

### Log Levels

| Level | GUI Color | Used For |
|---|---|---|
| INFO | White | Normal operation |
| OK | Green | Successful completions |
| WARN | Yellow | Non-fatal issues |
| ERROR | Red | Failed installs |
| DEBUG | Gray | Verbose output — only shown with -DryRun flag |

### Dry Run Flag

Launch with `-DryRun` flag. GUI shows [DRY RUN] banner. All logic executes normally — only actual command execution is skipped. Full log written to disk.

### Logger API Contract (for Session 3)

```powershell
# Call once at startup from Loadout.ps1
Initialize-Logger [-DryRun]

# Call from any module for all output
Write-Log -Message <string> [-Level <INFO|OK|WARN|ERROR|DEBUG>] [-NoNewline]
```

Script-scope variables set by Initialize-Logger:

| Variable | Type | Purpose |
|---|---|---|
| $Script:LogFilePath | string | Full path to the open log file for this run |
| $Script:LogPanel | object | WPF control reference (null until Session 7 wires it in) |
| $Script:DryRun | bool | Whether DryRun mode is active |

Behavior contract:
- Initialize-Logger creates `%APPDATA%\Loadout\Logs\` if missing and opens a new timestamped log file
- Write-Log always appends to $Script:LogFilePath
- Write-Log writes to $Script:LogPanel via Dispatcher.Invoke if non-null; falls back to Write-Host with matching colors if null
- DEBUG messages: written to disk always, but suppressed from UI/console unless $Script:DryRun is true
- Write-Log is the only output mechanism used by InstallEngine, UpdateChecker, ManifestManager, and all other src/ modules — nothing in src/ calls Write-Host directly

---

## SECTION 9: INSTALL ENGINE

### Declarative Model

Compares desired state (checkboxes) against current state (scan results) and executes whatever actions are needed. Mirrors Terraform's plan/apply model.

### Execution Phases

| Phase | What Happens |
|---|---|
| Phase 1 — Prerequisites | All isPrerequisite:true apps install silently. User sees 'Preparing prerequisites...' |
| Phase 2 — Standard installs | All winget and PSGallery installs run sequentially |
| Phase 3 — Direct downloads | Downloaded then installed silently using silentArgs |
| Phase 4 — WSL | Always last. May trigger reboot-resume. |
| Phase 5 — Post-install | postInstallCommands run per app. WSL distro updates run here. |

### Dependency Handling

- If a prerequisite fails: all apps depending on it are skipped
- Skipped apps appear in failure report with reason: "Prerequisite X failed to install"

### Winget Flags

```powershell
winget install --id <ID> --architecture x64 --silent --accept-package-agreements --accept-source-agreements
```

### Chocolatey Fallback

- NEVER pre-installed or assumed present
- Only triggered when app has chocolateyId and no other method works
- Commit preview warns: "Chocolatey will be installed as a prerequisite for X"
- User must confirm before Chocolatey installs
- Once installed it remains

---

## SECTION 10: UPDATE SYSTEM

### Launch-Time Scan

On every launch, scan all apps against what is installed. Results populate status badges before user interacts.

| Status | Badge | Checkbox State |
|---|---|---|
| Not installed | Gray dot | Unchecked |
| Installed and current | Green checkmark | Checked |
| Update available | Blue up-arrow | Checked (highlighted) |
| Failed last run | Red X | Unchecked |

### Version Check Methods by Install Type

| Method | How Checked |
|---|---|
| winget | winget list --id shows installed vs available |
| PSGallery | Compare Get-InstalledModule vs Find-Module |
| Direct download | Registry/file check vs versionCheckUrl in manifest |
| Chocolatey | choco outdated |

### Update Controls

- **Update All** — selects every app with available update
- **Update Selected** — respects current checkbox state
- Mutually exclusive — checking one clears the other
- User can mix: install new apps AND update existing in single Commit

### Scheduled Background Scan

- Optional Windows Task Scheduler task — off by default
- Runs weekly, writes to %APPDATA%\Loadout\update-cache.json
- Loadout reads cache on launch for instant status
- **NO toast notifications — ever**
- Status bar shows update count only

### GitHub Actions Manifest Auto-Update

- Weekly schedule + manual trigger
- Checks versionCheckUrl for each direct-download app
- Updates manifest and auto-commits if version changed
- Validates winget/PSGallery IDs still exist

---

## SECTION 11: GUI DESIGN

### Framework

WPF via XAML loaded in PowerShell. No additional installs required. Genuine talking point — most people don't know you can build real Windows GUIs in pure PowerShell.

### Layout

| Region | Content |
|---|---|
| Top bar | Loadout name, version number, Check for Updates button |
| Main left panel | Flat categorized checklist — categories as visual dividers not tabs. Text only, no icons. |
| Main right panel | Always-visible live scrolling log panel |
| Progress area | Overall progress bar ("Installing 3 of 12"), current item progress bar |
| Bottom bar | Select All, Deselect All, Update All, Update Selected, Commit button, Build USB Kit, Settings gear |
| Status bar | Persistent strip at very bottom — shows update count from scheduled scan cache |

### Commit Preview (Diff Before Any Action)

When user clicks Commit, a modal dialog appears BEFORE execution showing:
- Apps to install
- Apps to update (with old → new version)
- Apps to uninstall
- Prerequisites installing silently
- Orphaned prerequisites to remove
- Any Chocolatey installation warnings

User clicks Confirm or Cancel. Nothing happens until Confirm.

### Uninstall Model

- Everything currently installed shows pre-checked
- User unchecks apps to remove
- Commit preview shows those as "To uninstall"
- Orphaned prerequisite cleanup offered after uninstall

### Status Bar

Shows "X updates available" from cache. Clicking scrolls app list to first app with available update. This is the ONLY notification surface — no toast notifications ever.

---

## SECTION 12: UNINSTALL

| Install Method | Uninstall Method |
|---|---|
| winget | winget uninstall --id <ID> --silent |
| PSGallery | Uninstall-Module <Name> -AllVersions |
| Direct download | Read uninstall string from HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall |
| Chocolatey | choco uninstall <ID> -y |

### Orphaned Prerequisite Cleanup

After uninstall, check if any other installed app still depends on the same prerequisites. If not, prompt: "These prerequisites are no longer needed. Remove them?" User confirms or skips.

---

## SECTION 13: WSL INSTALLER

### Key Decisions — Locked In

- WSL 2 only — WSL 1 not offered
- Use `wsl --install -d <DistroName>` exclusively — never winget for distros
- WSL section hidden entirely on Server OS
- Hyper-V availability checked before showing WSL options (not on Home editions)

### Supported Distros

| Distro | Install Command | Package Manager |
|---|---|---|
| Ubuntu (Latest LTS) | wsl --install -d Ubuntu | apt |
| Ubuntu 24.04 | wsl --install -d Ubuntu-24.04 | apt |
| Ubuntu 22.04 | wsl --install -d Ubuntu-22.04 | apt |
| Debian | wsl --install -d Debian | apt |
| AlmaLinux 9 | wsl --install -d AlmaLinux-9 | dnf |
| Rocky Linux 9 | wsl --install -d Rocky-9 | dnf |
| Kali Linux | wsl --install -d kali-linux | apt |

### Install Sequence

| Step | Action | Notes |
|---|---|---|
| 1 | Check Windows edition | Abort if Home edition |
| 2 | Enable Windows features | Microsoft-Windows-Subsystem-Linux and VirtualMachinePlatform |
| 3 | Check if reboot needed | Required on older Win10 builds |
| 4 | Reboot-resume if needed | See Reboot Manager below |
| 5 | Set WSL default version | wsl --set-default-version 2 |
| 6 | Install Linux kernel update | Direct download from Microsoft — Win10 only |
| 7 | Install selected distros | wsl --install -d for each |
| 8 | Notify user | "WSL will now launch. You will be asked to create a username and password." |
| 9 | Post-install toolkit | apt/dnf update + upgrade + install toolkit packages |
| 10 | Install 7-Zip | p7zip-full (apt) or p7zip p7zip-plugins (dnf) |

### Post-Install Toolkit (All Distros)

Installed via: `wsl -d <DistroName> -- sudo <pm> install -y <packages>`

curl, wget, vim, nano, htop, tmux, tree, unzip, tar, net-tools, nmap, traceroute, dnsutils/bind-utils, openssh-client, rsync, jq, git, python3, pip, ansible, docker (CLI only), 7-zip

### Reboot Manager

- Before reboot: serialize state to %APPDATA%\Loadout\resume-state.json
- Register run key: HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
- On relaunch: detect resume-state.json, show "Resuming installation..." banner, continue
- After completion: delete resume-state.json and remove run key

---

## SECTION 14: WINDOWS FEATURES & SETTINGS

### Optional Windows Features

| Feature | Method | Notes |
|---|---|---|
| Hyper-V | Enable-WindowsOptionalFeature | Not on Home — detect and warn |
| OpenSSH Client | Add-WindowsCapability | |
| Telnet Client | Enable-WindowsOptionalFeature | |
| RSAT | Add-WindowsCapability | Large download — warn user |

### Optional Windows Settings

| Setting | Method |
|---|---|
| Show file extensions | HKCU Explorer HideFileExt = 0 |
| Show hidden files | HKCU Explorer Hidden = 1 |
| Enable dark mode | HKCU Personalization AppsUseLightTheme = 0 |
| High Performance power plan | powercfg /setactive (High Performance GUID) |
| Disable sleep on AC | powercfg /change standby-timeout-ac 0 |

---

## SECTION 15: VS CODE EXTENSIONS

Collapsible sub-section under VS Code in GUI. Only visible if VS Code is installed or selected.

Install: `code --install-extension <id> --force`
Check installed: `code --list-extensions`

Extensions: ms-vscode.powershell, ms-vscode-remote.remote-ssh, hashicorp.terraform, ms-azuretools.vscode-docker, eamodio.gitlens, redhat.vscode-yaml, redhat.ansible

---

## SECTION 16: USB KIT BUILDER

### User Flow

1. User clicks Build USB Kit
2. Panel opens with app checklist (defaults to current selection)
3. User selects destination folder
4. If removable drive: offer format (FAT32 or exFAT). **NEVER offer format for non-removable drives — DriveType check mandatory.**
5. Show estimated download size before proceeding
6. Download all selected apps — per-app progress shown
7. PSGallery modules: Save-Module to local path
8. winget download where available, direct URL fallback from manifest
9. Generate manifest-local.json with local file paths
10. Copy self-contained offline Loadout to destination
11. Write README.txt to drive
12. Show completion report with total size

### USB Folder Structure

```
Loadout-USB/
├── Loadout-Offline.ps1
├── manifest-local.json
├── README.txt
└── installers/
    └── modules/
```

### USB Update Behavior

- On launch: silently check version.json on GitHub
- If unreachable: run offline silently, no error
- If newer version: prompt "Update this USB kit to vX.X.X?"
- If yes: download new version, replace files on drive, offer to refresh cached installers

---

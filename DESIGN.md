# LOADOUT — Full Project Design Document
**Infrastructure Workstation Setup Tool**
**GitHub: github.com/bferguson-dev/Loadout**
**Author: bferguson-dev**

---

## HOW TO USE THIS DOCUMENT (READ FIRST — FOR CLAUDE CODE INSTANCES)

This is the single source of truth for the Loadout project. Every design decision is recorded here. Do not re-litigate decisions already made. Build what is described. If something is unclear, ask — do not assume.

### Chat/Session Startup Table

When starting a new build session, tell Claude Code which component you are building. Use this table to know which sections to read and where to start.

| Session # | Component | Read These Sections | Start Here |
|---|---|---|---|
| 1 | manifest.json | App List, Manifest Structure | Build manifest.json with all app entries — data only, no code |
| 2 | Bootstrapper | Architecture, Delivery Modes, Bootstrapper | Execution policy detection and elevation check first |
| 3 | Logger | Logger | Build Logger.ps1 first — everything else depends on it |
| 4 | Install Engine | Install Engine | Bring Logger.ps1 and manifest.json from prior sessions |
| 5 | Update Checker | Update System | Bring manifest.json and Install Engine |
| 6 | WPF GUI Shell | GUI Design | Build GUI.xaml and wire to manifest — hardcode data first |
| 7 | GUI + Engine Integration | Install Engine, GUI Design | Bring Session 4 and Session 6 outputs |
| 8 | Commit Preview | GUI Design — Commit Preview | Bring Session 7 output |
| 9 | Uninstall | Uninstall | Bring Session 7 output |
| 10 | WSL Installer | WSL | Bring Install Engine — WSL is its own isolated sequence |
| 11 | Windows Features + Settings | Windows Features | Bring GUI from Session 7 |
| 12 | VS Code Extensions | VS Code Extensions | Bring GUI and Install Engine |
| 13 | USB Kit Builder | USB Builder | Bring all prior outputs |
| 14 | Self-Updater | Self-Update | Bring bootstrapper from Session 2 |
| 15 | Custom App Feature | Custom Apps | Bring GUI and manifest manager |
| 16 | Import/Export + Sessions | Import Export | Bring GUI and manifest manager |
| 17 | GitHub Actions | Automation | Pure YAML — no prior code needed |
| 18 | Scheduled Scan + Status Bar | Update Notifications | Bring GUI and Update Checker |
| 19 | Failure Report | Failure Report | Bring Install Engine and Logger |
| 20 | README + GitHub Pages | Documentation | Bring all final outputs |
| 21 | Testing + Dry Run | Testing | Bring all final outputs |

---

## SECTION 1: PROJECT OVERVIEW

### What Loadout Is

Loadout is a portable, self-updating Windows infrastructure workstation setup tool built in PowerShell with a WPF GUI. It installs, updates, and uninstalls a curated set of tools for infrastructure professionals using a declarative checkbox model. It operates in two modes: online via a one-liner bootstrapper pulled from GitHub, and offline via a USB kit built from within the online version.

### Purpose

- Move quickly from workstation to workstation with a consistent tool environment
- Portfolio project demonstrating real PowerShell and infrastructure engineering skills
- Demonstrates: GUI development in PowerShell, package management, CI/CD, declarative state management, reboot-resume logic, offline deployment packaging

### Key Design Principles

- **Declarative model** — user describes desired state, Loadout makes it happen
- **winget-first** — always prefer winget, fall back only when necessary
- **Transparent** — everything the tool does is visible in the live log
- **Non-destructive** — preview before committing, never act without confirmation
- **Self-maintaining** — GitHub Actions keeps the manifest current automatically
- **Portable** — works from USB with no internet, or from a one-liner on any connected machine

---

## SECTION 2: REPOSITORY STRUCTURE

### GitHub Account

- Username: bferguson-dev
- Repository: https://github.com/bferguson-dev/Loadout
- License: MIT
- Versioning: Semantic versioning — Major.Minor.Patch starting at v1.0.0

### Key URLs

| URL | Purpose |
|---|---|
| https://bferguson-dev.github.io/Loadout/install | One-liner install short URL (GitHub Pages) |
| https://raw.githubusercontent.com/bferguson-dev/Loadout/main/bootstrap.ps1 | Bootstrapper raw file |
| https://raw.githubusercontent.com/bferguson-dev/Loadout/main/version.json | Version check endpoint |
| https://github.com/bferguson-dev/Loadout/releases/latest | Latest release download |

### Folder Structure

```
Loadout/
├── bootstrap.ps1                          # One-liner entry point — permanent URL on main
├── version.json                           # Latest version number and release download URL
├── manifest.json                          # Master app registry
├── LICENSE                                # MIT
├── README.md                              # Docs, one-liner, screenshots
├── DESIGN.md                              # This file
├── src/
│   ├── Loadout.ps1                        # Main entry point, launches WPF GUI
│   ├── GUI.xaml                           # WPF interface definition
│   ├── InstallEngine.ps1                  # Install, update, uninstall logic
│   ├── ManifestManager.ps1                # Manifest loading, merging, querying
│   ├── UpdateChecker.ps1                  # Launch-time app version scanning
│   ├── WSLInstaller.ps1                   # WSL-specific install sequence
│   ├── USBBuilder.ps1                     # USB kit packaging
│   ├── RebootManager.ps1                  # Reboot-resume state handling
│   ├── SelfUpdater.ps1                    # Loadout self-update logic
│   ├── WindowsFeatures.ps1                # Optional Windows features and settings
│   └── Logger.ps1                         # Logging to UI and disk
├── user/
│   └── user-manifest.json                 # User custom apps (gitignored — never overwritten)
├── assets/
│   └── Loadout.ico                        # Stylized L icon
├── docs/
│   └── index.html                         # GitHub Pages redirect for install one-liner
├── .github/
│   └── workflows/
│       ├── manifest-update.yml            # Weekly automated version checker
│       └── validate-manifest.yml          # Manifest schema validation on push
└── tests/
    └── dry-run/                           # Dry run outputs
```

---

## SECTION 3: ARCHITECTURE

### Technology Stack

- **Language:** PowerShell (primary)
- **GUI framework:** WPF via XAML loaded in PowerShell using [System.Windows.Markup.XamlReader]
- **Minimum PowerShell version:** 5.1 (ships with all supported Windows versions)
- **PS7** detected and preferred at runtime if available
- **WPF in PS5.1** uses built-in .NET Framework — no extra runtime install needed

### Install Priority Order

| Priority | Method | Used For | Notes |
|---|---|---|---|
| 1 | winget | Most apps | Always tried first. Use --architecture x64 and --accept-source-agreements |
| 2 | PSGallery | PowerShell modules | Install-Module with -Force and -AllowClobber |
| 3 | Direct download | Vendor-specific tools | Silent install flags stored in manifest |
| 4 | Chocolatey | Last resort ONLY | Installed on-demand only. Never pre-installed or assumed present. |
| 5 | wsl --install -d | WSL distros only | Never use winget for WSL distros |

### 64-bit Default

All apps default to x64. Global `preferX64: true` in manifest. Individual entries can override. Winget uses `--architecture x64`. Direct download URLs explicitly point to x64 builds. ARM64 architecture detected at launch — warn if app has no native ARM64 build.

### Operating System Support

| OS | Support Level | Notes |
|---|---|---|
| Windows 11 (all versions) | Full | Primary target |
| Windows 10 build 1903+ | Full | Minimum floor |
| Windows 10 build < 1903 | Warning shown | Non-blocking warning, tool still runs |
| Windows Server 2016/2019/2022/2025 | Full | WSL section hidden on all Server OS |
| ARM64 Windows | Partial | Per-app warnings for missing ARM64 builds |

WSL is never offered on any Server OS. Detection uses WMI at launch.

---

## SECTION 4: DELIVERY MODES

### Mode 1 — Online (Primary)

User opens an elevated PowerShell prompt and pastes:

```powershell
irm https://bferguson-dev.github.io/Loadout/install | iex
```

Bootstrap.ps1 handles elevation and execution policy, downloads latest release zip, extracts to `%APPDATA%\Loadout`, launches GUI. Loadout lives in AppData permanently and self-updates on every launch.

### Mode 2 — USB Offline Kit

Built from within the online version using Build USB Kit. Downloads all selected installers, generates local manifest, copies self-contained offline Loadout to destination. USB version never requires internet to install apps. When internet IS available it checks for updates and offers to refresh.

### AppData Install Location

| Path | Purpose |
|---|---|
| %APPDATA%\Loadout\ | Root install directory |
| %APPDATA%\Loadout\Logs\ | Timestamped log files (one per run) |
| %APPDATA%\Loadout\SessionBackups\PuTTY\ | PuTTY session exports |
| %APPDATA%\Loadout\SessionBackups\WinSCP\ | WinSCP session exports |
| %APPDATA%\Loadout\update-cache.json | Scheduled scan results cache |
| %APPDATA%\Loadout\resume-state.json | Reboot-resume state (deleted after completion) |
| %APPDATA%\Loadout\user-manifest.json | User custom apps (never overwritten by updates) |
| %USERPROFILE%\Desktop\Loadout.lnk | Desktop shortcut (optional, user chooses) |
| %APPDATA%\Microsoft\Windows\Start Menu\Programs\Loadout.lnk | Start Menu entry (optional) |

---

## SECTION 5: FULL APP LIST

All apps default to x64. Install method listed in priority order.

### Development

| App | winget ID | Notes |
|---|---|---|
| VS Code | Microsoft.VisualStudioCode | |
| Python | Python.Python.3 | Latest stable |
| Git for Windows | Git.Git | |
| Windows Terminal | Microsoft.WindowsTerminal | Pre-installed on Win11 — check first |
| PowerShell 7 | Microsoft.PowerShell | |
| Notepad++ | Notepad++.Notepad++ | |

### VS Code Extensions (sub-section under VS Code)

Installed via: `code --install-extension publisher.extensionname --force`
Check installed via: `code --list-extensions`

| Extension | ID |
|---|---|
| PowerShell | ms-vscode.powershell |
| Remote - SSH | ms-vscode-remote.remote-ssh |
| HashiCorp Terraform | hashicorp.terraform |
| Docker | ms-azuretools.vscode-docker |
| GitLens | eamodio.gitlens |
| YAML | redhat.vscode-yaml |
| Ansible | redhat.ansible |

### Remote Access

| App | winget ID |
|---|---|
| PuTTY | PuTTY.PuTTY |
| WinSCP | WinSCP.WinSCP |
| FileZilla | TimKosse.FileZilla.Client |
| mRemoteNG | mRemoteNG.mRemoteNG |
| Microsoft Remote Desktop | Microsoft.RemoteDesktopClient |
| Tailscale | Tailscale.Tailscale |
| OpenVPN | OpenVPNTechnologies.OpenVPN |

### Browsers

| App | winget ID |
|---|---|
| Mozilla Firefox | Mozilla.Firefox |
| Google Chrome | Google.Chrome |

### Infrastructure & Cloud

| App | Install Method | Notes |
|---|---|---|
| VMware Remote Console (VMRC) | Direct download | Check VMware site for latest URL |
| OpenLens | winget: OpenLens.OpenLens | |
| Terraform | winget: Hashicorp.Terraform | |
| AWS CLI | winget: Amazon.AWSCLI | |
| Azure CLI | winget: Microsoft.AzureCLI | |
| Draw.io Desktop | winget: JGraph.Draw | |

### API & Testing

| App | winget ID |
|---|---|
| Postman | Postman.Postman |
| Insomnia | Insomnia.Insomnia |
| Bruno | Bruno.Bruno |

### PowerShell Modules (PSGallery)

| Module | Install Command | Notes |
|---|---|---|
| VMware PowerCLI | Install-Module VMware.PowerCLI | Run Set-PowerCLIConfiguration -InvalidCertificateAction Ignore after install |
| Az (Azure) | Install-Module Az | Large — warn user of download size |
| AWS Tools for PowerShell | Install-Module AWSPowerShell.NetCore | |
| Pester | Install-Module Pester | PowerShell testing framework |

### Network & Diagnostics

| App | winget ID |
|---|---|
| Wireshark | WiresharkFoundation.Wireshark |
| Nmap | Insecure.Nmap |
| Advanced IP Scanner | Famatech.AdvancedIPScanner |

### Security & Credentials

| App | winget ID |
|---|---|
| KeePass | DominikReichl.KeePass |
| Bitwarden | Bitwarden.Bitwarden |

### Disk & Storage

| App | winget ID | Purpose |
|---|---|---|
| Rufus | Rufus.Rufus | Bootable USB creator |
| Ventoy | Ventoy.Ventoy | Multi-boot USB |
| CDBurnerXP | CDBurnerXP.CDBurnerXP | ISO burn and create |
| AnyBurn | AnyBurn.AnyBurn | ISO editing and burning |
| WinDirStat | WinDirStat.WinDirStat | Visual disk usage treemap |
| TreeSize Free | JAMSoftware.TreeSize.Free | Disk analysis |
| CrystalDiskInfo | CrystalDewWorld.CrystalDiskInfo | Drive health (S.M.A.R.T.) |
| CrystalDiskMark | CrystalDewWorld.CrystalDiskMark | Disk benchmark |
| MiniTool Partition Wizard Free | MiniTool.PartitionWizard.Free | Partition management |
| Eraser | Eraser.Eraser | Secure wipe |

### System Utilities

| App | winget ID | Notes |
|---|---|---|
| 7-Zip | 7zip.7zip | Also installed in all WSL distros |
| ShareX | ShareX.ShareX | Screenshot and screen capture |
| Greenshot | Greenshot.Greenshot | Lightweight screenshot |
| PowerToys | Microsoft.PowerToys | |
| Sysinternals Suite | Microsoft.Sysinternals | Full suite |
| WSL Manager | (winget) | Optional — GUI for managing WSL distros |

### Package Managers

| App | Notes |
|---|---|
| Chocolatey | LAST RESORT ONLY. Never pre-installed. Only installed when an app requires it and no other method works. User warned and must confirm before install. |

### Windows Features (separate section in GUI)

| Feature | Method |
|---|---|
| Hyper-V | Enable-WindowsOptionalFeature (not available on Home editions) |
| OpenSSH Client | Add-WindowsCapability |
| Telnet Client | Enable-WindowsOptionalFeature |
| RSAT | Add-WindowsCapability (large download — warn user) |

### Windows Settings (separate section in GUI)

| Setting | Method |
|---|---|
| Show file extensions | HKCU Explorer HideFileExt = 0 |
| Show hidden files | HKCU Explorer Hidden = 1 |
| Enable dark mode | HKCU Personalization AppsUseLightTheme = 0 |
| High Performance power plan | powercfg /setactive (High Performance GUID) |
| Disable sleep on AC power | powercfg /change standby-timeout-ac 0 |

---

## SECTION 6: MANIFEST STRUCTURE

The manifest.json is the heart of the project. Lives in repo root. user-manifest.json lives in AppData, merged at runtime, never overwritten by updates.

### Top-Level Structure

```json
{
  "version": "1.0.0",
  "lastUpdated": "2026-02-26",
  "preferX64": true,
  "apps": []
}
```

### Per-App Entry Fields

| Field | Type | Description |
|---|---|---|
| id | string | Unique identifier (e.g. vscode, python, putty) |
| displayName | string | What the GUI shows |
| description | string | Short description shown as subtext |
| category | string | Category grouping in GUI |
| isPrerequisite | boolean | True if this is a silent background install |
| dependencies | array | List of app IDs that must install first |
| requiresReboot | boolean | Whether install typically needs a reboot |
| requiresElevation | boolean | Whether install needs admin rights |
| includeInUSBKit | boolean | Whether included in USB kit by default |
| wingetId | string | Winget package ID — primary install method |
| psGalleryModule | string | PSGallery module name — for PS modules |
| directDownload | object | Direct download definition (see below) |
| chocolateyId | string | Chocolatey package ID — last resort only |
| silentArgs | string | Silent install arguments for direct downloads |
| postInstallCommands | array | Commands to run after install completes |
| x64Override | boolean | Override global preferX64 setting |
| arm64Available | boolean | Whether a native ARM64 build exists |
| notes | string | Human readable notes for maintainers |

### directDownload Object Fields

| Field | Description |
|---|---|
| url | Direct download URL to x64 installer |
| versionCheckUrl | URL to check current latest version |
| versionCheckMethod | github-api, json-path, regex, or version-file |
| versionCheckExpression | Path or pattern to extract version from response |
| installedVersionPath | Registry or file path to check installed version |

### WSL Distro Entry Fields

| Field | Description |
|---|---|
| wslDistroName | Name passed to wsl --install -d (e.g. Ubuntu-24.04) |
| packageManager | apt or dnf |
| postInstallPackages | Array of package names to install after distro setup |
| requiresUserSetup | Always true — triggers user notification about username/password |

---

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

## SECTION 17: SELF-UPDATE

| Step | Action |
|---|---|
| 1 | Fetch version.json from GitHub on every launch |
| 2 | Compare to baked-in version in Loadout.ps1 |
| 3 | If same: continue normally |
| 4 | If newer: prompt user |
| 5 | Download new release zip |
| 6 | Extract to temp subfolder |
| 7 | Launch Update-Helper.ps1 — waits for main process to exit, swaps files, relaunches |
| 8 | Loadout exits. Helper swaps. New version launches. |

PowerShell cannot replace a running script — the helper script pattern solves this.

---

## SECTION 18: CUSTOM APP FEATURE

- Add Custom App button opens form in GUI
- Fields: display name, description, category, install method, ID/URL, silent args
- Winget search: type app name, Loadout queries winget, user picks from results to auto-fill ID
- Saved to user-manifest.json in AppData — never overwritten by updates
- Merged with main manifest at runtime

### Import / Export

- Export: saves checkbox selections + custom apps to portable JSON config file
- Import: loads config file, restores selections and custom apps
- Use case: set up once, export, import on every new machine

---

## SECTION 19: IMPORT/EXPORT & SESSION BACKUP

### PuTTY Sessions

- Stored in: HKCU:\Software\SimonTatham\PuTTY\Sessions
- Export: reg export to %APPDATA%\Loadout\SessionBackups\PuTTY\putty-sessions-YYYY-MM-DD.reg
- Import: reg import of chosen file

### WinSCP Sessions

- Stored in registry or INI depending on version
- Export/import to %APPDATA%\Loadout\SessionBackups\WinSCP\

### Machine Config Snapshot

- Export: JSON of all installed apps and versions — useful as audit log
- Import: Loadout reads snapshot and pre-checks all apps that were installed

---

## SECTION 20: GITHUB ACTIONS

### manifest-update.yml

- Trigger: weekly + manual dispatch
- Checks versionCheckUrl for each direct-download app
- Updates manifest.json and auto-commits if version changed
- Validates winget/PSGallery IDs still exist

### validate-manifest.yml

- Trigger: every push
- Validates manifest.json against JSON schema
- Fails PR if manifest is malformed

### release.yml (future)

- Trigger: version tag push
- Zips source, creates GitHub Release, attaches zip, updates version.json

---

## SECTION 21: UPDATE NOTIFICATIONS

**NO TOAST NOTIFICATIONS — EVER. This is final.**

- Status bar in Loadout GUI shows update count from cached scan only
- Clicking status bar scrolls to first app with available update
- Nothing happens outside of Loadout — no tray icon, no popups, no system notifications
- Optional scheduled Task Scheduler job writes to cache file silently

---

## SECTION 22: FAILURE REPORT

End-of-run summary panel showing:

| Category | Icon | Contents |
|---|---|---|
| Successfully installed | Green checkmark | Apps installed this run |
| Successfully updated | Blue arrow | Apps updated with old → new version |
| Already up to date | Gray checkmark | No action needed |
| Skipped | Yellow warning | Apps skipped due to prerequisite failure — shows which prerequisite |
| Failed | Red X | Apps that failed with plain-English reason |

Full technical error output always in log file. Failure report shows human-readable summary. Both written to disk.

---

## SECTION 23: DOCUMENTATION & GITHUB PAGES

### README.md Must Include

- Project name and description
- One-liner install command prominently at top
- Screenshots of GUI
- Full app list
- How to use USB Kit Builder
- How to add custom apps
- Architecture overview
- MIT license badge

### GitHub Pages Setup

- Enable in repo settings — source: docs/ folder on main branch
- docs/index.html serves bootstrap.ps1 content
- URL: https://bferguson-dev.github.io/Loadout/install
- This URL is permanent — safe to share forever

---

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

*End of Loadout Design Document*
*github.com/bferguson-dev/Loadout*

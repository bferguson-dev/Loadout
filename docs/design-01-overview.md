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
| 2 | Bootstrapper | Architecture, Delivery Modes, Bootstrapper | Create bootstrap.ps1 at repo root. Build the 10-step Bootstrap Sequence in order (Section 7). Start with Step 1 (Get-ExecutionPolicy check — Process scope only, never machine) and Step 2 (elevation via Start-Process -Verb RunAs). Then winget availability check (Step 4) — this is the trickiest step. Do not build the shortcut UI (Steps 9–10) until the core sequence works. No Logger.ps1 yet — write-host only for now. |
| 3 | Logger | Logger | **DONE** -- src/Logger.ps1. See Implementation Log appendix for build notes. |
| 4 | Install Engine | Install Engine, Architecture | Create src/ManifestManager.ps1 first (manifest loading/querying -- needed by engine), then src/InstallEngine.ps1. Dot-source both Logger.ps1 and ManifestManager.ps1 at the top of InstallEngine.ps1. Use Write-Log exclusively for all output -- never Write-Host. Build the 5 execution phases from Section 9 in order (Prerequisites, Standard, Direct, WSL, Post-install). Expose one public entry point: Invoke-InstallPlan accepting an array of app objects resolved from the manifest. Use the exact winget flags from Section 9. For DryRun support: check $Script:DryRun before every external call (winget, registry, network) and Write-Log what would have run instead of running it. Test with a small hardcoded app list in dry-run mode -- no GUI needed. Do not build WSL logic yet (Session 10). Do not build uninstall yet (Session 9). |
| 5 | Update Checker | Update System | **DONE** -- src/UpdateChecker.ps1. See Implementation Log appendix for build notes. |
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

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# Loadout

**Windows Infrastructure Workstation Setup Tool**

Loadout is a portable, self-updating PowerShell + WPF application that installs, updates, and uninstalls a curated set of tools for infrastructure professionals. Pick your tools from a checklist, preview exactly what will change, and click Commit.

---

## Install

Open an **elevated** PowerShell prompt and run:

```powershell
irm https://bferguson-dev.github.io/Loadout/install | iex
```

Loadout installs to `%APPDATA%\Loadout`, creates optional shortcuts, and self-updates on every launch.

---

## Screenshots

> GUI screenshots will be added here after the first public release.

---

## Features

| Feature | Description |
|---|---|
| Declarative checkbox model | Select what you want, preview the diff, commit |
| Install / Update / Uninstall | Handles all three from the same checklist |
| Commit Preview | Shows exactly what will be installed, updated, or removed before anything runs |
| Startup scan | Detects already-installed apps and pre-checks them automatically |
| USB Kit Builder | Downloads all selected installers for fully offline deployment |
| Custom Apps | Add any app not in the built-in list; saved to AppData, never overwritten |
| Import / Export | Save your selections and custom apps to a portable JSON config |
| Session Backup | Export and restore PuTTY sessions, WinSCP sessions, and a machine config snapshot |
| Self-update | Checks for a new Loadout release on every launch and upgrades with one click |

---

## App List

All 72 apps default to x64. Install method priority: winget > PSGallery > direct download > Chocolatey (last resort only).

### Development

| App | Install Method |
|---|---|
| VS Code | winget |
| Python 3 | winget |
| Git for Windows | winget |
| Windows Terminal | winget |
| PowerShell 7 | winget |
| Notepad++ | winget |

### VS Code Extensions

Installed via `code --install-extension`. Managed as a separate section in the GUI.

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

| App | Install Method |
|---|---|
| PuTTY | winget |
| WinSCP | winget |
| FileZilla | winget |
| mRemoteNG | winget |
| Microsoft Remote Desktop | winget |
| Tailscale | winget |
| OpenVPN | winget |

### Browsers

| App | Install Method |
|---|---|
| Mozilla Firefox | winget |
| Google Chrome | winget |

### Infrastructure & Cloud

| App | Install Method |
|---|---|
| Terraform | winget |
| AWS CLI | winget |
| Azure CLI | winget |
| OpenLens | winget |
| VMware Remote Console (VMRC) | direct download |
| Draw.io Desktop | winget |

### API & Testing

| App | Install Method |
|---|---|
| Postman | winget |
| Insomnia | winget |
| Bruno | winget |

### PowerShell Modules

| Module | Install Method |
|---|---|
| VMware PowerCLI | PSGallery |
| Az (Azure) | PSGallery |
| AWS Tools for PowerShell | PSGallery |
| Pester | PSGallery |

### Network & Diagnostics

| App | Install Method |
|---|---|
| Wireshark | winget |
| Nmap | winget |
| Advanced IP Scanner | winget |

### Security & Credentials

| App | Install Method |
|---|---|
| KeePass | winget |
| Bitwarden | winget |

### Disk & Storage

| App | Install Method |
|---|---|
| Rufus | winget |
| Ventoy | winget |
| CDBurnerXP | winget |
| AnyBurn | winget |
| WinDirStat | winget |
| TreeSize Free | winget |
| CrystalDiskInfo | winget |
| CrystalDiskMark | winget |
| MiniTool Partition Wizard Free | winget |
| Eraser | winget |

### System Utilities

| App | Install Method |
|---|---|
| 7-Zip | winget |
| ShareX | winget |
| Greenshot | winget |
| PowerToys | winget |
| Sysinternals Suite | winget |
| WSL Manager | winget |

### Windows Features

Managed as a separate collapsible section in the GUI.

| Feature | Method |
|---|---|
| Hyper-V | Enable-WindowsOptionalFeature |
| OpenSSH Client | Add-WindowsCapability |
| Telnet Client | Enable-WindowsOptionalFeature |
| RSAT | Add-WindowsCapability |

### Windows Settings

| Setting | Effect |
|---|---|
| Show file extensions | Disables HideFileExt in Explorer |
| Show hidden files | Sets Hidden=1 in Explorer |
| Enable dark mode | Sets AppsUseLightTheme=0 |
| High Performance power plan | Activates the High Performance plan via powercfg |
| Disable sleep on AC power | Sets standby-timeout-ac to 0 via powercfg |

### WSL Distros

| Distro | Install Method |
|---|---|
| Ubuntu 24.04 | wsl --install -d Ubuntu-24.04 |
| Ubuntu 22.04 | wsl --install -d Ubuntu-22.04 |
| Debian | wsl --install -d Debian |

---

## How to Use USB Kit Builder

The USB Kit Builder downloads all selected installer files to a destination folder for fully offline use.

1. Open Loadout and check the apps you want on the USB drive
2. Click **Build USB Kit** in the bottom toolbar
3. In the dialog, review the app list and select a destination folder
4. Optionally check **Format drive before building** if the destination is a USB drive (exFAT or FAT32)
5. Click **Build USB Kit**

The destination folder will contain:
- Downloaded installer files for winget, direct download, and PSGallery apps
- A local copy of Loadout itself for offline launching
- A `manifest-local.json` pointing to the local files

On the target machine (no internet required): run `Loadout-Offline.ps1` from the USB root.

> VS Code extensions, WSL distros, and Windows Features are skipped by the USB builder as they require internet or OS infrastructure to install.

---

## How to Add Custom Apps

Apps not in the built-in manifest can be added without editing any files.

1. Click **Add App** in the bottom toolbar
2. Fill in:
   - **Display Name** (required) — shown in the app checklist
   - **Description** — shown as a tooltip
   - **Category** — pick an existing category or type a new one
   - **Install Method** — Winget, PSGallery, Direct Download, Chocolatey, or WSL Distro
   - **ID / URL** — winget package ID, module name, installer URL, etc.
3. For Winget: type a name in the Search box and click **Search** to look up the exact package ID
4. Click **Save**

Custom apps are saved to `%APPDATA%\Loadout\user-manifest.json`. This file is never overwritten by Loadout updates.

### Export and Import

To replicate your setup on another machine:

1. On the source machine: click **Export** and save `loadout-config.json`
2. Copy the file to the target machine
3. Open Loadout on the target machine, click **Import**, and select the file

The import restores all checkbox selections and merges any custom apps.

---

## Architecture Overview

```
Loadout/
+-- bootstrap.ps1           One-liner entry point -- permanent URL on main branch
+-- version.json            Current version and release download URL
+-- manifest.json           Master app registry (72 apps)
+-- src/
|   +-- Loadout.ps1         Entry point; loads GUI, wires all event handlers
|   +-- GUI.xaml            WPF interface definition (dark theme)
|   +-- Logger.ps1          Dual-output logging: WPF panel + disk
|   +-- ManifestManager.ps1 Manifest loading, user-manifest merging, plan resolution
|   +-- InstallEngine.ps1   7-phase install/update/uninstall engine
|   +-- UpdateChecker.ps1   Startup scan: detects installed apps and available updates
|   +-- USBBuilder.ps1      Downloads installers to a destination folder
|   +-- SelfUpdater.ps1     Version check and in-place upgrade
|   +-- Update-Helper.ps1   Out-of-process helper that swaps files while Loadout is not running
+-- .github/
|   +-- workflows/
|   |   +-- validate-manifest.yml   Validates manifest.json on every push/PR
|   |   +-- manifest-update.yml     Weekly automated version checker and updater
|   |   +-- release.yml             Builds and publishes a GitHub Release on version tag push
|   +-- schemas/
|   |   +-- manifest.schema.json    JSON Schema for manifest validation
|   +-- scripts/
|       +-- validate-manifest.py    Schema + structural checks
|       +-- check-manifest-versions.py  winget ID and version checks
+-- docs/
|   +-- index.html          GitHub Pages landing page (serves the install one-liner)
+-- tests/
    +-- parse-check.ps1         Syntax check for all .ps1 and .xaml files
    +-- test-install-engine.ps1 Dry-run install/uninstall/update engine tests
    +-- test-logger.ps1         Logger unit tests
    +-- test-update-checker.ps1 Update checker tests
    +-- test-usb-builder.ps1    USB builder dry-run tests
    +-- test-custom-app.ps1     Custom app dialog and Save-UserManifest tests
    +-- run-all-tests.ps1       Master test runner
```

**Technology:** PowerShell 5.1+ with WPF via `[System.Windows.Markup.XamlReader]`. No extra runtime required on any supported Windows version.

**Install priority:** winget > PSGallery > direct download > Chocolatey (last resort, confirmed by user)

**Minimum OS:** Windows 10 build 1903. Full support on Windows 11 and Windows Server 2016/2019/2022/2025. WSL is hidden on Server OS.

---

## Development

### Running Loadout from source

```powershell
powershell -ExecutionPolicy Bypass -NoExit -File src\Loadout.ps1
```

The `-NoExit` flag keeps the console open so errors are visible if the GUI crashes on startup.

### Running the test suite

```powershell
powershell -ExecutionPolicy Bypass -File tests\run-all-tests.ps1
```

Individual test files can be run directly from the repo root.

### Pre-push checks

Use the repo check script before pushing:

```bash
./check.sh
```

`check.sh` runs:
- `tests/parse-check.ps1`
- `tests/run-all-tests.ps1`
- `gitleaks detect --source . --no-banner`

### Sanitize repository metadata

If files were copied from Windows into WSL/Linux, remove `Zone.Identifier`
artifacts before commit:

```bash
find . -name '*:Zone.Identifier' -type f -delete
```

### Manifest validation

```powershell
python .github/scripts/validate-manifest.py
```

Requires Python 3 with `jsonschema`: `pip install jsonschema`.

### Linux migration handoff

If you are continuing work from Ubuntu WSL2, use the handoff guide:

- `docs/linux-handoff.md`

---

## License

MIT License. See [LICENSE](LICENSE).

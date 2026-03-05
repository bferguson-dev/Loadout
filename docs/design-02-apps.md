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


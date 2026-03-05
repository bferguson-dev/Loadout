# LOADOUT — Design Document Index

This file is the index only. All detail lives in numbered files under `docs/`.
Do NOT read this file's linked files speculatively — only read the one you need.

## Files

| # | File | Contents | Read When |
|---|---|---|---|
| 01 | [docs/design-01-overview.md](docs/design-01-overview.md) | HOW TO USE table, Sections 1-4: Project overview, repo structure, architecture, delivery modes | Session orientation, architecture questions |
| 02 | [docs/design-02-apps.md](docs/design-02-apps.md) | Sections 5-6: Full app list, manifest schema | Manifest work, adding apps |
| 03 | [docs/design-03-components.md](docs/design-03-components.md) | Sections 7-16: Bootstrapper, Logger, Install Engine, Update System, GUI, Uninstall, WSL, Windows Features, VS Code Extensions, USB Kit Builder | Building a specific component |
| 04 | [docs/design-04-features.md](docs/design-04-features.md) | Sections 17-23: Self-updater, Custom apps, Import/Export, GitHub Actions, Notifications, Failure Report, Documentation | Sessions 14-20 |
| 05 | [docs/design-05-standards.md](docs/design-05-standards.md) | Section 24 + Appendices: Testing strategy, Quick reference, Final decisions, Coding standards | Coding questions, final decisions list |
| 06 | [docs/design-06-sessions.md](docs/design-06-sessions.md) | Appendix: Implementation log for Sessions 1-6 and Session 7 spec | Debugging prior sessions, starting Session 7+ |

## Session Quick-Lookup

| Session | Component | Read |
|---|---|---|
| 7 | GUI + Engine Integration | 03 (GUI, Install Engine sections) + 06 (Session 7 spec at bottom) |
| 8 | Commit Preview | 03 (GUI -- Commit Preview section) |
| 9 | Uninstall | 03 (Uninstall section) |
| 10 | WSL Installer | 03 (WSL Installer section) |
| 11 | Windows Features + Settings | 03 (Windows Features section) |
| 12 | VS Code Extensions | 03 (VS Code Extensions section) |
| 13 | USB Kit Builder | 03 (USB Kit Builder section) |
| 14 | Self-Updater | 04 (Self-Update section) |
| 15 | Custom App Feature | 04 (Custom App section) |
| 16 | Import/Export | 04 (Import/Export section) |
| 17 | GitHub Actions | 04 (GitHub Actions section) |
| 18 | Scheduled Scan + Notifications | 04 (Update Notifications section) |
| 19 | Failure Report | 04 (Failure Report section) |
| 20 | README + GitHub Pages | 04 (Documentation section) |
| 21 | Testing + Dry Run | 05 (Testing Strategy section) |

## Locked Decisions (do not re-litigate)

- PowerShell + WPF -- not Python, not Electron, not C#
- winget first -> PSGallery -> direct download -> Chocolatey last resort
- No toast notifications -- status bar only
- WSL 2 only, wsl --install for distros, WSL hidden on Server OS
- AppData install location (%APPDATA%\Loadout\)
- Declarative model with commit preview diff before any action
- Minimum Windows 10 build 1903
- ASCII-only rule for all .ps1 files (see docs/design-05-standards.md)

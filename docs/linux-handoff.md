# Linux Handoff (Ubuntu WSL2)

This project is currently Windows-first (PowerShell + WPF + winget + registry).
This file is a handoff for continuing work from Ubuntu WSL2 with minimal re-discovery.

## Ground Truth

- GUI runtime is Windows-only (`src/GUI.xaml`, WPF assemblies in `src/Loadout.ps1`).
- Installer/runtime operations are Windows-only in current form:
  - `winget.exe`
  - `reg.exe` / Windows registry cmdlets
  - Windows Features/Capabilities cmdlets
- Most static validation and dry-run logic is still useful from Linux.

## Linux Setup (inside Ubuntu WSL2)

1. Clone/open repo in WSL filesystem.
2. Install core tools:
   - `git`
   - `ripgrep`
   - `python3`
   - `pwsh` (PowerShell 7)
3. Verify:
   - `pwsh --version`
   - `git --version`
   - `rg --version`

## Linux-Safe Validation Commands

Run these from repo root in WSL:

```bash
pwsh -NoProfile -File tests/parse-check.ps1
pwsh -NoProfile -File tests/verify-session6.ps1
pwsh -NoProfile -File tests/verify-session15.ps1
pwsh -NoProfile -File tests/verify-session16.ps1
```

Use caution with full test runs in Linux; scripts expecting Windows environment may fail for non-code reasons.

## Known Windows Coupling Hotspots

- `src/Loadout.ps1`: WPF UI bootstrapping and event wiring.
- `src/InstallEngine.ps1`: winget/registry/windows-feature operations.
- `src/UpdateChecker.ps1`: winget list parsing and Windows app detection.
- `src/SelfUpdater.ps1` + `src/Update-Helper.ps1`: Windows process/update flow.

## Migration Strategy (recommended)

1. Preserve current Windows app behavior as a compatibility track.
2. Extract platform-agnostic core first:
   - manifest loading and validation
   - commit-plan resolution logic
   - result/status models
3. Introduce platform adapters:
   - `WindowsAdapter` (existing behavior)
   - `LinuxAdapter` (apt/snap/flatpak/etc.)
4. Add a Linux CLI entry point before attempting Linux GUI.
5. Keep tests split by platform:
   - platform-neutral tests (run everywhere)
   - Windows integration tests
   - Linux integration tests

## Future-Me Checklist (Linux)

When resuming work in Linux, do this first:

1. Confirm tools:
   - `pwsh`, `git`, `rg`
2. Run static gates:
   - `tests/parse-check.ps1`
   - `tests/verify-session6.ps1`
   - `tests/verify-session15.ps1`
   - `tests/verify-session16.ps1`
3. Do not chase `winget`/firewall/registry failures inside Linux.
4. If adding Linux runtime support, start by introducing adapter interfaces, not by patching Windows-specific functions inline.
5. Keep files ASCII-only where required by repo tests.

## Non-Goals in WSL Linux Session

- Fixing Windows firewall/App Installer from Linux context.
- Running full WPF app from Linux.
- Treating Windows-only integration failures as regressions.

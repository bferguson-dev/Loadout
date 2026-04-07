*[!] This project is provided as-is, without warranties or guarantees of any
kind, and has not been validated in a production environment unless explicitly
stated otherwise. You are solely responsible for evaluating, testing, securing,
and operating it safely in your environment and for verifying compliance with
any legal, regulatory, or contractual requirements. By using this project, you
accept all risk, and the authors and contributors assume no liability for any
loss, damage, outage, misuse, or other consequences arising from its use. [!]*

# Loadout

Loadout is a portable PowerShell + WPF workstation setup tool for Windows.
It installs, updates, and removes a curated set of infrastructure,
development, remote access, and operations tools from a single checklist.

Use Loadout when you want a repeatable workstation bootstrap workflow with a
commit preview, local logging, import/export support, and an offline USB kit
builder.

## Non-Goals

- This is not a production-validated endpoint management platform.
- This does not replace enterprise software deployment, patch management, or
  compliance tooling.
- This does not guarantee vendor installer quality, package trust, or upgrade
  safety for third-party software.
- This does not manage Linux or macOS hosts.

## Requirements

- Windows 10 build 1903 or later, or a supported Windows Server release
- PowerShell 5.1 or PowerShell 7 to launch the app from source
- Internet access for normal installs and updates
- Administrator rights for packages or Windows features that require elevation
- `winget` for the default package path

## Assumptions

- The machine is a Windows workstation or server that can run WPF.
- Package sources such as `winget`, PowerShell Gallery, and vendor download
  endpoints are reachable unless you are using a USB kit.
- `%APPDATA%` is writable because Loadout stores user data there.
- Some package installs, feature enables, or updates may require a reboot.

## Install

Open an elevated PowerShell prompt and run:

```powershell
irm https://bferguson-dev.github.io/Loadout/install | iex
```

The install shim in [`docs/install`](docs/install) forwards to
[`bootstrap.ps1`](bootstrap.ps1).
Loadout installs to `%APPDATA%\Loadout`, can create shortcuts, and checks for
updates on launch.

## Run From Source

Launch the app from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -NoExit -File src\Loadout.ps1
```

The `-NoExit` flag keeps the console open so startup failures remain visible.

## What It Manages

Loadout reads [`manifest.json`](manifest.json) as the source of truth for
built-in apps and features.

- Development tools such as VS Code, Python, Git, Windows Terminal, and
  PowerShell 7
- VS Code extensions installed through `code --install-extension`
- Remote access tools such as PuTTY, WinSCP, FileZilla, and Tailscale
- Infrastructure tools such as Terraform, AWS CLI, Azure CLI, and OpenLens
- PowerShell modules from PSGallery
- Windows features, Windows settings, and selected WSL distros

The default install preference is:

```text
winget -> PowerShell Gallery -> direct download -> Chocolatey (last resort)
```

## Usage

### Standard workflow

1. Start Loadout.
2. Select the apps, modules, features, settings, and WSL distros you want.
3. Review the commit preview to confirm what will be installed, updated, or
   removed.
4. Click `Commit`.
5. Review the log output for successes, failures, reboot prompts, or skipped
   items.

### USB Kit Builder

Use the USB builder for offline deployment support.

1. Select the items you want in Loadout.
2. Click `Build USB Kit`.
3. Choose a destination folder.
4. Optionally format a removable drive if you intend to build directly to USB.
5. Run `Loadout-Offline.ps1` from the generated kit on the target machine.

Expected USB builder output:

- downloaded installer payloads for supported app types
- a local copy of Loadout
- a `manifest-local.json` that points to local installer files

VS Code extensions, WSL distros, and Windows features are not packaged for
offline installation because they depend on internet access or OS-managed
infrastructure.

### Custom apps and config portability

Custom apps are stored in `%APPDATA%\Loadout\user-manifest.json` and are not
overwritten by updates.

Use `Export` and `Import` to move selections and custom app definitions
between machines.

## Expected Output

When the app is working correctly, you should expect:

- a startup scan that pre-checks already-installed items where supported
- a commit preview before any install, update, or uninstall action runs
- per-item status results in the UI and the log file
- persistent app state under `%APPDATA%\Loadout`
- update prompts when a newer packaged release is available

## Repository Layout

```text
Loadout/
+-- bootstrap.ps1
+-- manifest.json
+-- version.json
+-- check.sh
+-- src/
|   +-- Loadout.ps1
|   +-- GUI.xaml
|   +-- Logger.ps1
|   +-- ManifestManager.ps1
|   +-- InstallEngine.ps1
|   +-- UpdateChecker.ps1
|   +-- USBBuilder.ps1
|   +-- SelfUpdater.ps1
|   +-- Update-Helper.ps1
+-- tests/
|   +-- parse-check.ps1
|   +-- run-all-tests.ps1
|   +-- test-*.ps1
|   +-- verify-*.ps1
+-- docs/
|   +-- index.html
|   +-- install
|   +-- design-*.md
+-- .github/
    +-- workflows/
    +-- scripts/
    +-- schemas/
```

## Validation Workflow

Run the repository quality gate before pushing changes:

```bash
./check.sh
```

The gate is intended to prove more than syntax:

- Git hygiene checks for staged diffs when relevant
- PowerShell parse validation
- the PowerShell test suite
- manifest validation
- JSON and Markdown sanity checks
- shell syntax checks
- optional secret scanning with `gitleaks`
- optional staged secret scanning with `gitleaks`

If a tool is unavailable, `check.sh` reports that as a skip or warning rather
than a false pass.

To enable the local pre-commit hook path:

```bash
git config core.hooksPath .githooks
```

## CI

GitHub Actions runs the repo quality gate on pushes and pull requests. The CI
path also runs a dedicated gitleaks action because hosted runners do not
guarantee the local `gitleaks` binary is preinstalled.

## Troubleshooting

### The GUI does not open

- Launch from source with `-NoExit` so the console stays open.
- Run `tests/parse-check.ps1` to catch syntax issues before debugging the UI.
- Confirm the host is Windows with WPF support.

### Tests fail in Linux or WSL

- Use PowerShell 7 (`pwsh`) when Windows PowerShell is not available.
- Review [`docs/linux-handoff.md`](docs/linux-handoff.md) for the supported
  cross-platform validation path.
- Do not treat Linux validation as proof that the WPF GUI path works.

### Install or update actions fail

- Confirm the package source is reachable.
- Re-run with elevation if the selected item requires it.
- Review the log for the exact package or feature that failed.
- If a package source changed upstream, validate the corresponding manifest
  entry before retrying.

### Copied files show `Zone.Identifier`

Remove copied Windows metadata files before committing:

```bash
find . -name '*:Zone.Identifier' -type f -delete
```

## Known Limitations

- The GUI path is Windows-only because it depends on WPF.
- This repository has not been validated in a production environment.
- Third-party installer behavior can change upstream without notice.
- Offline USB builds do not cover every package type.
- Linux and WSL checks can validate scripts and tests, but they do not prove
  Windows GUI behavior.

## Recovery, Rollback, And Compatibility Notes

- Custom app definitions live in `%APPDATA%\Loadout\user-manifest.json`; keep
  an exported config if you need to rebuild a machine.
- Review the commit preview before applying destructive changes because
  uninstall behavior is driven from the selected state.
- If a release introduces problems, use a prior tagged release package and
  validate `version.json` before redeploying.
- If package identifiers or installer URLs change upstream, update
  [`manifest.json`](manifest.json) and rerun the quality gate before shipping
  the fix.

## Additional Documentation

- Design index:
  [`DESIGN.md`](DESIGN.md)
- Linux and WSL handoff guidance:
  [`docs/linux-handoff.md`](docs/linux-handoff.md)
- Full repository disclaimer:
  [`DISCLAIMER.md`](DISCLAIMER.md)

## Disclaimer

This project is provided as-is, without warranties or guarantees of any kind,
and has not been validated in a production environment unless explicitly
stated otherwise. You are solely responsible for evaluating, testing,
securing, and operating it safely in your environment and for verifying
compliance with any legal, regulatory, or contractual requirements. By using
this project, you accept all risk, and the authors and contributors assume no
liability for any loss, damage, outage, misuse, or other consequences arising
from its use.

## License

MIT License. See [LICENSE](LICENSE).

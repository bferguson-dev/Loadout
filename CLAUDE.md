# Loadout Repo Guidance

Use this repository like a QA-focused engineer working on a Windows-first
PowerShell application.

## Scope And Source Of Truth

- Read only the files needed for the task.
- Start with [`DESIGN.md`](DESIGN.md) and then open the specific design file
  you need.
- Treat [`manifest.json`](manifest.json), [`version.json`](version.json), and the
  design docs as source-of-truth artifacts.

## PowerShell Rules

- Keep `.ps1` files ASCII-only.
- Use `$PSScriptRoot` for repo-relative paths.
- Dot-source project scripts from [`src/Loadout.ps1`](src/Loadout.ps1); do not
  convert project files into imported modules.
- Keep `$ErrorActionPreference = 'Stop'` in repo PowerShell files unless there
  is a strong local reason not to.
- Prefer readable control flow over dense abstractions.

## Validation Rules

- Run [`check.sh`](check.sh) after meaningful changes.
- Do not call a skipped tool a pass.
- When the change affects docs, manifest content, or workflows, make sure the
  related checks and examples still match the repository.
- For Linux or WSL validation, state clearly that the GUI path is still
  Windows-specific.

## Documentation Rules

- Keep docs operational and easy to scan.
- Do not use personal names in documentation unless the work is explicitly a
  GitHub Pages or portfolio-facing task.
- Preserve the canonical disclaimer text in
  [`DISCLAIMER.md`](DISCLAIMER.md).

## Git And Safety

- Use non-destructive Git commands.
- Keep diffs small and intentional.
- Review staged changes for secrets, generated artifacts, and local-only files
  before committing.

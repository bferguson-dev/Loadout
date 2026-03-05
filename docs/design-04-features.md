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

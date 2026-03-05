# Loadout v1.0.0 -- Internal User Testing Checklist

Run the app with:
```powershell
powershell -ExecutionPolicy Bypass -NoExit -File src\Loadout.ps1
```

Mark each item PASS / FAIL / NOTES before signing off for release.

---

## 1. Startup
- [ ] App window opens without errors
- [ ] App list populates with categories and checkboxes
- [ ] No red errors in the console

## 2. Admin Elevation
- [ ] If running without admin: warning appears in status bar or UAC prompt fires
- [ ] If running as admin: no warning, app proceeds normally

## 3. Install Checkboxes + Commit Preview
- [ ] Check 2-3 apps from different categories
- [ ] Click Commit -- diff preview dialog appears listing selected apps
- [ ] Cancel out (do not actually install)

## 4. Scan (Update Checker)
- [ ] Click Scan button in bottom bar
- [ ] Progress indicator appears while scan runs
- [ ] After scan: installed apps show a version number in grey
- [ ] If any updates available: version shown as "old->new" in yellow
- [ ] Scan results persist if you click away and come back

## 5. Select All Updates / Deselect All Updates
- [ ] "Select All Updates" button checks all update checkboxes for apps with updates available
- [ ] "Deselect All Updates" unchecks them all
- [ ] Install checkboxes are NOT affected by these buttons

## 6. Font Size Scaling (T+ / T-)
- [ ] T+ increases font size of category labels and column headers
- [ ] T- decreases them
- [ ] Update column header and slot width scale together (stay aligned)
- [ ] Scrollbar stays on the right edge regardless of font size

## 7. Add App (Custom App Dialog)
- [ ] Click "Add App" in bottom bar -- dialog opens
- [ ] Type a partial name in the search box and press Enter or click Search
- [ ] Search results populate in the list
- [ ] Clicking a result auto-fills the Winget ID field
- [ ] Fill in Name + ID and click Add -- app appears in the main list under its category
- [ ] Verify %APPDATA%\Loadout\user-manifest.json was created/updated

## 8. Manage Apps
- [ ] Click "Manage Apps" -- dialog opens listing custom apps
- [ ] Deleting a custom app removes it from the list and from user-manifest.json
- [ ] The deleted app is NOT uninstalled from the system (if it was installed)
- [ ] Main app list rebuilds after deletion

## 9. Import / Export Config
- [ ] Click Import/Export -- menu or dialog appears
- [ ] Export: saves a .json file; open it and confirm it contains selectedIds and customApps
- [ ] Import: load the exported file back; selected checkboxes restore correctly

## 10. Settings
- [ ] Settings button is in the TOP BAR (right of T+)
- [ ] Dialog opens with expected options (DryRun toggle, Chocolatey toggle, etc.)
- [ ] Changes persist after closing and reopening settings

## 11. Build USB Kit
- [ ] Click "Build USB Kit" in bottom bar -- dialog opens
- [ ] Dialog shows destination path picker and app list
- [ ] Cancel without building (no drive required for this check)
- [ ] No errors in console after cancelling

## 12. Clean Close
- [ ] Close the window normally
- [ ] Console shows no unhandled exceptions after close
- [ ] No orphaned powershell.exe processes left running (check Task Manager)

---

## Sign-off

| Result | |
|---|---|
| Tester | |
| Date | |
| Overall | PASS / FAIL |
| Notes | |

If all items pass: proceed with release steps in MEMORY.md.

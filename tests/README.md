# Regression checks

On Windows with PowerShell 7, run from the repository folder:

```powershell
pwsh -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Run-Tests.ps1
```

Checks cover actual pointer targets in full and compact layouts, offscreen startup recovery, final resize persistence, open settings dropdowns during status ticks, change-only exports and check-ins, cached imports, and graceful shortcut restart with visible/hidden windows and Settings open.

Tests briefly open isolated widget windows with example readings. They do not query Codex, access credentials, change startup registration, or interact with an existing widget. Files stay in uniquely named temporary folders whose paths are printed for troubleshooting. No test files are written into this repository.

The bootstrap replaces only account access, tray visibility, startup lookup, state paths, and the production message loop. Keep its source replacements synchronized when changing startup. Pointer checks use real WPF hit testing; raising a click event alone cannot detect a control hidden underneath another visual.

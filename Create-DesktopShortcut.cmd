@echo off
rem Create a local shortcut using the widget folder beside this helper.
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Create-DesktopShortcut.ps1"
rem Return immediately; the helper reports success or an actionable error in a popup.
exit /b

@echo off
rem Use built-in Windows PowerShell to locate PowerShell 7 without relying on PATH.
start "" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Start-AIUsageWidget.ps1"
rem Return immediately after starting the hidden launcher.
exit /b

# Forward existing desktop and sign-in shortcuts to the renamed launcher.
param([switch] $IfNotRunning)
# Preserve automatic-launch behavior and the new launcher's restart checks.
& (Join-Path $PSScriptRoot 'Start-AIUsageWidget.ps1') -IfNotRunning:$IfNotRunning

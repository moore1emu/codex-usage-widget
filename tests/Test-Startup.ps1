# Check production startup ownership and migration in a temporary folder, never the real Startup folder.
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $project 'AIUsageWidget.ps1'))
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
foreach ($name in @('Get-LaunchAtSignIn','Set-LaunchAtSignIn')) {
    $function=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    Invoke-Expression $function.Extent.Text
}
# Supply synthetic launcher and shortcut paths without starting any application.
$root=Join-Path ([IO.Path]::GetTempPath()) ('AIUsageWidget-startup-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$script:WidgetDirectory=$root
$script:StartupShortcutPath=Join-Path $root 'AI Usage Widget.lnk'
$script:LegacyStartupShortcutPath=Join-Path $root 'Codex Usage Widget.lnk'
function New-TestStartupShortcut {
    param([string]$Path,[switch]$Foreign,[switch]$LegacyLauncher)
    # Create a real shortcut with synthetic arguments so the production COM ownership checks are exercised.
    $shell=New-Object -ComObject WScript.Shell
    $shortcut=$shell.CreateShortcut($Path)
    try {
        $shortcut.TargetPath=if ($Foreign) {Join-Path $env:SystemRoot 'System32/notepad.exe'} else {Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'}
        $launcher=Join-Path $root $(if ($LegacyLauncher) {'Start-CodexUsageWidget.ps1'} else {'Start-AIUsageWidget.ps1'})
        $shortcut.Arguments=if ($Foreign) {''} else {'-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -IfNotRunning' -f $launcher}
        $shortcut.Save()
    } finally {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
}
# A matching old name and old launcher migrate to one correctly named entry.
New-TestStartupShortcut $script:LegacyStartupShortcutPath -LegacyLauncher
if (-not (Get-LaunchAtSignIn)) {throw 'A matching legacy entry was not recognized.'}
Set-LaunchAtSignIn $true
if (-not (Get-LaunchAtSignIn -Path $script:StartupShortcutPath) -or (Test-Path -LiteralPath $script:LegacyStartupShortcutPath)) {throw 'Startup rename left a duplicate or incorrect launcher.'}
# Disabling startup removes both names when both entries belong to this widget.
New-TestStartupShortcut $script:LegacyStartupShortcutPath
Set-LaunchAtSignIn $false
if ((Test-Path -LiteralPath $script:StartupShortcutPath) -or (Test-Path -LiteralPath $script:LegacyStartupShortcutPath)) {throw 'Disabling startup left an owned entry behind.'}
# A different target is preserved instead of being overwritten or removed.
New-TestStartupShortcut $script:LegacyStartupShortcutPath -Foreign
$before=[Convert]::ToBase64String([IO.File]::ReadAllBytes($script:LegacyStartupShortcutPath))
$rejected=$false
try {Set-LaunchAtSignIn $true} catch {$rejected=$true}
if (-not $rejected -or (Get-LaunchAtSignIn) -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:LegacyStartupShortcutPath)) -ne $before) {throw 'A different startup target was modified.'}
Remove-Item -LiteralPath $script:LegacyStartupShortcutPath
# A failed new-file save must leave the working old shortcut available.
New-TestStartupShortcut $script:LegacyStartupShortcutPath
$script:StartupShortcutPath=Join-Path $root 'missing/AI Usage Widget.lnk'
$rejected=$false
try {Set-LaunchAtSignIn $true} catch {$rejected=$true}
if (-not $rejected -or -not (Test-Path -LiteralPath $script:LegacyStartupShortcutPath)) {throw 'A failed upgrade removed the previous startup entry.'}
Write-Output 'PASS: startup display name, legacy migration, duplicate removal, target ownership and failed-save retention.'
Write-Output ('Temporary test files: '+$root)

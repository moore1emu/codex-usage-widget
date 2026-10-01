# Run portable checks in separate processes so WPF shutdown and preferences cannot leak between tests.
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Run this test runner in PowerShell 7 on Windows.' }
$pwshPath = Join-Path $PSHOME 'pwsh.exe'
$project = Split-Path -Parent $PSScriptRoot
# Parse production and test scripts before opening isolated windows.
foreach ($file in @(Get-ChildItem -LiteralPath $project -Filter '*.ps1') + @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1')) {
    $tokens=$null; $parseErrors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw ($file.Name + ': ' + ($parseErrors.Message -join '; ')) }
}
# Use PowerShell 7 for sharing and actual WPF interaction checks.
foreach ($name in @('Test-Sharing.ps1','Test-WindowControls.ps1','Test-SettingsDropdowns.ps1')) {
    & $pwshPath -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $name)
    if ($LASTEXITCODE -ne 0) { throw ($name + ' failed.') }
}
# Exercise shortcut shutdown under the same built-in Windows PowerShell used by the launcher.
$windowsPowerShell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
& $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'Test-ShortcutRestart.ps1') -PwshPath $pwshPath
if ($LASTEXITCODE -ne 0) { throw 'Shortcut restart checks failed.' }
Write-Output 'PASS: all regression checks.'

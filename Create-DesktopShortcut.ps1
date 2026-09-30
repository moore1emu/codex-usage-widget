# Allow a different destination for testing or users who prefer a folder other than the desktop.
param(
    [string] $DestinationDirectory = [Environment]::GetFolderPath('Desktop'),
    [switch] $Quiet
)

# Use built-in Windows PowerShell so shortcut creation itself does not require PowerShell 7.
$ErrorActionPreference = 'Stop'
$shell = $null
$shortcut = $null
try {
    # Derive every application path from this file's location, never from the author's computer.
    $launcherPath = Join-Path $PSScriptRoot 'Start-CodexUsageWidget.ps1'
    $iconPath = Join-Path $PSScriptRoot 'CodexUsage-Tricolor.ico'
    foreach ($requiredPath in @($launcherPath, $iconPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) { throw 'Keep this helper with the widget scripts and icon, then try again.' }
    }
    if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) { throw 'The shortcut destination folder does not exist.' }
    # Refuse to overwrite an unrelated existing shortcut with the same name.
    $shortcutPath = Join-Path $DestinationDirectory 'Codex Usage.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $targetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $launcherPath
    if ((Test-Path -LiteralPath $shortcutPath) -and ($shortcut.TargetPath -ne $targetPath -or $shortcut.Arguments -ne $arguments)) {
        throw 'A different Codex Usage shortcut already exists here. Rename or remove that shortcut before creating this one.'
    }
    # Use the same launcher as the CMD file, including its existing-instance restart check.
    $shortcut.TargetPath = $targetPath
    $shortcut.Arguments = $arguments
    $shortcut.WorkingDirectory = $PSScriptRoot
    $shortcut.IconLocation = $iconPath + ',0'
    $shortcut.Description = 'Open the Codex Usage widget.'
    $shortcut.Save()
    # Report where the local shortcut was created without launching the widget.
    if (-not $Quiet) { [void]$shell.Popup("Shortcut created:`r`n$shortcutPath`r`n`r`nKeep the widget folder in this location.", 0, 'Codex Usage', 64) }
}
catch {
    # Preserve a usable error for unattended tests, or show it when launched with a double-click.
    if ($Quiet) { throw }
    if (-not $shell) { $shell = New-Object -ComObject WScript.Shell }
    [void]$shell.Popup($_.Exception.Message, 0, 'Codex Usage - Shortcut not created', 16)
    exit 1
}
finally {
    # Release shortcut COM objects before the short-lived helper exits.
    if ($shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    if ($shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}

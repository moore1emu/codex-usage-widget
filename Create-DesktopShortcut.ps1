# Allow a different destination for testing or users who prefer a folder other than the desktop.
param(
    [string] $DestinationDirectory = [Environment]::GetFolderPath('Desktop'),
    [switch] $Quiet
)

# Use built-in Windows PowerShell so shortcut creation itself does not require PowerShell 7.
$ErrorActionPreference = 'Stop'
function Test-OneDriveDestination {
    param([string] $Directory)
    # Compare complete directory boundaries so similarly named neighboring folders stay local.
    $destination = [IO.Path]::GetFullPath($Directory).TrimEnd('\')
    $roots = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)
    # Include registered accounts for multiple business accounts and custom OneDrive locations.
    $accounts = 'HKCU:\Software\Microsoft\OneDrive\Accounts'
    foreach ($account in @(Get-ChildItem -LiteralPath $accounts -ErrorAction SilentlyContinue)) {
        $settings = Get-ItemProperty -LiteralPath $account.PSPath -Name UserFolder -ErrorAction SilentlyContinue
        if ($settings.UserFolder) { $roots += $settings.UserFolder }
    }
    foreach ($root in $roots) {
        # Ignore absent or unusable registrations without guessing from the folder's name.
        if ([string]::IsNullOrWhiteSpace($root)) { continue }
        try { $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\') } catch { continue }
        if ($destination.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
            $destination.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}
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
    # Give synced desktop shortcuts distinct names while keeping local desktop names simple.
    $isOneDrive = Test-OneDriveDestination $DestinationDirectory
    # Read the full local hostname instead of the shortened Windows computer name.
    $computerName = [Environment]::MachineName
    try { $hostname = [Net.Dns]::GetHostName(); if ($hostname) { $computerName = $hostname } } catch { }
    $shortcutName = if ($isOneDrive) { 'Codex Usage - ' + $computerName + '.lnk' } else { 'Codex Usage.lnk' }
    $shortcutPath = Join-Path $DestinationDirectory $shortcutName
    # Refuse to overwrite an unrelated existing shortcut with the same name.
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
    # Retire generic and shortened names only when they point to this exact local launcher.
    $legacyNames = @('Codex Usage.lnk', ('Codex Usage - ' + [Environment]::MachineName + '.lnk'))
    foreach ($legacyName in $legacyNames) {
        $legacyPath = Join-Path $DestinationDirectory $legacyName
        if (-not $isOneDrive -or $legacyPath -eq $shortcutPath -or -not (Test-Path -LiteralPath $legacyPath -PathType Leaf)) { continue }
        $legacy = $shell.CreateShortcut($legacyPath)
        try {
            if ($legacy.TargetPath -eq $targetPath -and $legacy.Arguments -eq $arguments) {
                Remove-Item -LiteralPath $legacyPath
            }
        } finally { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($legacy) }
    }
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

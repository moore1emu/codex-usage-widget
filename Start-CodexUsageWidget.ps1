# Automatic launchers can leave an existing widget alone without showing a restart prompt.
param([switch] $IfNotRunning)

# Use Windows PowerShell 5.1-compatible syntax to bootstrap PowerShell 7.
$ErrorActionPreference = 'Stop'

function Get-ExistingWidgetProcesses {
    param([string] $WidgetPath)
    # Match this exact script path, never other PowerShell tasks or the usage reader.
    $pattern = '(?i)(?:^|\s)-File\s+(?:"' + [regex]::Escape($WidgetPath) + '"|' + [regex]::Escape($WidgetPath) + '(?=\s|$))'
    $sessionId = (Get-Process -Id $PID).SessionId
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($record in @(Get-CimInstance Win32_Process -Filter "Name = 'pwsh.exe' OR Name = 'powershell.exe'")) {
        # Restrict replacement to the current Windows user and desktop session.
        if ($record.SessionId -ne $sessionId -or $record.CommandLine -notmatch $pattern) { continue }
        $owner = Invoke-CimMethod -InputObject $record -MethodName GetOwnerSid
        if ($owner.ReturnValue -ne 0 -or $owner.Sid -ne $sid) { continue }
        $record
    }
}

function Confirm-WidgetRestart {
    # Offer an explicit restart action with Cancel as the safe default.
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = 'Codex Usage is already running'
    $dialog.ClientSize = New-Object System.Drawing.Size(420,125)
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.StartPosition = 'CenterScreen'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.TopMost = $true
    $label = New-Object System.Windows.Forms.Label
    $label.SetBounds(15,15,390,50)
    $label.Text = 'Restart the widget to load the current version? Your settings will be saved before it closes.'
    $restart = New-Object System.Windows.Forms.Button
    $restart.SetBounds(125,80,145,28)
    $restart.Text = 'Restart widget'
    $restart.DialogResult = [Windows.Forms.DialogResult]::OK
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.SetBounds(280,80,125,28)
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = [Windows.Forms.DialogResult]::Cancel
    $dialog.Controls.AddRange(@($label,$restart,$cancel))
    $dialog.AcceptButton = $cancel
    $dialog.CancelButton = $cancel
    try { return $dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK }
    finally { $dialog.Dispose() }
}

function Close-ExistingWidgets {
    param([object[]] $Instances)
    # Enumerate hidden windows too, since a tray-only widget has no MainWindowHandle.
    if (-not ('CodexUsageLauncher.Windows' -as [type])) {
        Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace CodexUsageLauncher {
    public static class Windows {
        private delegate bool EnumCallback(IntPtr hwnd, IntPtr parameter);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumCallback callback, IntPtr parameter);
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int length);
        [DllImport("user32.dll")] private static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
        // Register the same dedicated shutdown message as the widget, without closing individual accounts.
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] private static extern uint RegisterWindowMessage(string name);
        public static bool RequestClose(int processId) {
            bool sent = false;
            // Restart uses the full Exit path; ordinary WM_CLOSE only hides one account in Separate windows.
            uint exitMessage = RegisterWindowMessage("CodexUsageWidget.RestartExit");
            EnumWindows(delegate(IntPtr hwnd, IntPtr ignored) {
                uint pid;
                GetWindowThreadProcessId(hwnd, out pid);
                if (pid != processId) return true;
                var title = new StringBuilder(256);
                GetWindowText(hwnd, title, title.Capacity);
                if (title.ToString().StartsWith("Codex Usage v", StringComparison.Ordinal) &&
                    !title.ToString().EndsWith("Settings", StringComparison.Ordinal))
                    sent = PostMessage(hwnd, exitMessage, IntPtr.Zero, IntPtr.Zero) || sent;
                return true;
            }, IntPtr.Zero);
            return sent;
        }
    }
}
'@
    }
    foreach ($instance in $Instances) {
        # A widget may have exited while the confirmation dialog was open.
        try { $process = [Diagnostics.Process]::GetProcessById([int]$instance.ProcessId) }
        catch [ArgumentException] { continue }
        try {
            # Do not act on a recycled process ID belonging to a newer process.
            if ([Math]::Abs(($process.StartTime - $instance.CreationDate).TotalSeconds) -gt 1) { continue }
            if (-not $process.HasExited -and -not [CodexUsageLauncher.Windows]::RequestClose($process.Id)) {
                throw 'Close the current widget before launching. Its window is not ready to close normally.'
            }
            if (-not $process.WaitForExit(10000)) {
                throw 'Close the current widget before launching. It did not finish closing within 10 seconds; it has not been force-closed. If this is an older version, choose Exit from its tray menu once, then launch again.'
            }
        } finally { $process.Dispose() }
    }
}

$launchMutex = $null
$ownsLaunchMutex = $false
try {
    # Prefer PowerShell 7 when the shell can already locate its executable.
    $command = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $pwshPath = if ($command) { $command.Source } else { $null }

    # Check common machine-wide and per-user installations when PATH is incomplete.
    if (-not $pwshPath) {
        $candidates = @(
            "$env:ProgramFiles\PowerShell\7\pwsh.exe"
            "${env:ProgramFiles(x86)}\PowerShell\7\pwsh.exe"
            "$env:LOCALAPPDATA\Programs\PowerShell\7\pwsh.exe"
            "$env:LOCALAPPDATA\Microsoft\PowerShell\7\pwsh.exe"
        )
        # Select the first existing installation rather than changing Windows PATH.
        $pwshPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }

    # Check Microsoft Store installations if standard locations were not found.
    if (-not $pwshPath) {
        $packages = Get-AppxPackage -Name 'Microsoft.PowerShell' -ErrorAction SilentlyContinue
        foreach ($package in $packages) {
            # Resolve the executable inside the current user's registered package.
            $candidate = Join-Path $package.InstallLocation 'pwsh.exe'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $pwshPath = $candidate
                break
            }
        }
    }

    # Give an actionable message if PowerShell 7 is missing or installed elsewhere.
    if (-not $pwshPath) {
        throw 'PowerShell 7 could not be found. Install PowerShell 7 on this computer, or add the folder containing pwsh.exe to PATH if it is already installed, then launch the widget again.'
    }

    # Resolve the widget beside this launcher so OneDrive paths with spaces work.
    $widgetPath = Join-Path $PSScriptRoot 'CodexUsageWidget.ps1'
    if (-not (Test-Path -LiteralPath $widgetPath -PathType Leaf)) {
        throw 'CodexUsageWidget.ps1 is missing. Wait for OneDrive to finish syncing the widget folder, then try again.'
    }
    # Check the usage reader before opening a widget that would be unable to refresh.
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Get-CodexUsage.ps1') -PathType Leaf)) {
        throw 'Get-CodexUsage.ps1 is missing. Wait for OneDrive to finish syncing the widget folder, then try again.'
    }

    # Serialize simultaneous shortcut clicks for this folder and current user/session.
    $hashAlgorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $identity = [IO.Path]::GetFullPath($widgetPath).ToUpperInvariant() + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $pathHash = [BitConverter]::ToString($hashAlgorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($identity))).Replace('-','')
    } finally { $hashAlgorithm.Dispose() }
    $launchMutex = New-Object System.Threading.Mutex($false, ('Local\CodexUsageLaunch-' + $pathHash))
    try { $ownsLaunchMutex = $launchMutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $ownsLaunchMutex = $true }
    if (-not $ownsLaunchMutex) { return }
    # Ask only for manual launches; automatic launchers leave a current instance untouched.
    $existing = @(Get-ExistingWidgetProcesses -WidgetPath $widgetPath)
    if ($existing.Count) {
        if ($IfNotRunning -or -not (Confirm-WidgetRestart)) { return }
        Close-ExistingWidgets -Instances $existing
    }

    # Start the WPF widget in a hidden STA PowerShell 7 process.
    $arguments = '-NoLogo -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $widgetPath
    Start-Process -FilePath $pwshPath -ArgumentList $arguments -WindowStyle Hidden -ErrorAction Stop | Out-Null
}
catch {
    # Show startup errors even though the launcher's console is hidden.
    $shell = New-Object -ComObject WScript.Shell
    [void] $shell.Popup($_.Exception.Message, 0, 'Codex Usage Widget - Unable to start', 16)
    exit 1
}
finally {
    # Release launcher coordination even after Cancel, a failed close, or an error.
    if ($ownsLaunchMutex) { $launchMutex.ReleaseMutex() }
    if ($launchMutex) { $launchMutex.Dispose() }
}

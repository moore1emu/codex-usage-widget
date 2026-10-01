$ErrorActionPreference = 'Stop'
# Report otherwise invisible startup failures from the hidden PowerShell process.
trap {
    $startupMessage = $_.Exception.Message
    try {
        # Keep diagnostics on this computer rather than in the shared OneDrive folder.
        $logDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexUsageWidget'
        [void](New-Item -ItemType Directory -Path $logDirectory -Force)
        $logPath = Join-Path $logDirectory 'startup-error.log'
        "$(Get-Date -Format o)`r`n$($_ | Out-String)" | Set-Content -LiteralPath $logPath -Encoding utf8
        $startupMessage += "`r`n`r`nDetails: $logPath"
    } catch { }
    # Use the built-in popup even when WPF initialization itself failed.
    $errorShell = New-Object -ComObject WScript.Shell
    [void]$errorShell.Popup($startupMessage, 0, 'Codex Usage Widget - Error', 16)
    exit 1
}
# Bump this version and the separate changelog together for each released update.
$script:WidgetVersion = '2.0.3'
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
# Use Windows' app color preference for native menus and settings before creating controls.
if ([System.Windows.Forms.Application].GetMethods().Name -contains 'SetColorMode') {
    [System.Windows.Forms.Application]::SetColorMode([System.Windows.Forms.SystemColorMode]::System)
}
[System.Windows.Forms.Application]::EnableVisualStyles()

if (-not ('CodexUsageWidget.NativeMethods' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace CodexUsageWidget {
    public static class NativeMethods {
        // Share native screen coordinates between dragging and monitor placement.
        [StructLayout(LayoutKind.Sequential)]
        public struct Point { public int X, Y; }
        [StructLayout(LayoutKind.Sequential)]
        public struct Rect { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)]
        public struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
        [DllImport("user32.dll")]
        public static extern bool GetCursorPos(out Point point);
        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr window, out Rect rect);
        [DllImport("user32.dll")]
        public static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
        // Move directly without entering the shell's snap-enabled move loop.
        [DllImport("user32.dll")]
        public static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern bool DestroyIcon(IntPtr handle);

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
    }
}
'@
}

# Use a generic app identity when the widget is shared with other users.
[void] [CodexUsageWidget.NativeMethods]::SetCurrentProcessExplicitAppUserModelID('CodexUsageWidget')

$script:WidgetDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ReaderPath = Join-Path $script:WidgetDirectory 'Get-CodexUsage.ps1'
# Windows startup entries are local to this user and computer, not synchronized preferences.
$script:StartupShortcutPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Codex Usage Widget.lnk'
$script:StateDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexUsageWidget'
if (-not (Test-Path -LiteralPath $script:StateDirectory)) {
    [void] (New-Item -ItemType Directory -Path $script:StateDirectory -Force)
}
$script:StatePath = Join-Path $script:StateDirectory 'widget-state.json'
# Remember warnings across restarts without rewriting window settings each refresh.
$script:AlertStatePath = Join-Path $script:StateDirectory 'warning-state.json'
$script:Usage = $null
$script:RefreshProcess = $null
$script:RefreshStarted = $null
# Bound the complete request, including pipe draining, and preserve error status between ticks.
$script:RefreshTimeoutSeconds = 45
$script:RefreshOutputTask = $null
$script:RefreshErrorTask = $null
$script:RefreshError = $null
$script:RefreshTimer = $null
$script:TrayIconImage = $null
$script:WindowIconImage = $null
$script:RefreshIntervalMinutes = 5
# Keep quota colors configurable while retaining the familiar defaults.
$script:PrimaryColor = '#669CFF'
$script:SecondaryColor = '#A97BFF'
# Use a muted blue-green default that complements the blue and purple quota colors.
$script:CreditColor = '#91B8B0'
# Leave alerts disabled until the user chooses a remaining-quota threshold.
$script:PrimaryAlertThreshold = 0
$script:SecondaryAlertThreshold = 0
# Reset notifications are independently opt-in, even when low-usage warnings are disabled.
$script:NotifyPrimaryReset = $false
# Show upcoming reset estimates separately from notification preferences.
$script:PrimaryResetHours = 25
$script:ShowWeeklyResetDate = $true
$script:AlertStates = @{}
# Restore sent warnings so reopening below the threshold does not repeat them.
if (Test-Path -LiteralPath $script:AlertStatePath) {
    try { $script:AlertStates = Get-Content -LiteralPath $script:AlertStatePath -Raw | ConvertFrom-Json -AsHashtable }
    catch { $script:AlertStates = @{} }
}
# Recover invalid JSON structures without discarding valid per-window notification history.
if ($script:AlertStates -isnot [System.Collections.IDictionary]) { $script:AlertStates = @{} }
foreach ($key in @($script:AlertStates.Keys)) {
    # Only a Boolean notification flag is meaningful to the warning evaluator.
    $entry = $script:AlertStates[$key]
    if ($key -notin @('primary', 'secondary', 'primaryReset') -or $entry -isnot [System.Collections.IDictionary] -or $entry.Notified -isnot [bool]) {
        $script:AlertStates.Remove($key)
        continue
    }
    # Validate the saved reset baseline before using it across restarts.
    if ($key -eq 'primaryReset') {
        $numericTypes = @([int], [long], [double], [decimal])
        if ($null -eq $entry.ResetsAt -or $null -eq $entry.UsedPercent -or
            $entry.ResetsAt.GetType() -notin $numericTypes -or $entry.UsedPercent.GetType() -notin $numericTypes -or
            $entry.ResetsAt -le 0 -or $entry.UsedPercent -lt 0 -or $entry.UsedPercent -gt 100 -or
            [double]::IsNaN([double]$entry.UsedPercent)) {
            $script:AlertStates.Remove($key)
        }
    }
}
# Show positive or unlimited credits by default, regardless of subscription usage.
$script:CreditDisplayMode = 'Available'
# Load the v2 sharing, account rendering, and unified native settings helpers.
foreach ($helper in @('WidgetSharing.ps1','WidgetAccounts.ps1','WidgetSettings.ps1')) {
    . (Join-Path $script:WidgetDirectory $helper)
}

[xml] $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Codex Usage" Width="280" Height="290" WindowStyle="None"
        MinWidth="72" MinHeight="58" AllowsTransparency="True" Background="Transparent" ResizeMode="CanResizeWithGrip"
        Topmost="True" ShowInTaskbar="False">
  <Border x:Name="OuterBorder" CornerRadius="18" Background="#F2161A23" BorderBrush="#413D4658" BorderThickness="1" Padding="18">
    <Border.Effect>
      <DropShadowEffect BlurRadius="24" ShadowDepth="7" Opacity="0.45" Color="#000000"/>
    </Border.Effect>
    <Grid x:Name="RootGrid" Grid.IsSharedSizeScope="True">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid x:Name="DragArea" Grid.Row="0" Background="Transparent">
        <!-- Align the title, status dot, and controls on a single header row. -->
        <Grid.RowDefinitions><RowDefinition Height="24"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="24"/>
          <ColumnDefinition Width="24"/>
          <ColumnDefinition Width="24"/>
          <ColumnDefinition Width="24"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <Ellipse x:Name="StatusDot" Width="9" Height="9" Fill="#4FD1A5" Margin="0,0,9,0" VerticalAlignment="Center"/>
          <StackPanel>
            <TextBlock x:Name="TitleText" Text="CODEX USAGE" Foreground="#F5F7FB" FontSize="13" FontWeight="SemiBold"/>
          </StackPanel>
        </StackPanel>
        <TextBlock x:Name="PlanText" Grid.Row="1" Grid.ColumnSpan="5" Text="Connecting…" Foreground="#8992A8" FontSize="10"/>
        <Button x:Name="RefreshButton" Grid.Column="1" Content="↻" ToolTip="Refresh now" Background="Transparent"
                Foreground="#AAB2C5" BorderThickness="0" FontSize="18" Cursor="Hand"/>
        <Button x:Name="PinButton" Grid.Column="2" Content="◉" ToolTip="Always on top: on" Background="Transparent"
                Foreground="#78A7FF" BorderThickness="0" FontSize="13" Cursor="Hand"/>
        <Button x:Name="MinimizeButton" Grid.Column="3" Content="—" ToolTip="Minimize to tray" Background="Transparent"
                Foreground="#AAB2C5" BorderThickness="0" FontSize="14" Cursor="Hand"/>
        <Button x:Name="CloseButton" Grid.Column="4" Content="×" ToolTip="Close" Background="Transparent"
                Foreground="#AAB2C5" BorderThickness="0" FontSize="19" Cursor="Hand"/>
      </Grid>

      <Grid x:Name="PrimaryArea" Grid.Row="1" Margin="0,5,0,0">
        <Grid.RowDefinitions><RowDefinition Height="27"/><RowDefinition Height="12"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto" SharedSizeGroup="UsageValue"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="PrimaryLabel" Text="5-hour window" Foreground="#DDE3EF" FontSize="13" VerticalAlignment="Center"/>
        <TextBlock x:Name="PrimaryPercent" Grid.Column="1" Text="—" Foreground="#78A7FF" FontSize="18" FontWeight="SemiBold" HorizontalAlignment="Left"/>
        <ProgressBar x:Name="PrimaryBar" Grid.Row="1" Grid.ColumnSpan="2" Height="8" Minimum="0" Maximum="100"
                     Background="#293041" Foreground="#669CFF" BorderThickness="0" Value="0"/>
        <TextBlock x:Name="PrimaryReset" Grid.Row="2" Grid.ColumnSpan="2" Text="Waiting for usage data"
                   Foreground="#8992A8" FontSize="10" TextWrapping="Wrap" VerticalAlignment="Top" Margin="0,3,0,0"/>
      </Grid>

      <Grid x:Name="SecondaryArea" Grid.Row="2" Margin="0,5,0,0">
        <Grid.RowDefinitions><RowDefinition Height="27"/><RowDefinition Height="12"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto" SharedSizeGroup="UsageValue"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="SecondaryLabel" Text="Weekly window" Foreground="#DDE3EF" FontSize="13" VerticalAlignment="Center"/>
        <TextBlock x:Name="SecondaryPercent" Grid.Column="1" Text="—" Foreground="#B893FF" FontSize="18" FontWeight="SemiBold" HorizontalAlignment="Left"/>
        <ProgressBar x:Name="SecondaryBar" Grid.Row="1" Grid.ColumnSpan="2" Height="8" Minimum="0" Maximum="100"
                     Background="#293041" Foreground="#A97BFF" BorderThickness="0" Value="0"/>
        <TextBlock x:Name="SecondaryReset" Grid.Row="2" Grid.ColumnSpan="2" Text="Waiting for usage data"
                   Foreground="#8992A8" FontSize="10" TextWrapping="Wrap" VerticalAlignment="Top" Margin="0,3,0,0"/>
      </Grid>

      <!-- Keep credits separate from quota percentages and reset countdowns. -->
      <Grid x:Name="CreditsArea" Grid.Row="3" Visibility="Collapsed" Margin="0,5,0,0" Height="27">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto" SharedSizeGroup="UsageValue"/></Grid.ColumnDefinitions>
        <TextBlock x:Name="CreditsLabel" Text="Credits" Foreground="#DDE3EF" FontSize="13" VerticalAlignment="Center"/>
        <TextBlock x:Name="CreditsText" Grid.Column="1" Foreground="#91B8B0" FontSize="18" FontWeight="SemiBold" HorizontalAlignment="Left"/>
      </Grid>
      <Grid x:Name="FooterArea" Grid.Row="4" Height="24">
        <TextBlock x:Name="UpdatedText" Text="Starting…" Foreground="#687187" FontSize="9" VerticalAlignment="Bottom"/>
      </Grid>

      <Border x:Name="UltraCompactPanel" Grid.RowSpan="5" Visibility="Collapsed" Background="Transparent"
              ToolTip="Usage left · Top: 5-hour · Bottom: weekly · Double-click to expand">
        <Grid VerticalAlignment="Center">
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <!-- Keep each reset countdown directly below its corresponding percentage. -->
          <StackPanel Grid.Row="0" HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock x:Name="CompactPrimaryPercent" Text="—" Foreground="#78A7FF" FontSize="20"
                       FontWeight="SemiBold" HorizontalAlignment="Center"/>
            <TextBlock x:Name="CompactPrimaryReset" Text="—" Foreground="#8992A8" FontSize="10"
                       HorizontalAlignment="Center"/>
          </StackPanel>
          <StackPanel Grid.Row="1" HorizontalAlignment="Center" VerticalAlignment="Center">
            <TextBlock x:Name="CompactSecondaryPercent" Text="—" Foreground="#B893FF" FontSize="20"
                       FontWeight="SemiBold" HorizontalAlignment="Center"/>
            <TextBlock x:Name="CompactSecondaryReset" Text="—" Foreground="#8992A8" FontSize="10"
                       HorizontalAlignment="Center"/>
          </StackPanel>
          <!-- Give the balance the same numeric emphasis as the quota percentages. -->
          <StackPanel x:Name="CompactCreditsPanel" Grid.Row="2" Visibility="Collapsed" HorizontalAlignment="Center">
            <TextBlock x:Name="CompactCreditsText" Foreground="#91B8B0" FontSize="20" FontWeight="SemiBold" HorizontalAlignment="Center"/>
            <TextBlock x:Name="CompactCreditsCaption" Text="Credits" Foreground="#DDE3EF" FontSize="10" HorizontalAlignment="Center"/>
          </StackPanel>
        </Grid>
      </Border>

      <!-- Keep refresh available when the rest of the header no longer fits. -->
      <Button x:Name="CompactRefreshButton" Grid.RowSpan="5" Content="↻" ToolTip="Refresh now"
              HorizontalAlignment="Right" VerticalAlignment="Top" Width="20" Height="20" Visibility="Collapsed"
              Background="Transparent" Foreground="#AAB2C5" BorderThickness="0" FontSize="16" Cursor="Hand"/>
      <!-- Reveal missing window controls on hover without reserving permanent readout space. -->
      <Button x:Name="HoverPinButton" Grid.RowSpan="5" Content="◉" ToolTip="Always on top: on"
              HorizontalAlignment="Right" VerticalAlignment="Top" Width="20" Height="20" Visibility="Collapsed"
              Background="#F2161A23" Foreground="#78A7FF" BorderThickness="0" FontSize="16" Cursor="Hand"/>
      <Button x:Name="HoverMinimizeButton" Grid.RowSpan="5" Content="—" ToolTip="Minimize to tray"
              HorizontalAlignment="Right" VerticalAlignment="Top" Width="20" Height="20" Visibility="Collapsed"
              Background="#F2161A23" Foreground="#AAB2C5" BorderThickness="0" FontSize="16" Cursor="Hand"/>
      <Button x:Name="HoverRefreshButton" Grid.RowSpan="5" Content="↻" ToolTip="Refresh now"
              HorizontalAlignment="Right" VerticalAlignment="Top" Width="20" Height="20" Margin="0,0,24,0" Visibility="Collapsed"
              Background="#F2161A23" Foreground="#AAB2C5" BorderThickness="0" FontSize="16" Cursor="Hand"/>
      <Button x:Name="HoverCloseButton" Grid.RowSpan="5" Content="×" ToolTip="Close Codex Usage"
              HorizontalAlignment="Right" VerticalAlignment="Top" Width="20" Height="20" Visibility="Collapsed"
              Background="#F2161A23" Foreground="#F06A7A" BorderThickness="0" FontSize="18" Cursor="Hand"/>

    </Grid>
  </Border>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$outerBorder = $window.FindName('OuterBorder')
$dragArea = $window.FindName('DragArea')
$primaryArea = $window.FindName('PrimaryArea')
$secondaryArea = $window.FindName('SecondaryArea')
$ultraCompactPanel = $window.FindName('UltraCompactPanel')
$compactPrimaryPercent = $window.FindName('CompactPrimaryPercent')
$compactSecondaryPercent = $window.FindName('CompactSecondaryPercent')
# Bind the reset labels used after the header and progress bars disappear.
$compactPrimaryReset = $window.FindName('CompactPrimaryReset')
$compactSecondaryReset = $window.FindName('CompactSecondaryReset')
# Bind full-size and compact credit labels to the same account snapshot.
$creditsText = $window.FindName('CreditsText')
$compactCreditsText = $window.FindName('CompactCreditsText')
# Treat the balance and its caption as one responsive compact readout.
$compactCreditsPanel = $window.FindName('CompactCreditsPanel')
$compactCreditsCaption = $window.FindName('CompactCreditsCaption')
$creditsArea = $window.FindName('CreditsArea')
$creditsLabel = $window.FindName('CreditsLabel')
$compactRefreshButton = $window.FindName('CompactRefreshButton')
$hoverCloseButton = $window.FindName('HoverCloseButton')
$hoverRefreshButton = $window.FindName('HoverRefreshButton')
# Bind fallback window controls to the same actions as the full header.
$hoverPinButton = $window.FindName('HoverPinButton')
$hoverMinimizeButton = $window.FindName('HoverMinimizeButton')
$statusDot = $window.FindName('StatusDot')
$titleText = $window.FindName('TitleText')
$planText = $window.FindName('PlanText')
$primaryLabel = $window.FindName('PrimaryLabel')
$primaryPercent = $window.FindName('PrimaryPercent')
$primaryBar = $window.FindName('PrimaryBar')
$primaryReset = $window.FindName('PrimaryReset')
$secondaryLabel = $window.FindName('SecondaryLabel')
$secondaryPercent = $window.FindName('SecondaryPercent')
$secondaryBar = $window.FindName('SecondaryBar')
$secondaryReset = $window.FindName('SecondaryReset')
$footerArea = $window.FindName('FooterArea')
$updatedText = $window.FindName('UpdatedText')
$refreshButton = $window.FindName('RefreshButton')
$pinButton = $window.FindName('PinButton')
$minimizeButton = $window.FindName('MinimizeButton')
$closeButton = $window.FindName('CloseButton')
# Expose the installed version without adding width to the responsive header.
$window.Title = "Codex Usage v$script:WidgetVersion"
$titleText.ToolTip = $window.Title
$ultraCompactPanel.ToolTip = "$($window.Title) · Usage left · Top: 5-hour · Next: weekly · Double-click to expand"

function New-TrayUsageIcon {
    param(
        [double] $PrimaryRemaining = 0,
        [double] $SecondaryRemaining = 0
    )

    $bitmap = [System.Drawing.Bitmap]::new(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $backgroundBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 38, 44, 58))
        # Use the selected quota colors in the live notification icon.
        $blueBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($script:PrimaryColor))
        $purpleBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($script:SecondaryColor))
        # Prepare the optional credit stripe and a boundary visible even at zero quota.
        $creditBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($script:CreditColor))
        $outlinePen = [System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(235,245,247,251), 1)
        try {
            # Keep the dark square and outline visible even when both usage bars are empty.
            $graphics.FillRectangle($backgroundBrush, 2, 2, 28, 28)
            # Scale each remaining percentage to the tray bar's pixel width.
            $blueWidth = [int] [Math]::Round(28 * ([Math]::Min(100, [Math]::Max(0, $PrimaryRemaining)) / 100))
            $purpleWidth = [int] [Math]::Round(28 * ([Math]::Min(100, [Math]::Max(0, $SecondaryRemaining)) / 100))
            if ($blueWidth -gt 0) { $graphics.FillRectangle($blueBrush, 2, 4, $blueWidth, 6) }
            if ($purpleWidth -gt 0) { $graphics.FillRectangle($purpleBrush, 2, 14, $purpleWidth, 6) }
            # Show the credit identity accent only for enabled positive or unlimited credits.
            $creditValue = [decimal]0
            $positiveCredits = [decimal]::TryParse([string]$script:Usage.credits.balance, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$creditValue) -and $creditValue -gt 0
            if ($script:CreditDisplayMode -ne 'Off' -and ($positiveCredits -or $script:Usage.credits.unlimited -eq $true)) {
                $graphics.FillRectangle($creditBrush, 4, 25, 24, 3)
            }
            $graphics.DrawRectangle($outlinePen, 1, 1, 29, 29)
        }
        finally {
            $backgroundBrush.Dispose()
            $blueBrush.Dispose()
            $purpleBrush.Dispose()
            $creditBrush.Dispose()
            $outlinePen.Dispose()
        }

        $handle = $bitmap.GetHicon()
        try {
            return ([System.Drawing.Icon]::FromHandle($handle).Clone())
        }
        finally {
            [void] [CodexUsageWidget.NativeMethods]::DestroyIcon($handle)
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function New-WindowUsageIcon {
    $bitmap = [System.Drawing.Bitmap]::new(32, 32)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    try {
        $graphics.Clear([System.Drawing.Color]::Transparent)
        # Fill a square with the blue, purple, and muted-green identity colors.
        # Match the running application's icon to the selected quota colors.
        $blueBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($script:PrimaryColor))
        $purpleBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($script:SecondaryColor))
        $dividerBrush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(255, 24, 29, 40))
        $creditBrush = [System.Drawing.SolidBrush]::new([System.Drawing.ColorTranslator]::FromHtml($script:CreditColor))
        try {
            # Draw three straight-edged color bands with narrow dark separators.
            $graphics.FillRectangle($dividerBrush, 2, 2, 28, 28)
            $graphics.FillRectangle($blueBrush, 2, 2, 28, 8)
            $graphics.FillRectangle($purpleBrush, 2, 12, 28, 8)
            $graphics.FillRectangle($creditBrush, 2, 22, 28, 8)
        }
        finally {
            # Release drawing resources after creating the square artwork.
            $blueBrush.Dispose()
            $purpleBrush.Dispose()
            $dividerBrush.Dispose()
            $creditBrush.Dispose()
        }

        $handle = $bitmap.GetHicon()
        try {
            return ([System.Drawing.Icon]::FromHandle($handle).Clone())
        }
        finally {
            [void] [CodexUsageWidget.NativeMethods]::DestroyIcon($handle)
        }
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

function Get-LaunchAtSignIn {
    # Consider the setting enabled only when our own shortcut targets this folder's launcher.
    if (-not (Test-Path -LiteralPath $script:StartupShortcutPath -PathType Leaf)) { return $false }
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($script:StartupShortcutPath)
    try {
        $launcher = Join-Path $script:WidgetDirectory 'Start-CodexUsageWidget.ps1'
        return $shortcut.TargetPath -eq "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -and
            $shortcut.Arguments -eq ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -IfNotRunning' -f $launcher)
    } finally {
        # Release temporary COM references instead of retaining one for every tray-menu opening.
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
}

function Set-LaunchAtSignIn {
    param([bool] $Enabled)
    # Do not overwrite or remove a different shortcut that happens to use our chosen filename.
    if ((Test-Path -LiteralPath $script:StartupShortcutPath) -and -not (Get-LaunchAtSignIn)) {
        throw 'A different Codex Usage Widget startup shortcut already exists. Remove or rename that entry before changing this setting.'
    }
    if (-not $Enabled) {
        if (Test-Path -LiteralPath $script:StartupShortcutPath -PathType Leaf) { Remove-Item -LiteralPath $script:StartupShortcutPath }
        return
    }
    # Use the existing hidden bootstrap and silently retain any already-running widget.
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($script:StartupShortcutPath)
    try {
        $launcher = Join-Path $script:WidgetDirectory 'Start-CodexUsageWidget.ps1'
        $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $shortcut.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -IfNotRunning' -f $launcher
        $shortcut.WorkingDirectory = $script:WidgetDirectory
        $shortcut.IconLocation = (Join-Path $script:WidgetDirectory 'CodexUsage-Tricolor.ico') + ',0'
        $shortcut.Description = 'Start Codex Usage at sign-in without duplicating an existing widget.'
        $shortcut.Save()
    } finally {
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
    }
}

$trayMenu = [System.Windows.Forms.ContextMenuStrip]::new()
# Keep version information accessible even when the widget is minimized or tiny.
$versionItem = $trayMenu.Items.Add("Codex Usage v$script:WidgetVersion")
$versionItem.Enabled = $false
[void]$trayMenu.Items.Add([System.Windows.Forms.ToolStripSeparator]::new())
$trayOpenItem = $trayMenu.Items.Add('Open Codex Usage')
$trayRefreshItem = $trayMenu.Items.Add('Refresh')
# Open the four-tab settings window from the tray.
$settingsItem = $trayMenu.Items.Add('Settings...')
# Provide predictable window sizes without requiring manual dragging.
$sizeMenu = [System.Windows.Forms.ToolStripMenuItem]::new('Window size')
[void]$trayMenu.Items.Add($sizeMenu)
foreach ($preset in @(
    @{ Name = 'Mini'; Width = 72; Height = 72 },
    @{ Name = 'Small'; Width = 140; Height = 155 },
    # Preserve Medium's dimensions while reset details take priority over optional header text.
    @{ Name = 'Medium'; Width = 190; Height = 210 },
    @{ Name = 'Large / Default'; Width = 280; Height = 290 }
)) {
    # Store dimensions on each menu item instead of capturing the loop variable.
    # Layout-specific dimensions are applied when the preset is selected.
    $item = $sizeMenu.DropDownItems.Add($preset.Name)
    $item.Tag = $preset
    $item.Add_Click({
        param($sender,$eventArgs)
        Set-WidgetPreset $sender.Tag.Name
    })
}
# Place the current size in a monitor corner without resizing or changing topmost state.
$positionMenu = [System.Windows.Forms.ToolStripMenuItem]::new('Position')
[void]$trayMenu.Items.Add($positionMenu)
foreach ($corner in @('Top left', 'Top right', 'Bottom left', 'Bottom right')) {
    $item = $positionMenu.DropDownItems.Add($corner)
    $item.Tag = $corner
    $item.Add_Click({ param($sender, $eventArgs) Set-WidgetCorner -Corner $sender.Tag })
}
# Manage automatic sign-in launch through one per-user Startup shortcut.
$startupItem = $trayMenu.Items.Add('Launch at Windows sign-in')
$startupItem.Checked = Get-LaunchAtSignIn
$startupItem.Add_Click({
    try { Set-LaunchAtSignIn -Enabled (-not (Get-LaunchAtSignIn)) }
    catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to change startup setting') }
    $startupItem.Checked = Get-LaunchAtSignIn
})
$trayMenu.Add_Opening({ $startupItem.Checked = Get-LaunchAtSignIn })
$trayExitItem = $trayMenu.Items.Add('Exit')
$trayIcon = [System.Windows.Forms.NotifyIcon]::new()
$trayIcon.ContextMenuStrip = $trayMenu
$trayIcon.Text = 'Codex usage · connecting'
$script:TrayIconImage = New-TrayUsageIcon
$trayIcon.Icon = $script:TrayIconImage
$trayIcon.Visible = $true
$script:WindowIconImage = New-WindowUsageIcon
$windowIcon = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
    $script:WindowIconImage.Handle,
    [System.Windows.Int32Rect]::Empty,
    [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
)
$windowIcon.Freeze()
$window.Icon = $windowIcon

function Show-Widget {
    $window.Show()
    $window.WindowState = [System.Windows.WindowState]::Normal
    # Restore the desktop widget while retaining its tray-only taskbar presence.
    $window.ShowInTaskbar = $false
    [void] $window.Activate()
}

function Set-WidgetCorner {
    param([ValidateSet('Top left','Top right','Bottom left','Bottom right')][string] $Corner)
    # Restore before measuring the widget's normal bounds on its current monitor.
    Show-Widget
    $handle = [Windows.Interop.WindowInteropHelper]::new($window).Handle
    $bounds = [CodexUsageWidget.NativeMethods+Rect]::new()
    $info = [CodexUsageWidget.NativeMethods+MonitorInfo]::new()
    $info.Size = [Runtime.InteropServices.Marshal]::SizeOf($info)
    $monitor = [CodexUsageWidget.NativeMethods]::MonitorFromWindow($handle, 2)
    if (-not [CodexUsageWidget.NativeMethods]::GetWindowRect($handle, [ref]$bounds) -or
        -not [CodexUsageWidget.NativeMethods]::GetMonitorInfo($monitor, [ref]$info)) { return }
    # Use the taskbar-excluding work area with a 2-logical-pixel inset scaled for this display.
    $gap = [int][Math]::Round(2 * [Windows.Media.VisualTreeHelper]::GetDpi($window).DpiScaleX)
    $x = if ($Corner.EndsWith('right')) { $info.Work.Right - ($bounds.Right - $bounds.Left) - $gap } else { $info.Work.Left + $gap }
    $y = if ($Corner.StartsWith('Bottom')) { $info.Work.Bottom - ($bounds.Bottom - $bounds.Top) - $gap } else { $info.Work.Top + $gap }
    # Keep oversized windows reachable without changing their chosen dimensions.
    $x = [Math]::Max($info.Work.Left, $x)
    $y = [Math]::Max($info.Work.Top, $y)
    if ([CodexUsageWidget.NativeMethods]::SetWindowPos($handle, [IntPtr]::Zero, $x, $y, 0, 0, 0x15)) { Save-WidgetState }
}

function Start-WidgetDrag {
    # Capture the original cursor offset instead of handing dragging to Windows Snap.
    if ($window.WindowState -ne [Windows.WindowState]::Normal -or $script:DragOrigin) { return }
    $point = [CodexUsageWidget.NativeMethods+Point]::new()
    $bounds = [CodexUsageWidget.NativeMethods+Rect]::new()
    $handle = [Windows.Interop.WindowInteropHelper]::new($window).Handle
    if (-not [CodexUsageWidget.NativeMethods]::GetCursorPos([ref]$point) -or
        -not [CodexUsageWidget.NativeMethods]::GetWindowRect($handle, [ref]$bounds)) { return }
    if ($outerBorder.CaptureMouse()) {
        $script:DragOrigin = @{ Handle=$handle; X=$point.X; Y=$point.Y; Left=$bounds.Left; Top=$bounds.Top }
    }
}

function Update-WidgetDrag {
    # Preserve dimensions and topmost state while following the captured pointer.
    if (-not $script:DragOrigin) { return }
    $point = [CodexUsageWidget.NativeMethods+Point]::new()
    if ([CodexUsageWidget.NativeMethods]::GetCursorPos([ref]$point)) {
        $x = $script:DragOrigin.Left + $point.X - $script:DragOrigin.X
        $y = $script:DragOrigin.Top + $point.Y - $script:DragOrigin.Y
        [void][CodexUsageWidget.NativeMethods]::SetWindowPos($script:DragOrigin.Handle, [IntPtr]::Zero, $x, $y, 0, 0, 0x15)
    }
}

function Update-QuotaColors {
    # Color credit totals independently while keeping their labels white.
    $creditsText.Foreground = $script:CreditColor
    $compactCreditsText.Foreground = $script:CreditColor
    # Apply each color consistently to percentages and remaining-quota bars.
    foreach ($control in @($primaryPercent, $compactPrimaryPercent, $primaryBar)) {
        $control.Foreground = $script:PrimaryColor
    }
    foreach ($control in @($secondaryPercent, $compactSecondaryPercent, $secondaryBar)) {
        $control.Foreground = $script:SecondaryColor
    }
    # Repaint the notification icon using the current usage snapshot.
    Update-TrayIcon
    # Replace the running application's icon and release the previous image.
    $replacement = New-WindowUsageIcon
    $previous = $script:WindowIconImage
    $script:WindowIconImage = $replacement
    $source = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($replacement.Handle,
        [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
    $source.Freeze()
    $window.Icon = $source
    if ($previous) { $previous.Dispose() }
}





function Get-PrimaryResetNotification {
    # Disabling the option clears its baseline so enabling it later cannot send an old reset.
    if (-not $script:NotifyPrimaryReset) { $script:AlertStates.Remove('primaryReset'); return $null }
    $quota = $script:Usage.primary
    if (-not $quota -or $null -eq $quota.usedPercent) { return $null }
    $used = [Math]::Min(100, [Math]::Max(0, [double]$quota.usedPercent))
    $resetAt = [long]$quota.resetsAt
    $previous = $script:AlertStates['primaryReset']
    $message = $null
    # Notify only after the observed deadline AND a fresh response confirming recovered quota.
    # A timestamp moving, countdown reaching zero, or first launch alone is not a reset signal.
    if ($previous -and -not $previous.Notified -and
        [DateTimeOffset]::Now.ToUnixTimeSeconds() -ge $previous.ResetsAt -and $used -lt $previous.UsedPercent) {
        # A five-hour recovery is only useful when the same snapshot confirms weekly quota remains.
        $weekly = $script:Usage.secondary
        if ($weekly -and $null -ne $weekly.usedPercent -and [double]$weekly.usedPercent -ge 0 -and [double]$weekly.usedPercent -lt 100) {
            $message = '5-hour window reset: {0:N0}% left. Weekly limits still apply.' -f (100 - $used)
        }
        # Consume this reset even when suppressed; do not send it later as a stale recovery notice.
        $previous.Notified = $true
    }
    # A fully recovered inactive window may omit its next deadline; retain any valid prior cycle.
    if ($resetAt -le 0) {
        if ($previous) { $previous.UsedPercent = $used }
        return $message
    }
    # A later window starts a new notification cycle; otherwise retain the sent flag.
    $notified = $previous -and $previous.Notified -and $resetAt -le $previous.ResetsAt
    $script:AlertStates['primaryReset'] = @{ ResetsAt=$resetAt; UsedPercent=$used; Notified=[bool]$notified }
    return $message
}

function Show-UsageWarnings {
    param([string] $AccountName)
    # Check only successful account snapshots; missing quota data cannot trigger alerts.
    if (-not $script:Usage) { return }
    $messages = @()
    # Merge reset and low-quota messages into one balloon so simultaneous events cannot overwrite it.
    $resetMessage = Get-PrimaryResetNotification
    if ($resetMessage) { $messages += $resetMessage }
    $hasLowWarning = $false
    foreach ($setting in @(
        @{ Key = 'primary'; Label = '5-hour'; Threshold = $script:PrimaryAlertThreshold },
        @{ Key = 'secondary'; Label = 'Weekly'; Threshold = $script:SecondaryAlertThreshold }
    )) {
        # Zero disables this quota's alert and clears its previous notification state.
        if ($setting.Threshold -eq 0) {
            $script:AlertStates.Remove($setting.Key)
            continue
        }
        $quota = $script:Usage.($setting.Key)
        if (-not $quota -or $null -eq $quota.usedPercent) { continue }
        # Convert server usage to the remaining percentage used by the widget.
        $remaining = [Math]::Min(100, [Math]::Max(0, 100 - [double]$quota.usedPercent))
        $previous = $script:AlertStates[$setting.Key]
        # Reset timestamps can move while quota remains exhausted; they must not rearm alerts.
        if (-not $previous) {
            $previous = @{ Notified = $false }
            $script:AlertStates[$setting.Key] = $previous
        }
        # Rearm only after quota recovers to the threshold or above.
        if ($remaining -ge $setting.Threshold) {
            $previous.Notified = $false
        }
        elseif (-not $previous.Notified) {
            # Collect simultaneous warnings into one popup so neither is overwritten.
            $messages += ('{0}: {1:N0}% left (below {2}%).' -f $setting.Label, $remaining, $setting.Threshold)
            $hasLowWarning = $true
            $previous.Notified = $true
        }
    }
    # Let Windows display its notification-area popup subject to notification settings.
    if ($messages.Count -gt 0) {
        # Save the sent state before showing the notification so restarts cannot repeat it.
        Save-WarningState
        $title = if ($resetMessage -and $hasLowWarning) { 'Codex usage update' } elseif ($resetMessage) { '5-hour window reset' } else { 'Codex usage running low' }
        $icon = if ($hasLowWarning) { [System.Windows.Forms.ToolTipIcon]::Warning } else { [System.Windows.Forms.ToolTipIcon]::Info }
        # Identify imported-account alerts without changing the local tray readings.
        if ($AccountName) { $title = $AccountName + ' - ' + $title }
        $trayIcon.ShowBalloonTip(8000, $title, ($messages -join [Environment]::NewLine), $icon)
    }
    else {
        # Persist recovery and disabled alerts too, without changing refresh preferences.
        Save-WarningState
    }
}

function Save-WarningState {
    # Shared alerts persist their own source-aware history before a popup is displayed.
    if ($script:ProcessingSharedWarnings) { Save-SharedWarnings; return }
    # Store only changes to keep polling from producing needless disk writes.
    if (-not $script:AlertStatePath) { return }
    $json = $script:AlertStates | ConvertTo-Json -Compress -Depth 4
    if ($json -ne $script:LastWarningState) {
        $json | Set-Content -LiteralPath $script:AlertStatePath -Encoding utf8
        $script:LastWarningState = $json
    }
}





function Set-RefreshInterval {
    param([int] $Minutes)
    if ($Minutes -notin @(0, 1, 5, 15, 30)) { return }
    $script:RefreshIntervalMinutes = $Minutes


    if ($script:RefreshTimer) {
        $script:RefreshTimer.Stop()
        if ($Minutes -gt 0) {
            $script:RefreshTimer.Interval = [TimeSpan]::FromMinutes($Minutes)
            $script:RefreshTimer.Start()
        }
    }
    # Save the chosen interval now so a restart cannot restore an older setting.
    Save-WidgetState
}

function Save-WidgetState {
    # Startup assigns settings before the window exists on screen; save only live bounds.
    if (-not $window.IsLoaded) { return }
    $bounds = $window.RestoreBounds
    # Use explicit current dimensions for preset changes before the next layout pass.
    @{
        left = $bounds.Left
        top = $bounds.Top
        width = $window.Width
        height = $window.Height
        topmost = $window.Topmost
        refreshIntervalMinutes = $script:RefreshIntervalMinutes
        primaryColor = $script:PrimaryColor
        secondaryColor = $script:SecondaryColor
        creditColor = $script:CreditColor
        primaryAlertThreshold = $script:PrimaryAlertThreshold
        secondaryAlertThreshold = $script:SecondaryAlertThreshold
        notifyPrimaryReset = $script:NotifyPrimaryReset
        primaryResetHours = $script:PrimaryResetHours
        showWeeklyResetDate = $script:ShowWeeklyResetDate
        creditDisplayMode = $script:CreditDisplayMode
        # Keep file connections and aliases on this computer, outside the synchronized project.
        sharedEnabled = $script:SharedEnabled
        sharedCreditDisplayMode = $script:SharedCreditDisplayMode
        sharedPrimaryResetHours = $script:SharedPrimaryResetHours
        sharedShowWeeklyResetDate = $script:SharedShowWeeklyResetDate
        sharedPrimaryAlertThreshold = $script:SharedPrimaryAlertThreshold
        sharedSecondaryAlertThreshold = $script:SharedSecondaryAlertThreshold
        sharedNotifyPrimaryReset = $script:SharedNotifyPrimaryReset
        writeUsageEnabled = $script:WriteUsageEnabled
        readUsageEnabled = $script:ReadUsageEnabled
        usageOutputPath = $script:UsageOutputPath
        usageInputPath = $script:UsageInputPath
        localDisplayName = $script:LocalDisplayName
        sharingSourceId = $script:SharingSourceId
        writeIntervalMinutes = $script:WriteIntervalMinutes
        readIntervalMinutes = $script:ReadIntervalMinutes
        accountLayout = $script:AccountLayout
        selectedAccount = $script:SelectedAccount
        localScheme = $script:LocalScheme
        remoteScheme = $script:RemoteScheme
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $script:StatePath -Encoding utf8
}

function Update-PinDisplay {
    if ($window.Topmost) {
        $pinButton.Content = '◉'
        $pinButton.Foreground = '#78A7FF'
        $pinButton.ToolTip = 'Always on top: on'
    }
    else {
        $pinButton.Content = '○'
        $pinButton.Foreground = '#AAB2C5'
        $pinButton.ToolTip = 'Always on top: off'
    }
    # Keep the hover button's symbol, color, and tooltip synchronized with the header.
    $hoverPinButton.Content = $pinButton.Content
    $hoverPinButton.Foreground = $pinButton.Foreground
    $hoverPinButton.ToolTip = $pinButton.ToolTip
}

function Update-HoverControls {
    param([bool] $IsPointerOver = $outerBorder.IsMouseOver)
    # Account cards share the parent toolbar and must not create competing hover buttons.
    if ($script:RenderingAccountCard) {
        foreach ($control in @($compactRefreshButton,$hoverCloseButton,$hoverPinButton,$hoverMinimizeButton,$hoverRefreshButton)) { $control.Visibility = 'Collapsed' }
        return
    }
    # Reveal missing header controls only while the pointer is over the widget.
    $showClose = $IsPointerOver -and $dragArea.Visibility -ne 'Visible'
    $hoverCloseButton.Visibility = if ($showClose) { 'Visible' } else { 'Collapsed' }
    $hoverPinButton.Visibility = $hoverCloseButton.Visibility
    $hoverMinimizeButton.Visibility = $hoverCloseButton.Visibility
    # Add refresh to the hover overlay only if the permanent compact button is absent.
    $hoverRefreshButton.Visibility = if ($showClose -and $compactRefreshButton.Visibility -ne 'Visible') { 'Visible' } else { 'Collapsed' }
    # Use two rows in the smallest badge so all four 20px buttons remain inside its bounds.
    $twoRows = $window.ActualWidth -lt 110
    $hoverMinimizeButton.Margin = [System.Windows.Thickness]::new(0,0,24,0)
    $hoverPinButton.Margin = [System.Windows.Thickness]::new(0,$(if ($twoRows) { 24 } else { 0 }),$(if ($twoRows) { 0 } else { 48 }),0)
    $refreshMargin = [System.Windows.Thickness]::new(0,$(if ($twoRows) { 24 } else { 0 }),$(if ($twoRows) { 24 } else { 72 }),0)
    $hoverRefreshButton.Margin = $refreshMargin
    # Reposition the existing compact refresh instead of drawing a duplicate on hover.
    $compactRefreshButton.Margin = if ($showClose) { $refreshMargin } else { [System.Windows.Thickness]::new(0) }
}

function Update-ResponsiveLayout {
    # Measure labeled rows before choosing a layout, rather than guessing a cutoff.
    $measureSize = [System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity)
    # Restore visibility before measurement so resizing upward is deterministic.
    foreach ($control in @($primaryArea, $secondaryArea, $creditsArea, $primaryReset, $secondaryReset)) { $control.Visibility = 'Visible' }
    # Consume the center gap before shortening labels or reducing numeric type size.
    foreach ($density in @('Full','ShortLabels','SmallType')) {
        $primaryLabel.Text = if ($density -eq 'Full') { '5-hour window' } else { '5-hour' }
        $secondaryLabel.Text = if ($density -eq 'Full') { 'Weekly window' } else { 'Weekly' }
        $primaryPercent.FontSize = if ($density -eq 'SmallType') { 15 } else { 18 }
        $secondaryPercent.FontSize = $primaryPercent.FontSize
        $creditsText.FontSize = $primaryPercent.FontSize
        # Match each white label to its value before measuring the row's required width.
        $primaryLabel.FontSize = $primaryPercent.FontSize
        $secondaryLabel.FontSize = $secondaryPercent.FontSize
        $creditsLabel.FontSize = $creditsText.FontSize
        foreach ($control in @($primaryLabel, $secondaryLabel, $primaryPercent, $secondaryPercent, $creditsLabel, $creditsText)) { $control.Measure($measureSize) }
        # Reserve only the widest label, shared value column, and a small readable gap.
        $labelWidth = [Math]::Max($primaryLabel.DesiredSize.Width, $secondaryLabel.DesiredSize.Width)
        $valueWidth = [Math]::Max($primaryPercent.DesiredSize.Width, $secondaryPercent.DesiredSize.Width)
        if ($script:CreditsVisible) { $labelWidth = [Math]::Max($labelWidth, $creditsLabel.DesiredSize.Width); $valueWidth = [Math]::Max($valueWidth, $creditsText.DesiredSize.Width) }
        $requiredWidth = $labelWidth + $valueWidth + 8
        if ($requiredWidth + 14 -le $window.ActualWidth) { break }
    }
    # Wrap reset details at the current width and retain them before considering bars.
    Update-ResetLabels
    # Reserve the actual reset text height, the existing 27px value row, and 5px row margins.
    $resetHeight = [Math]::Ceiling([Math]::Max($primaryReset.DesiredSize.Height, $secondaryReset.DesiredSize.Height))
    $creditHeight = if ($script:CreditsVisible) { 32 } else { 0 }
    $labeledHeight = 2 * (27 + 5 + $resetHeight) + $creditHeight
    $ultraCompact = $window.ActualWidth -lt ($requiredWidth + 14) -or $window.ActualHeight -lt ($labeledHeight + 14)
    # Hide bars only after the essential labeled rows consume the available height.
    $showBars = $window.ActualHeight -ge ($labeledHeight + 24 + 20 + 14)
    $coreHeight = $labeledHeight + $(if ($showBars) { 24 } else { 0 })
    foreach ($area in @($primaryArea, $secondaryArea)) { $area.RowDefinitions[1].Height = [System.Windows.GridLength]::new($(if ($showBars) { 12 } else { 0 })) }
    $primaryBar.Visibility = if ($showBars) { 'Visible' } else { 'Collapsed' }
    $secondaryBar.Visibility = $primaryBar.Visibility
    $ultraCompactPanel.Visibility = if ($ultraCompact) { 'Visible' } else { 'Collapsed' }
    $primaryArea.Visibility = if ($ultraCompact) { 'Collapsed' } else { 'Visible' }
    $secondaryArea.Visibility = if ($ultraCompact) { 'Collapsed' } else { 'Visible' }
    $creditsArea.Visibility = if ($script:CreditsVisible -and -not $ultraCompact) { 'Visible' } else { 'Collapsed' }
    # Reset reservations before calculating the refresh-only layout.
    $primaryArea.Margin = [System.Windows.Thickness]::new(0,5,0,0)
    $dragArea.Height = [double]::NaN
    $ultraCompactPanel.Margin = [System.Windows.Thickness]::new(0)
    $compactRefreshButton.Visibility = 'Collapsed'

    if ($ultraCompact) {
        # Keep only the numeric readouts and reset details that physically fit.
        $dragArea.Visibility = 'Collapsed'
        $footerArea.Visibility = 'Collapsed'
        $outerBorder.Padding = [System.Windows.Thickness]::new(6)
        # Fit three numeric rows at minimum size when credits are enabled.
        $numberSize = if ($script:CreditsVisible -and $window.ActualHeight -lt 75) { 12 } elseif ($window.ActualWidth -lt 105 -or $window.ActualHeight -lt 75) { 15 } else { 20 }
        $compactPrimaryPercent.FontSize = $numberSize
        $compactSecondaryPercent.FontSize = $numberSize
        $compactCreditsText.FontSize = $numberSize
        # Fit the numeric rows themselves using measured font heights, including 72x58.
        $numericLabels = @($compactPrimaryPercent, $compactSecondaryPercent)
        if ($script:CreditsVisible) { $numericLabels += $compactCreditsText }
        while ($numberSize -ge 10) {
            $numericHeight = 0
            $numericWidth = 0
            foreach ($label in $numericLabels) {
                $label.FontSize = $numberSize
                $label.Measure($measureSize)
                $numericHeight += $label.DesiredSize.Height
                $numericWidth = [Math]::Max($numericWidth, $label.DesiredSize.Width)
            }
            if (($numericHeight -le ($window.ActualHeight - 14) -and $numericWidth -le ($window.ActualWidth - 14)) -or $numberSize -eq 10) { break }
            $numberSize--
        }
        # Reserve the reset countdowns before deciding whether refresh has spare space.
        $refreshHeight = 0
        # Measure actual text so countdowns remain visible for as long as they fit.
        $compactPrimaryReset.Visibility = 'Visible'
        $compactSecondaryReset.Visibility = 'Visible'
        $measureSize = [System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity)
        foreach ($label in @($compactPrimaryPercent, $compactSecondaryPercent, $compactPrimaryReset, $compactSecondaryReset)) {
            $label.Measure($measureSize)
        }
        # Reserve padding and border space around two equally sized compact rows.
        $rowHeight = [Math]::Max($compactPrimaryPercent.DesiredSize.Height + $compactPrimaryReset.DesiredSize.Height,
                               $compactSecondaryPercent.DesiredSize.Height + $compactSecondaryReset.DesiredSize.Height)
        $resetWidth = [Math]::Max($compactPrimaryReset.DesiredSize.Width, $compactSecondaryReset.DesiredSize.Width)
        # Reserve space for visible credits rather than silently dropping the balance.
        $compactCreditsPanel.Visibility = if ($script:CreditsVisible) { 'Visible' } else { 'Collapsed' }
        $compactCreditsCaption.Visibility = 'Visible'
        $compactCreditsPanel.Measure($measureSize)
        $creditHeight = if ($script:CreditsVisible) { $compactCreditsPanel.DesiredSize.Height } else { 0 }
        # Remove the credit caption before hiding reset countdowns at tight sizes.
        if ($window.ActualHeight -lt (2 * $rowHeight + $creditHeight + 14 + $refreshHeight)) {
            $compactCreditsCaption.Visibility = 'Collapsed'
            $compactCreditsPanel.Measure($measureSize)
            $creditHeight = if ($script:CreditsVisible) { $compactCreditsPanel.DesiredSize.Height } else { 0 }
        }
        $showResets = ($window.ActualHeight -ge (2 * $rowHeight + $creditHeight + 14 + $refreshHeight)) -and ($window.ActualWidth -ge ($resetWidth + 14))
        $compactPrimaryReset.Visibility = if ($showResets) { 'Visible' } else { 'Collapsed' }
        $compactSecondaryReset.Visibility = if ($showResets) { 'Visible' } else { 'Collapsed' }
        # Show a permanent refresh button only after both countdowns and the credit row fit.
        $refreshHeight = if (-not $script:RenderingAccountCard -and $showResets -and
            $window.ActualHeight -ge (2 * $rowHeight + $creditHeight + 14 + 20)) { 20 } else { 0 }
        $compactRefreshButton.Visibility = if ($refreshHeight) { 'Visible' } else { 'Collapsed' }
        $ultraCompactPanel.Margin = [System.Windows.Thickness]::new(0,$refreshHeight,0,0)
        # Refresh hover controls after resizing without moving the numeric layout.
        Update-HoverControls
        if (-not $script:RenderingAccountCard) { Update-AccountViews }
        return
    }

    # Account cards use the shared parent toolbar, leaving their space to usage and reset details.
    if ($script:RenderingAccountCard) {
        $dragArea.Visibility = 'Collapsed'
        $footerArea.Visibility = 'Collapsed'
        $outerBorder.Padding = [Windows.Thickness]::new(6)
        Update-HoverControls
        return
    }
    # Measure header controls separately, adding them only after the data rows fit.
    # Fit the full title before abbreviating it; the plan line has its own fit check.
    $planText.Visibility = 'Collapsed'
    $titleText.Text = 'CODEX USAGE'
    $dragArea.Visibility = 'Visible'
    # Measure the title and fixed controls directly; a star column can retain old layout width.
    $titleText.Measure($measureSize)
    $headerWidth = $titleText.DesiredSize.Width + 18 + 96
    if ($headerWidth + 14 -gt $window.ActualWidth) {
        $titleText.Text = 'CODEX'
        $titleText.Measure($measureSize)
        $headerWidth = $titleText.DesiredSize.Width + 18 + 96
    }
    $planText.Visibility = 'Visible'
    $planText.Measure($measureSize)
    if ($planText.DesiredSize.Width + 14 -gt $window.ActualWidth -or $window.ActualHeight -lt ($coreHeight + 24 + $planText.DesiredSize.Height + 14)) { $planText.Visibility = 'Collapsed' }
    if ($planText.Visibility -eq 'Visible') { $headerWidth = [Math]::Max($headerWidth, $planText.DesiredSize.Width) }
    $dragArea.Measure($measureSize)
    $headerHeight = [Math]::Ceiling($dragArea.DesiredSize.Height)
    $showHeader = $window.ActualWidth -ge ($headerWidth + 14) -and $window.ActualHeight -ge ($coreHeight + $headerHeight + 14)
    $dragArea.Visibility = if ($showHeader) { 'Visible' } else { 'Collapsed' }
    $usedHeight = $coreHeight + $(if ($showHeader) { $headerHeight } else { 0 })
    # Reserve a small top strip for refresh after hiding the full header.
    if (-not $showHeader -and $window.ActualHeight -ge ($coreHeight + 34)) {
        $compactRefreshButton.Visibility = 'Visible'
        # Reserve refresh space in its own header row so neither quota row gets squeezed.
        $dragArea.Visibility = 'Hidden'
        $dragArea.Height = 20
        $usedHeight += 20
    }
    # Add the footer and generous padding only when they leave the rows unclipped.
    $updatedText.Measure($measureSize)
    $footerWidth = $updatedText.DesiredSize.Width
    $showFooter = $showHeader -and $window.ActualWidth -ge ($footerWidth + 14) -and $window.ActualHeight -ge ($usedHeight + 24 + 14)
    $footerArea.Visibility = if ($showFooter) { 'Visible' } else { 'Collapsed' }
    $usedHeight += $(if ($showFooter) { 24 } else { 0 })
    # Cap padding at 10px so the narrower full view does not waste a large center gap.
    $padding = if ($window.ActualHeight -ge ($usedHeight + 22) -and $window.ActualWidth -ge ([Math]::Max($requiredWidth, $headerWidth) + 22)) { 10 } else { 6 }
    $outerBorder.Padding = [System.Windows.Thickness]::new($padding)
    Update-HoverControls
    Update-AccountViews
}

function Update-TrayIcon {
    # Convert consumed quota to usage left, keeping missing-window bars empty.
    $primaryKnown = $null -ne $script:Usage.primary.usedPercent
    $secondaryKnown = $null -ne $script:Usage.secondary.usedPercent
    $primaryValue = if ($primaryKnown) { [Math]::Min(100, [Math]::Max(0, 100 - [double] $script:Usage.primary.usedPercent)) } else { 0 }
    $secondaryValue = if ($secondaryKnown) { [Math]::Min(100, [Math]::Max(0, 100 - [double] $script:Usage.secondary.usedPercent)) } else { 0 }
    # Draw both tray bars with the remaining percentages.
    $replacement = New-TrayUsageIcon -PrimaryRemaining $primaryValue -SecondaryRemaining $secondaryValue
    # Replace the icon and release its previous image.
    $previous = $script:TrayIconImage
    $script:TrayIconImage = $replacement
    $trayIcon.Icon = $replacement
    if ($previous) { $previous.Dispose() }
    # Label the tray percentages as quota left.
    # Distinguish unknown or stale readings from genuine zero quota.
    $primaryLabel = if ($primaryKnown) { '{0:N0}% left' -f $primaryValue } else { 'unavailable' }
    $secondaryLabel = if ($secondaryKnown) { '{0:N0}% left' -f $secondaryValue } else { 'unavailable' }
    # Include available credits while respecting the same display setting as the widget.
    $creditLabel = Get-CreditLabel
    $showCreditText = $script:CreditDisplayMode -ne 'Off' -and $creditLabel -notmatch 'unavailable|none|^Credits: 0$'
    $tooltip = "Codex · 5h $primaryLabel · Wk $secondaryLabel" + $(if ($showCreditText) { ' · ' + $creditLabel } else { '' })
    if ($script:RefreshError) { $tooltip = 'Stale · ' + $tooltip }
    $trayIcon.Text = $tooltip.Substring(0,[Math]::Min(127,$tooltip.Length))
}

function Format-ResetCountdown {
    param([long] $UnixSeconds, [switch] $Compact, [switch] $CountdownOnly)
    # Use short placeholders when the badge has little room.
    if ($UnixSeconds -le 0) { if ($Compact) { return '—' }; return 'Reset time unavailable' }
    $reset = [DateTimeOffset]::FromUnixTimeSeconds($UnixSeconds).ToLocalTime()
    $remaining = $reset - [DateTimeOffset]::Now
    if ($remaining.TotalSeconds -le 0) { if ($Compact) { return 'Resetting' }; return 'Resetting now…' }

    # Keep compact countdowns to two units so they fit beneath the percentages.
    if ($Compact -and $remaining.TotalDays -ge 1) {
        return ('{0}d {1}h' -f [Math]::Floor($remaining.TotalDays), $remaining.Hours)
    }

    if ($remaining.TotalDays -ge 1) {
        $countdown = '{0}d {1}h {2}m' -f [Math]::Floor($remaining.TotalDays), $remaining.Hours, $remaining.Minutes
    }
    elseif ($remaining.TotalHours -ge 1) {
        $countdown = '{0}h {1}m' -f [Math]::Floor($remaining.TotalHours), $remaining.Minutes
    }
    else {
        $countdown = '{0}m {1}s' -f [Math]::Max(0, $remaining.Minutes), [Math]::Max(0, $remaining.Seconds)
    }
    # Omit the explanatory prefix and clock time only for the compact badge.
    if ($Compact) { return $countdown }
    # Keep the countdown separate when the responsive label supplies its own reset details.
    if ($CountdownOnly) { return "Resets in $countdown" }
    return "Resets in $countdown · $($reset.ToString('ddd h:mm tt'))"
}

function Get-ResetDetails {
    param($Quota, [switch] $Weekly, [switch] $NextOnly, [DateTimeOffset] $Now = [DateTimeOffset]::Now)
    # Do not project unknown, expired, or malformed server reset timestamps.
    $stamp = [long]0
    if (-not $Quota -or -not [long]::TryParse([string]$Quota.resetsAt, [ref]$stamp) -or $stamp -le 0) { return '' }
    try { $reset = [DateTimeOffset]::FromUnixTimeSeconds($stamp) }
    catch { return '' }
    if ($reset -le $Now) { return '' }
    $localReset = $reset.ToLocalTime()
    if ($Weekly) {
        # Use the account's actual weekly date; never extrapolate a weekly period.
        if (-not $script:ShowWeeklyResetDate) { return '' }
        return $localReset.ToString('ddd, MMM d') + ' at ' + $localReset.ToString('h:mm tt').Replace(' ', [string][char]0xA0)
    }
    # Zero independently disables the five-hour clock/schedule line.
    if ($script:PrimaryResetHours -le 0) { return '' }
    # Keep each clock time together when wrapping, including its AM/PM suffix.
    $text = 'at ' + $localReset.ToString('h:mm tt').Replace(' ', [string][char]0xA0)
    if ($NextOnly) { return $text }
    # Count hours ahead from now, always retaining the reported next reset even beyond that range.
    $end = $Now.AddHours($script:PrimaryResetHours)
    $period = [double]0
    if (-not [double]::TryParse([string]$Quota.windowDurationMins, [ref]$period) -or
        [double]::IsNaN($period) -or [double]::IsInfinity($period) -or $period -le 0) { $period = 300 }
    # Later resets assume immediate reuse; advance elapsed UTC time so daylight-saving shifts are correct.
    $estimated = [Collections.Generic.List[string]]::new()
    $future = $reset.AddMinutes($period)
    for ($index = 0; $future -le $end -and $index -lt 34; $index++) {
        $localFuture = $future.ToLocalTime()
        # Keep the visible schedule to clock times; estimation context stays in the tooltip.
        $estimated.Add($localFuture.ToString('h:mm tt').Replace(' ', [string][char]0xA0))
        $future = $future.AddMinutes($period)
    }
    if ($estimated.Count) { $text += ', ' + ($estimated -join ', ') }
    return $text
}

function Update-ResetLabels {
    # Keep enough padding for either responsive border setting and measure real wrapped text.
    $availableWidth = [Math]::Max(1, $window.ActualWidth - 22)
    $bounded = [Windows.Size]::new($availableWidth, [double]::PositiveInfinity)
    $unbounded = [Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity)
    # Preserve full schedules first, then actual next resets, then countdowns before the numeric badge.
    foreach ($detailLevel in @('Full', 'Next', 'Countdown')) {
        foreach ($entry in @(
            @{ Control = $primaryReset; Quota = $script:Usage.primary; Weekly = $false; Missing = 'No 5-hour window returned' },
            @{ Control = $secondaryReset; Quota = $script:Usage.secondary; Weekly = $true; Missing = 'No weekly window returned' }
        )) {
            $control = $entry.Control
            $quota = $entry.Quota
            $countdown = if ($quota -and $null -ne $quota.usedPercent) { Format-ResetCountdown -UnixSeconds ([long]$quota.resetsAt) -CountdownOnly } else { $entry.Missing }
            # Shorten only the countdown when necessary; the reset details get their own wrapped space.
            $control.MaxWidth = [double]::PositiveInfinity
            $control.Text = $countdown
            $control.Measure($unbounded)
            if ($quota -and $control.DesiredSize.Width -gt $availableWidth) {
                $countdown = 'Resets in ' + (Format-ResetCountdown -UnixSeconds ([long]$quota.resetsAt) -Compact)
            }
            $details = if ($detailLevel -ne 'Countdown' -and $quota -and $null -ne $quota.usedPercent) {
                Get-ResetDetails -Quota $quota -Weekly:$entry.Weekly -NextOnly:($detailLevel -eq 'Next')
            } else { '' }
            # Put time/date beside the countdown only when the entire line fits.
            $control.Text = if ($details) { $countdown + ' · ' + $details } else { $countdown }
            $control.Measure($unbounded)
            if ($details -and $control.DesiredSize.Width -gt $availableWidth) { $control.Text = $countdown + [Environment]::NewLine + $details }
            $control.MaxWidth = $availableWidth
            $control.Measure($bounded)
            # Preserve the complete schedule on hover even after shrinking its visible representation.
            $fullDetails = if ($quota -and $null -ne $quota.usedPercent) { Get-ResetDetails -Quota $quota -Weekly:$entry.Weekly } else { '' }
            $control.ToolTip = $countdown + $(if ($fullDetails) { [Environment]::NewLine + $fullDetails } else { '' })
            # Explain estimates on hover without repeating labels in the visible clock list.
            if ($fullDetails -and -not $entry.Weekly) {
                $control.ToolTip += [Environment]::NewLine + 'First time: reported next reset. Later times: estimates assuming immediate reuse.'
            }
        }
        # Equal star rows must both fit the taller reset block before adding bars or header controls.
        $resetHeight = [Math]::Ceiling([Math]::Max($primaryReset.DesiredSize.Height, $secondaryReset.DesiredSize.Height))
        $creditHeight = if ($script:CreditsVisible) { 32 } else { 0 }
        if (2 * (27 + 5 + $resetHeight) + $creditHeight + 14 -le $window.ActualHeight) { break }
    }
}

function Update-Display {
    # Wait for the first account snapshot before updating the display.
    if (-not $script:Usage) { Update-ResponsiveLayout; Update-RefreshStatus; return }
    # Read both quota windows from the unchanged usage response.
    $primary = $script:Usage.primary
    $secondary = $script:Usage.secondary
    # Show available credits by default, independently of remaining subscription quota.
    $creditData = $script:Usage.credits
    $balance = [decimal]0
    $hasBalance = $null -ne $creditData -and [decimal]::TryParse([string]$creditData.balance, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$balance)
    # An availability flag without a usable balance must not reveal an unavailable credit row.
    $creditsExist = $creditData -and ($creditData.unlimited -eq $true -or ($hasBalance -and $balance -gt 0))
    $script:CreditsVisible = $script:CreditDisplayMode -eq 'Always' -or ($script:CreditDisplayMode -eq 'Available' -and $creditsExist)
    $creditLabel = Get-CreditLabel
    # Use matching label/value columns, with a rounded whole-number credit total.
    $creditsText.Text = $creditLabel -replace '^Credits: ', ''
    $creditsText.ToolTip = $creditLabel
    # Use a short numeric placeholder for unknown balances in the smallest badge.
    $compactCreditsText.Text = if ($creditData.unlimited -eq $true) { '∞' } elseif ($hasBalance) { $balance.ToString('0', [Globalization.CultureInfo]::CurrentCulture) } elseif ($creditData.hasCredits -eq $false) { '0' } else { '—' }
    $compactCreditsText.ToolTip = $creditLabel

    # Show remaining five-hour quota when the window is available.
    if ($primary -and $null -ne $primary.usedPercent) {
        # Convert used quota once so the label and bar agree.
        $primaryRemaining = [Math]::Min(100, [Math]::Max(0, 100 - [double] $primary.usedPercent))
        $primaryPercent.Text = ('{0:N0}% left' -f $primaryRemaining)
        $primaryBar.Value = $primaryRemaining
        # Keep the server's reset time for the countdown.
        $primaryReset.Text = Format-ResetCountdown -UnixSeconds ([long] $primary.resetsAt)
    }
    else {
        # Preserve the unavailable state instead of implying full quota.
        $primaryPercent.Text = 'Unavailable'
        $primaryBar.Value = 0
        $primaryReset.Text = 'No 5-hour window returned'
    }

    # Show remaining weekly quota when the window is available.
    if ($secondary -and $null -ne $secondary.usedPercent) {
        # Convert used quota once so the label and bar agree.
        $secondaryRemaining = [Math]::Min(100, [Math]::Max(0, 100 - [double] $secondary.usedPercent))
        $secondaryPercent.Text = ('{0:N0}% left' -f $secondaryRemaining)
        $secondaryBar.Value = $secondaryRemaining
        # Keep the server's reset time for the countdown.
        $secondaryReset.Text = Format-ResetCountdown -UnixSeconds ([long] $secondary.resetsAt)
    }
    else {
        # Preserve the unavailable state instead of implying full quota.
        $secondaryPercent.Text = 'Unavailable'
        $secondaryBar.Value = 0
        $secondaryReset.Text = 'No weekly window returned'
    }

    # Reuse the same remaining percentages in the compact badge.
    $compactPrimaryPercent.Text = if ($primary -and $null -ne $primary.usedPercent) { '{0:N0}%' -f $primaryRemaining } else { '—' }
    $compactSecondaryPercent.Text = if ($secondary -and $null -ne $secondary.usedPercent) { '{0:N0}%' -f $secondaryRemaining } else { '—' }
    # Update the compact countdowns each second and expose the full reset time on hover.
    $compactPrimaryReset.Text = if ($primary) { Format-ResetCountdown -UnixSeconds ([long] $primary.resetsAt) -Compact } else { '—' }
    $compactSecondaryReset.Text = if ($secondary) { Format-ResetCountdown -UnixSeconds ([long] $secondary.resetsAt) -Compact } else { '—' }
    # Recheck fit as countdown text changes, including after a reset.
    Update-ResponsiveLayout
    # Keep full reset schedules accessible from both compact percentages after the layout pass.
    $compactPrimaryPercent.ToolTip = $primaryReset.ToolTip
    $compactSecondaryPercent.ToolTip = $secondaryReset.ToolTip
    if ($script:CreditsVisible) {
        $compactPrimaryPercent.ToolTip += [Environment]::NewLine + $creditLabel
        $compactSecondaryPercent.ToolTip += [Environment]::NewLine + $creditLabel
    }
    # Apply status after ordinary tooltips are refreshed so errors remain visible at every size.
    Update-RefreshStatus
}

function Update-RefreshStatus {
    # Highlight stale data without taking space away from compact numbers or hover controls.
    $outerBorder.BorderBrush = if ($script:RefreshError) { '#E8B44C' } else { '#413D4658' }
    $outerBorder.BorderThickness = [Windows.Thickness]::new($(if ($script:RefreshError) { 2 } else { 1 }))
    $outerBorder.ToolTip = if ($script:RefreshError) { "Refresh failed; displayed values may be stale.`n$script:RefreshError" } else { $null }
    if ($script:RefreshError) {
        # Override child tooltips that would otherwise hide the parent's error message.
        foreach ($control in @($compactPrimaryPercent, $compactSecondaryPercent, $compactCreditsText, $creditsText, $primaryReset, $secondaryReset)) {
            $control.ToolTip = $outerBorder.ToolTip
        }
    }
}

function Get-CreditLabel {
    # Treat missing credit data as unknown rather than inventing a zero balance.
    $credits = $script:Usage.credits
    if ($null -eq $credits) { return 'Credits: unavailable' }
    if ($credits.unlimited -eq $true) { return 'Credits: unlimited' }
    # Preserve the service's reported units and precision without assuming a currency.
    if ($null -ne $credits.balance -and -not [string]::IsNullOrWhiteSpace([string]$credits.balance)) {
        # Round the display to a whole credit without changing the account balance.
        $value = [decimal]0
        if ([decimal]::TryParse([string]$credits.balance, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$value)) {
            return ('Credits: ' + $value.ToString('0', [Globalization.CultureInfo]::CurrentCulture))
        }
        return 'Credits: balance unavailable'
    }
    if ($credits.hasCredits -eq $false) { return 'Credits: none' }
    return 'Credits: balance unavailable'
}

function Start-UsageRefresh {
    # A matched input check follows each widget refresh, including manual-only operation.
    if ($script:ReadUsageEnabled -and $script:ReadIntervalMinutes -eq -1) { Read-SharedUsage }
    # Let the poller collect or time out the current request before starting another one.
    if ($script:RefreshProcess) { return }

    $pwsh = (Get-Process -Id $PID).Path
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $pwsh
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-ExecutionPolicy')
    $startInfo.ArgumentList.Add('Bypass')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($script:ReaderPath)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true

    $script:RefreshProcess = [System.Diagnostics.Process]::new()
    $script:RefreshProcess.StartInfo = $startInfo
    try {
        # Drain both pipes while the reader runs so a full pipe cannot block its exit.
        [void] $script:RefreshProcess.Start()
        $script:RefreshStarted = [DateTimeOffset]::Now
        $script:RefreshOutputTask = $script:RefreshProcess.StandardOutput.ReadToEndAsync()
        $script:RefreshErrorTask = $script:RefreshProcess.StandardError.ReadToEndAsync()
        # Poll for completion only while a usage request is actually in flight.
        $pollTimer.Start()
        $planText.Text = 'Refreshing…'
        $statusDot.Fill = '#E8B44C'
    } catch {
        # A failed process launch must leave the next scheduled/manual attempt available.
        $script:RefreshProcess.Dispose()
        $script:RefreshProcess = $null
        # A failed launch must not leave an idle completion timer running.
        $pollTimer.Stop()
        Set-RefreshFailure -Message $_.Exception.Message
    }
}

function Set-RefreshFailure {
    param([string] $Message)
    # Retain last known values while making their stale status visible in every layout.
    $script:RefreshError = $Message
    $planText.Text = 'Unable to refresh'
    $statusDot.Fill = '#F06A7A'
    $updatedText.Text = $Message
    Update-Display
    Update-TrayIcon
}

function Complete-UsageRefresh {
    if (-not $script:RefreshProcess) { return }
    # Check the overall deadline even if the child or one of its output streams is stuck.
    $timedOut = ([DateTimeOffset]::Now - $script:RefreshStarted).TotalSeconds -ge $script:RefreshTimeoutSeconds
    if (-not $timedOut -and (-not $script:RefreshProcess.HasExited -or -not $script:RefreshOutputTask.IsCompleted -or -not $script:RefreshErrorTask.IsCompleted)) { return }
    try {
        if ($timedOut) { throw "Usage refresh timed out after $script:RefreshTimeoutSeconds seconds. Try Refresh again." }
        # Both asynchronous reads have finished, so collecting their results cannot block the UI.
        $output = $script:RefreshOutputTask.GetAwaiter().GetResult().Trim()
        if (-not $output) {
            $details = $script:RefreshErrorTask.GetAwaiter().GetResult().Trim()
            if (-not $details) { $details = 'No response from Codex.' }
            throw $details
        }
        $result = $output | ConvertFrom-Json
        if ($result.error) { throw [string] $result.error }

        $script:Usage = $result
        # Clear stale styling only after a new successful response has been received.
        $script:RefreshError = $null
        $planName = if ($result.planType) { ([string] $result.planType).ToUpperInvariant() } else { 'SIGNED IN' }
        $planText.Text = "$planName plan · live account data"
        $statusDot.Fill = if ($result.ordinaryUsageAllowed) { '#4FD1A5' } else { '#F06A7A' }
        $fetched = [DateTimeOffset]::FromUnixTimeSeconds([long] $result.fetchedAt).ToLocalTime()
        $updatedText.Text = "Updated $($fetched.ToString('h:mm:ss tt'))"
        Update-Display
        Update-TrayIcon
        # Check configured warning thresholds only after receiving fresh account data.
        Show-UsageWarnings
        # Matching writes immediately; explicit file intervals keep their own publishing cadence.
        if ($script:WriteIntervalMinutes -eq -1 -or $script:PublishOnRefresh) { Write-SharedUsage -Force }
        $script:PublishOnRefresh = $false
    }
    catch {
        Set-RefreshFailure -Message $_.Exception.Message
    }
    finally {
        # Terminate a timed-out process tree and always release the request slot.
        try {
            if (-not $script:RefreshProcess.HasExited) { $script:RefreshProcess.Kill($true) }
        } finally {
            $script:RefreshProcess.Dispose()
            $script:RefreshProcess = $null
            $script:RefreshOutputTask = $null
            $script:RefreshErrorTask = $null
            $script:RefreshStarted = $null
            # Success, service errors, and timeouts all return to an idle timer state.
            $pollTimer.Stop()
        }
    }
}

if (Test-Path -LiteralPath $script:StatePath) {
    try {
        $state = Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
        # Restore valid saved colors; older settings files keep the defaults.
        if ($state.primaryColor -match '^#[0-9A-Fa-f]{6}$') { $script:PrimaryColor = $state.primaryColor }
        if ($state.secondaryColor -match '^#[0-9A-Fa-f]{6}$') { $script:SecondaryColor = $state.secondaryColor }
        if ($state.creditColor -match '^#[0-9A-Fa-f]{6}$') { $script:CreditColor = $state.creditColor }
        # Migrate the old default to the muted green while preserving custom selections.
        if ($script:CreditColor -eq '#8BCBB8') { $script:CreditColor = '#91B8B0' }
        # Restore bounded warning thresholds; absent values keep alerts disabled.
        if ($null -ne $state.primaryAlertThreshold -and $state.primaryAlertThreshold -ge 0 -and $state.primaryAlertThreshold -le 100) { $script:PrimaryAlertThreshold = [int]$state.primaryAlertThreshold }
        if ($null -ne $state.secondaryAlertThreshold -and $state.secondaryAlertThreshold -ge 0 -and $state.secondaryAlertThreshold -le 100) { $script:SecondaryAlertThreshold = [int]$state.secondaryAlertThreshold }
        # Older settings keep reset notifications off until explicitly enabled.
        if ($state.notifyPrimaryReset -is [bool]) { $script:NotifyPrimaryReset = $state.notifyPrimaryReset }
        # Older preferences adopt the new display defaults; reject invalid or oversized counts.
        if ($state.primaryResetHours -is [long] -or $state.primaryResetHours -is [int]) {
            if ($state.primaryResetHours -ge 0 -and $state.primaryResetHours -le 168) { $script:PrimaryResetHours = [int]$state.primaryResetHours }
        }
        if ($state.showWeeklyResetDate -is [bool]) { $script:ShowWeeklyResetDate = $state.showWeeklyResetDate }
        # Keep the automatic credit display preference across launches.
        # Older settings adopt the new available-credit default.
        if ($state.creditDisplayMode -in @('Available', 'Always', 'Off')) { $script:CreditDisplayMode = $state.creditDisplayMode }
        # Migrate older preferences to safe v2 defaults; JSON sharing starts disabled unless saved.
        foreach ($key in @('writeUsageEnabled','readUsageEnabled')) {
            if ($state.$key -is [bool]) { Set-Variable -Scope Script -Name $key -Value $state.$key }
        }
        foreach ($key in @('usageOutputPath','usageInputPath')) {
            if ($state.$key -is [string]) { Set-Variable -Scope Script -Name $key -Value $state.$key }
        }
        # Older shared connections remain enabled; new installations start with the master lock off.
        $script:SharedEnabled = $script:WriteUsageEnabled -or $script:ReadUsageEnabled
        if ($state.sharedEnabled -is [bool]) { $script:SharedEnabled = $state.sharedEnabled }
        if ($state.sharedCreditDisplayMode -in @('Available','Always','Off')) { $script:SharedCreditDisplayMode = $state.sharedCreditDisplayMode }
        foreach ($key in @('sharedShowWeeklyResetDate','sharedNotifyPrimaryReset')) {
            if ($state.$key -is [bool]) { Set-Variable -Scope Script -Name $key -Value $state.$key }
        }
        foreach ($key in @('sharedPrimaryResetHours','sharedPrimaryAlertThreshold','sharedSecondaryAlertThreshold')) {
            $maximum = if ($key -eq 'sharedPrimaryResetHours') { 168 } else { 100 }
            if (($state.$key -is [int] -or $state.$key -is [long]) -and $state.$key -ge 0 -and $state.$key -le $maximum) { Set-Variable -Scope Script -Name $key -Value ([int]$state.$key) }
        }
        # Bound the cleaned nickname rather than the original text containing control characters.
        if ($state.localDisplayName -is [string] -and $state.localDisplayName.Trim()) {
            $savedName = ($state.localDisplayName -replace '[\p{C}]','').Trim()
            if ($savedName) { $script:LocalDisplayName = $savedName.Substring(0,[Math]::Min(40,$savedName.Length)) }
        }
        if ($state.sharingSourceId -match '^[0-9a-f]{32}$') { $script:SharingSourceId = $state.sharingSourceId }
        foreach ($key in @('writeIntervalMinutes','readIntervalMinutes')) {
            if (($state.$key -is [long] -or $state.$key -is [int]) -and $state.$key -in @(-1,0,1,5,15,30)) { Set-Variable -Scope Script -Name $key -Value ([int]$state.$key) }
        }
        if ($state.accountLayout -in @('Side by side','Stacked','Account picker')) { $script:AccountLayout = $state.accountLayout }
        if ($state.selectedAccount -in @('Local','Remote')) { $script:SelectedAccount = $state.selectedAccount }
        # Preserve palette selections saved before the Fuchsia label was shortened.
        foreach ($key in @('localScheme','remoteScheme')) {
            if ($state.$key -eq 'Muted fuchsia / mauve / mist') { $state.$key = 'Fuchsia / mauve / mist' }
        }
        if ($state.localScheme -and $script:ColorSchemes.Contains([string]$state.localScheme)) { $script:LocalScheme = $state.localScheme }
        if ($state.remoteScheme -and $script:ColorSchemes.Contains([string]$state.remoteScheme)) { $script:RemoteScheme = $state.remoteScheme }
        if ($null -ne $state.left -and $null -ne $state.top) {
            $window.WindowStartupLocation = 'Manual'
            $window.Left = [double] $state.left
            $window.Top = [double] $state.top
        }
        if ($null -ne $state.width -and [double] $state.width -ge $window.MinWidth) {
            $window.Width = [double] $state.width
        }
        if ($null -ne $state.height -and [double] $state.height -ge $window.MinHeight) {
            $window.Height = [double] $state.height
        }
        if ($null -ne $state.topmost) {
            $window.Topmost = [bool] $state.topmost
        }
        if ($null -ne $state.refreshIntervalMinutes -and [int] $state.refreshIntervalMinutes -in @(0, 1, 5, 15, 30)) {
            $script:RefreshIntervalMinutes = [int] $state.refreshIntervalMinutes
        }
    } catch { }
}
else {
    $window.WindowStartupLocation = 'CenterScreen'
}
# Apply a coordinated palette and create the optional peer views after restoring local preferences.
Set-AccountScheme $script:LocalScheme
Initialize-SharedWarnings
Initialize-AccountViews

$dragArea.Add_MouseLeftButtonDown({
    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left -and
        $window.WindowState -eq [System.Windows.WindowState]::Normal) {
        Start-WidgetDrag
    }
})
# Keep the intermediate bar layout draggable after its title header disappears.
$outerBorder.Add_MouseLeftButtonDown({
    if ($dragArea.Visibility -ne 'Visible' -and $ultraCompactPanel.Visibility -eq 'Collapsed' -and -not $compactRefreshButton.IsMouseOver -and -not $hoverRefreshButton.IsMouseOver -and -not $hoverCloseButton.IsMouseOver -and -not $hoverMinimizeButton.IsMouseOver -and -not $hoverPinButton.IsMouseOver -and $_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        Start-WidgetDrag
    }
})
$ultraCompactPanel.Add_MouseLeftButtonDown({
    if ($_.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        if ($_.ClickCount -eq 2) {
            Set-WidgetPreset 'Large / Default'
        }
        elseif ($window.WindowState -eq [System.Windows.WindowState]::Normal) {
            Start-WidgetDrag
        }
    }
})
# Continue dragging beyond the widget bounds while captured, then save on release.
$outerBorder.Add_MouseMove({ if ([Windows.Input.Mouse]::LeftButton -eq 'Pressed') { Update-WidgetDrag } })
$outerBorder.Add_MouseLeftButtonUp({
    if ($script:DragOrigin) {
        Update-WidgetDrag
        $script:DragOrigin = $null
        $outerBorder.ReleaseMouseCapture()
        Save-WidgetState
    }
})
# Losing capture must never leave the window following later pointer movements.
$outerBorder.Add_LostMouseCapture({ $script:DragOrigin = $null })
$refreshButton.Add_Click({ Invoke-WidgetRefresh })
# The compact refresh button uses the same asynchronous account refresh.
$compactRefreshButton.Add_Click({ Invoke-WidgetRefresh })
$hoverRefreshButton.Add_Click({ Invoke-WidgetRefresh })
$pinButton.Add_Click({
    $window.Topmost = -not $window.Topmost
    Update-PinDisplay
})
$minimizeButton.Add_Click({ $window.WindowState = [System.Windows.WindowState]::Minimized })
# Forward hover actions through the existing buttons to preserve identical behavior.
$hoverMinimizeButton.Add_Click({ $minimizeButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) })
$hoverPinButton.Add_Click({ $pinButton.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent)) })
$closeButton.Add_Click({ $window.Close() })
# Use the normal close path so hovering and closing still saves all settings.
$hoverCloseButton.Add_Click({ $window.Close() })
$outerBorder.Add_MouseEnter({ Update-HoverControls -IsPointerOver $true })
$outerBorder.Add_MouseLeave({ Update-HoverControls -IsPointerOver $false })
$window.Add_SizeChanged({ Update-ResponsiveLayout })
$window.Add_StateChanged({
    if ($window.WindowState -eq [System.Windows.WindowState]::Minimized) {
        $window.ShowInTaskbar = $false
        $window.Hide()
    }
})
$trayIcon.Add_DoubleClick({ Show-Widget })
$trayOpenItem.Add_Click({ Show-Widget })
$trayRefreshItem.Add_Click({ Invoke-WidgetRefresh })
# Apply settings through one native dialog instead of several competing menus.
$settingsItem.Add_Click({ Show-WidgetSettings })
$trayExitItem.Add_Click({ $window.Close() })
$window.Add_Closing({
    # Use the same settings writer as preset sizes and refresh interval changes.
    Save-WidgetState
    # Stop file polling before disposing the window and tray controls.
    if ($script:SharingTimer) { $script:SharingTimer.Stop() }
    if ($script:RefreshProcess -and -not $script:RefreshProcess.HasExited) {
        $script:RefreshProcess.Kill($true)
    }
    $trayIcon.Visible = $false
    $trayIcon.Dispose()
    $trayMenu.Dispose()
    if ($script:TrayIconImage) { $script:TrayIconImage.Dispose() }
    if ($script:WindowIconImage) { $script:WindowIconImage.Dispose() }
})

$pollTimer = [Windows.Threading.DispatcherTimer]::new()
$pollTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$pollTimer.Add_Tick({ Complete-UsageRefresh })
# Start this timer inside Start-UsageRefresh, not while waiting between requests.

$clockTimer = [Windows.Threading.DispatcherTimer]::new()
$clockTimer.Interval = [TimeSpan]::FromSeconds(1)
$clockTimer.Add_Tick({ Update-Display })
# Pause per-second countdown/layout work while hidden; account refreshes remain independent.
$window.Add_IsVisibleChanged({
    if ($window.IsVisible) {
        # Refresh countdowns immediately on restore instead of showing old text for a second.
        Update-Display
        $clockTimer.Start()
    } else {
        $clockTimer.Stop()
    }
})

$script:RefreshTimer = [Windows.Threading.DispatcherTimer]::new()
$script:RefreshTimer.Add_Tick({ Start-UsageRefresh })
Set-RefreshInterval -Minutes $script:RefreshIntervalMinutes
# Independent file timers remain active in the tray but do no work when sharing is disabled.
$script:SharingTimer = [Windows.Threading.DispatcherTimer]::new()
$script:SharingTimer.Interval = [TimeSpan]::FromSeconds(5)
$script:SharingTimer.Add_Tick({ Invoke-SharingTick })
Update-SharingTimer

$window.Add_ContentRendered({
    # Apply restored colors once all controls and icons are initialized.
    Update-QuotaColors
    Update-PinDisplay

    Update-ResponsiveLayout
    Read-SharedUsage
    Start-UsageRefresh
})
# End the event loop only on explicit close; hiding to the tray must keep timers and menus alive.
$window.Add_Closed({ $window.Dispatcher.BeginInvokeShutdown([Windows.Threading.DispatcherPriority]::Normal) })
# A modeless window can hide and restore without ending the script's message loop.
$window.Show()
[Windows.Threading.Dispatcher]::Run()



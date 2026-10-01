function New-SettingsChoice {
    param([string[]] $Choices, [string] $Selected)
    # Replace only the native selector chrome that otherwise keeps a white arrow in dark mode.
    if (-not ('CodexUsageWidget.ThemedComboBox' -as [type])) {
        $themeReferences = @([ComponentModel.Component].Assembly.Location) + @([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -match '^System\.(Windows\.Forms|Drawing|Private\.Windows)' -and -not $_.IsDynamic } | ForEach-Object { $_.Location })
        Add-Type -ReferencedAssemblies $themeReferences -TypeDefinition @'
using System;
using System.Drawing;
using System.Windows.Forms;
namespace CodexUsageWidget {
    public class ThemedComboBox : ComboBox {
        protected override void WndProc(ref Message message) {
            // Preserve the normal dropdown, keyboard input and accessibility behavior.
            base.WndProc(ref message);
            if (message.Msg != 0x000F && message.Msg != 0x0317 && message.Msg != 0x0318) return;
            // Paint the same arrow and outline for on-screen rendering and bitmap previews.
            using (Graphics graphics = message.Msg == 0x000F ? Graphics.FromHwnd(Handle) : Graphics.FromHdc(message.WParam)) {
                int arrowWidth = SystemInformation.VerticalScrollBarWidth;
                int x = ClientSize.Width - arrowWidth;
                using (Brush background = new SolidBrush(BackColor)) graphics.FillRectangle(background, x, 0, arrowWidth, ClientSize.Height);
                Color text = Enabled ? ForeColor : SystemColors.GrayText;
                using (Pen border = new Pen(BackColor.GetBrightness() < .5f ? Color.FromArgb(80,80,80) : Color.FromArgb(160,160,160))) graphics.DrawRectangle(border, 0, 0, ClientSize.Width - 1, ClientSize.Height - 1);
                int center = x + arrowWidth / 2;
                int y = ClientSize.Height / 2;
                using (Brush arrow = new SolidBrush(text)) graphics.FillPolygon(arrow, new Point[] { new Point(center-3,y-1), new Point(center+3,y-1), new Point(center,y+2) });
            }
        }
    }
}
'@
    }
    # Use native non-editable selectors so unsupported values cannot be entered.
    $control = [CodexUsageWidget.ThemedComboBox]::new()
    $control.DropDownStyle = 'DropDownList'
    # Draw all selector text ourselves so Windows cannot leave selected dropdowns white in dark mode.
    $control.DrawMode = 'OwnerDrawFixed'
    $control.FlatStyle = 'Popup'
    $control.Add_DrawItem({
        param($sender,$eventArgs)
        if ($eventArgs.Index -lt 0) { return }
        # Distinguish the highlighted dropdown row while leaving the closed selector's colors unchanged.
        $highlighted = ($eventArgs.State -band [Windows.Forms.DrawItemState]::Selected) -and -not ($eventArgs.State -band [Windows.Forms.DrawItemState]::ComboBoxEdit)
        $dark = $sender.BackColor.GetBrightness() -lt 0.5
        $background = if ($highlighted -and $dark) { [Drawing.Color]::FromArgb(65,65,65) } elseif ($highlighted) { [Drawing.SystemColors]::Highlight } else { $sender.BackColor }
        $brush = [Drawing.SolidBrush]::new($background)
        try { $eventArgs.Graphics.FillRectangle($brush,$eventArgs.Bounds) } finally { $brush.Dispose() }
        $color = if (-not $sender.Enabled) { [Drawing.SystemColors]::GrayText } elseif ($highlighted -and -not $dark) { [Drawing.SystemColors]::HighlightText } else { $sender.ForeColor }
        [Windows.Forms.TextRenderer]::DrawText($eventArgs.Graphics,[string]$sender.Items[$eventArgs.Index],$sender.Font,$eventArgs.Bounds,$color,([Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::VerticalCenter -bor [Windows.Forms.TextFormatFlags]::EndEllipsis -bor [Windows.Forms.TextFormatFlags]::NoPrefix))
        $eventArgs.DrawFocusRectangle()
    })
    $control.Items.AddRange([object[]]$Choices)
    $control.SelectedItem = $Selected
    if ($control.SelectedIndex -lt 0) { $control.SelectedIndex = 0 }
    return $control
}

function Set-SettingsChoiceTheme {
    param($Dialog,$Controls)
    # Follow the rendered panel's actual color, including the system high-contrast preference.
    $dark = $Dialog.BackColor.GetBrightness() -lt 0.5
    foreach ($control in $Controls.Values) {
        if ($control -isnot [Windows.Forms.ComboBox]) { continue }
        $control.BackColor = if ([Windows.Forms.SystemInformation]::HighContrast) { [Drawing.SystemColors]::Window } elseif ($dark) { [Drawing.Color]::FromArgb(45,45,45) } else { [Drawing.Color]::White }
        $control.ForeColor = if ([Windows.Forms.SystemInformation]::HighContrast) { [Drawing.SystemColors]::WindowText } elseif ($dark) { [Drawing.Color]::FromArgb(235,235,235) } else { [Drawing.Color]::Black }
    }
}

function Add-SettingsRow {
    param($Table, [string] $Label, $Control, $Browse)
    # Let native preferred sizes determine row height and wrap longer labels on high-DPI screens.
    $row = $Table.RowCount
    $Table.RowCount++
    [void]$Table.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    $caption = [Windows.Forms.Label]::new()
    $caption.Text = $Label
    $caption.AutoSize = $true
    $caption.Dock = 'Fill'
    $caption.TextAlign = 'MiddleLeft'
    $caption.Margin = [Windows.Forms.Padding]::new(3,8,8,8)
    $Control.Dock = 'Fill'
    $Control.Margin = [Windows.Forms.Padding]::new(3,5,3,5)
    [void]$Table.Controls.Add($caption,0,$row)
    [void]$Table.Controls.Add($Control,1,$row)
    if ($Browse) { $Browse.AutoSize = $true; [void]$Table.Controls.Add($Browse,2,$row) }
    else { $Table.SetColumnSpan($Control,2) }
}

function Add-SettingsNote {
    param($Table, [string] $Text)
    # Reserve a full-width row for short help text, section names, and live sharing status.
    $label = [Windows.Forms.Label]::new()
    $label.Text = $Text
    $label.AutoSize = $true
    $label.Dock = 'Fill'
    $label.Margin = [Windows.Forms.Padding]::new(3,7,3,7)
    $row = $Table.RowCount
    $Table.RowCount++
    [void]$Table.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
    [void]$Table.Controls.Add($label,0,$row)
    $Table.SetColumnSpan($label,3)
    return $label
}

function Set-SettingsHelp {
    param($ToolTip, $Control, [string] $Text)
    # Attach help to both the input and its internal native controls, such as numeric editors.
    $ToolTip.SetToolTip($Control,$Text)
    foreach ($child in $Control.Controls) { $ToolTip.SetToolTip($child,$Text) }
    # Let users hover over the row label as well as the setting itself.
    $table = $Control.Parent
    if ($table -is [Windows.Forms.TableLayoutPanel]) {
        $row = $table.GetPositionFromControl($Control).Row
        foreach ($caption in $table.Controls) {
            $position = $table.GetPositionFromControl($caption)
            if ($position.Row -eq $row -and $position.Column -eq 0) { $ToolTip.SetToolTip($caption,$Text) }
        }
    }
}
function Show-WidgetSettings {
    # Focus the existing settings window instead of opening competing drafts.
    if ($script:SettingsForm -and -not $script:SettingsForm.IsDisposed) { [void]$script:SettingsForm.Activate(); return }
    # Keep all settings in one native Windows dialog that follows the system app theme.
    $dialog = [Windows.Forms.Form]::new()
    $dialog.Text = "Codex Usage v$script:WidgetVersion · Settings"
    $dialog.ClientSize = [Drawing.Size]::new(600,760)
    $dialog.MinimumSize = [Drawing.Size]::new(540,640)
    $dialog.StartPosition = 'CenterScreen'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.TopMost = $true
    # Keep explanatory text available on hover without reserving full rows in the dialog.
    $settingsToolTip = [Windows.Forms.ToolTip]::new()
    $settingsToolTip.InitialDelay = 500
    $settingsToolTip.ReshowDelay = 100
    $settingsToolTip.AutoPopDelay = 20000
    $settingsToolTip.ShowAlways = $true
    $tabs = [Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'
    $tables = @{}
    foreach ($name in @('General','Shared')) {
        # Scroll a tab only when Windows text scaling makes its controls exceed the available height.
        $page = [Windows.Forms.TabPage]::new($name)
        $page.AutoScroll = $true
        $table = [Windows.Forms.TableLayoutPanel]::new()
        $table.Dock = 'Top'
        $table.AutoSize = $true
        $table.Padding = [Windows.Forms.Padding]::new(12)
        $table.ColumnCount = 3
        $table.RowCount = 0
        [void]$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,35))
        [void]$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,65))
        [void]$table.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::AutoSize))
        [void]$page.Controls.Add($table)
        [void]$tabs.TabPages.Add($page)
        $tables[$name] = $table
    }
    $controls = @{}
    $intervalChoices = @('Match widget refresh','Every 1 minute','Every 5 minutes','Every 15 minutes','Every 30 minutes','Manual only')
    $intervalValues = @(-1,1,5,15,30,0)
    $widgetChoices = @('Every 1 minute','Every 5 minutes','Every 15 minutes','Every 30 minutes','Manual only')
    $controls.Refresh = New-SettingsChoice $widgetChoices $widgetChoices[@(1,5,15,30,0).IndexOf($script:RefreshIntervalMinutes)]
    Add-SettingsRow $tables.General 'Widget refresh' $controls.Refresh
    # Restore startup and window choices without applying them until Save.
    foreach ($entry in @(@{Key='Startup';Text='Launch at Windows sign-in';Value=(Get-LaunchAtSignIn)},@{Key='Topmost';Text='Keep widget on top';Value=$window.Topmost})) {
        $check = [Windows.Forms.CheckBox]::new()
        $check.Text = $entry.Text
        $check.AutoSize = $true
        $check.Checked = $entry.Value
        $controls[$entry.Key] = $check
        Add-SettingsRow $tables.General '' $check
    }
    $controls.Size = New-SettingsChoice @('Keep current size','Mini','Small','Medium','Large / Default') 'Keep current size'
    Add-SettingsRow $tables.General 'Window size' $controls.Size
    $controls.Position = New-SettingsChoice @('Keep current position','Top left','Top right','Bottom left','Bottom right') 'Keep current position'
    Add-SettingsRow $tables.General 'Position' $controls.Position
    # The master switch stays usable while all other Shared controls are locked.
    $controls.SharedEnabled = [Windows.Forms.CheckBox]::new()
    $controls.SharedEnabled.Text = 'Enable Shared'
    $controls.SharedEnabled.AutoSize = $true
    $controls.SharedEnabled.Checked = $script:SharedEnabled
    Add-SettingsRow $tables.Shared '' $controls.SharedEnabled
    $controls.SharedLock = Add-SettingsNote $tables.Shared ''
    # Keep second-account layout and palette controls beside their shared-file connections.
    $controls.Layout = New-SettingsChoice @('Side by side','Stacked','Account picker','Separate windows') $script:AccountLayout
    Add-SettingsRow $tables.Shared 'Account layout' $controls.Layout
    # Keep the choice tied to its account index even when both accounts have the same nickname.
    $controls.Account = New-SettingsChoice @($script:LocalDisplayName,$script:RemoteDisplayName) $script:LocalDisplayName
    $controls.Account.SelectedIndex = if ($script:SelectedAccount -eq 'Remote') { 1 } else { 0 }
    Add-SettingsRow $tables.Shared 'Picker account' $controls.Account
    $controls.LocalScheme = New-SettingsChoice @($script:ColorSchemes.Keys) $script:LocalScheme
    $controls.RemoteScheme = New-SettingsChoice @($script:ColorSchemes.Keys) $script:RemoteScheme
    Add-SettingsRow $tables.General 'This computer''s colors' $controls.LocalScheme
    Add-SettingsRow $tables.Shared 'Shared computer''s colors' $controls.RemoteScheme
    $controls.Credits = New-SettingsChoice @('When credits exist','Always show','Off') @{'Available'='When credits exist';'Always'='Always show';'Off'='Off'}[$script:CreditDisplayMode]
    Add-SettingsRow $tables.General 'Credit display' $controls.Credits
    $controls.ResetHours = [Windows.Forms.NumericUpDown]::new()
    $controls.ResetHours.Maximum = 168
    $controls.ResetHours.Value = $script:PrimaryResetHours
    Add-SettingsRow $tables.General '5-hour times: hours ahead' $controls.ResetHours
    $controls.WeeklyDate = [Windows.Forms.CheckBox]::new()
    $controls.WeeklyDate.Text = 'Show weekly reset date and time'
    $controls.WeeklyDate.AutoSize = $true
    $controls.WeeklyDate.Checked = $script:ShowWeeklyResetDate
    Add-SettingsRow $tables.General '' $controls.WeeklyDate
    # Mirror the local display and notification choices for the imported account.
    $controls.SharedCredits = New-SettingsChoice @('When credits exist','Always show','Off') @{'Available'='When credits exist';'Always'='Always show';'Off'='Off'}[$script:SharedCreditDisplayMode]
    Add-SettingsRow $tables.Shared 'Credit display' $controls.SharedCredits
    $controls.SharedResetHours = [Windows.Forms.NumericUpDown]::new()
    $controls.SharedResetHours.Maximum = 168
    $controls.SharedResetHours.Value = $script:SharedPrimaryResetHours
    Add-SettingsRow $tables.Shared '5-hour times: hours ahead' $controls.SharedResetHours
    $controls.SharedWeeklyDate = [Windows.Forms.CheckBox]::new()
    $controls.SharedWeeklyDate.Text = 'Show weekly reset date and time'
    $controls.SharedWeeklyDate.AutoSize = $true
    $controls.SharedWeeklyDate.Checked = $script:SharedShowWeeklyResetDate
    Add-SettingsRow $tables.Shared '' $controls.SharedWeeklyDate
    foreach ($entry in @(@{Key='SharedPrimaryAlert';Label='5-hour warning below %';Value=$script:SharedPrimaryAlertThreshold},@{Key='SharedSecondaryAlert';Label='Weekly warning below %';Value=$script:SharedSecondaryAlertThreshold})) {
        $input = [Windows.Forms.NumericUpDown]::new()
        $input.Maximum = 100
        $input.Value = $entry.Value
        $controls[$entry.Key] = $input
        Add-SettingsRow $tables.Shared $entry.Label $input
    }
    $controls.SharedResetAlert = [Windows.Forms.CheckBox]::new()
    $controls.SharedResetAlert.Text = 'Notify when the 5-hour window resets'
    $controls.SharedResetAlert.AutoSize = $true
    $controls.SharedResetAlert.Checked = $script:SharedNotifyPrimaryReset
    Add-SettingsRow $tables.Shared '' $controls.SharedResetAlert
    # Use independent writer and reader enable switches, paths, and frequency selectors.
    $controls.Name = [Windows.Forms.TextBox]::new()
    $controls.Name.MaxLength = 40
    $controls.Name.Text = $script:LocalDisplayName
    foreach ($kind in @('Write','Read')) {
        $enable = [Windows.Forms.CheckBox]::new()
        $enable.AutoSize = $true
        $enable.Text = if ($kind -eq 'Write') { 'Write my usage to JSON' } else { 'Read the shared computer''s JSON' }
        $enable.Checked = if ($kind -eq 'Write') { $script:WriteUsageEnabled } else { $script:ReadUsageEnabled }
        $controls[$kind + 'Enabled'] = $enable
        Add-SettingsRow $tables.Shared '' $enable
        if ($kind -eq 'Write') { Add-SettingsRow $tables.Shared 'My display name' $controls.Name }
        $path = [Windows.Forms.TextBox]::new()
        $path.Text = if ($kind -eq 'Write') { $script:UsageOutputPath } else { $script:UsageInputPath }
        $controls[$kind + 'Path'] = $path
        $browse = [Windows.Forms.Button]::new()
        $browse.Text = 'Browse…'
        $browse.Tag = @{ Kind=$kind; Input=$path }
        $browse.Add_Click({
            param($sender,$eventArgs)
            # Pick an actual usage file without opening, exporting, or modifying its contents here.
            $chooser = if ($sender.Tag.Kind -eq 'Write') { [Windows.Forms.SaveFileDialog]::new() } else { [Windows.Forms.OpenFileDialog]::new() }
            try {
                $chooser.Filter = 'Usage JSON (*.json)|*.json'
                $chooser.FileName = if ($sender.Tag.Input.Text) { [Environment]::ExpandEnvironmentVariables($sender.Tag.Input.Text) } elseif ($sender.Tag.Kind -eq 'Write') { 'my-usage.json' } else { '' }
                if ($chooser.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) { $sender.Tag.Input.Text = $chooser.FileName }
            } finally { $chooser.Dispose() }
        })
        $controls[$kind + 'Browse'] = $browse
        Add-SettingsRow $tables.Shared $(if ($kind -eq 'Write') { 'Output file' } else { 'Input file' }) $path $browse
        $interval = if ($kind -eq 'Write') { $script:WriteIntervalMinutes } else { $script:ReadIntervalMinutes }
        $choice = New-SettingsChoice $intervalChoices $intervalChoices[$intervalValues.IndexOf($interval)]
        $controls[$kind + 'Interval'] = $choice
        Add-SettingsRow $tables.Shared ($kind + ' frequency') $choice
        $controls[$kind + 'Status'] = Add-SettingsNote $tables.Shared ''
    }
    $controls.SourceStatus = Add-SettingsNote $tables.Shared ''
    # Keep alerts local even while displaying a remote account or both accounts together.
    foreach ($entry in @(@{Key='PrimaryAlert';Label='5-hour warning below %';Value=$script:PrimaryAlertThreshold},@{Key='SecondaryAlert';Label='Weekly warning below %';Value=$script:SecondaryAlertThreshold})) {
        $input = [Windows.Forms.NumericUpDown]::new()
        $input.Maximum = 100
        $input.Value = $entry.Value
        $controls[$entry.Key] = $input
        Add-SettingsRow $tables.General $entry.Label $input
    }
    $controls.ResetAlert = [Windows.Forms.CheckBox]::new()
    $controls.ResetAlert.Text = 'Notify when the 5-hour window resets'
    $controls.ResetAlert.AutoSize = $true
    $controls.ResetAlert.Checked = $script:NotifyPrimaryReset
    Add-SettingsRow $tables.General '' $controls.ResetAlert
    # Map former help paragraphs to the settings and labels they explain.
    Set-SettingsHelp $settingsToolTip $controls.Refresh 'Checks this computer''s Codex account. File timers use the latest available reading.'
    foreach ($key in @('ResetHours','SharedResetHours')) {
        Set-SettingsHelp $settingsToolTip $controls[$key] '0 = off. Later reset times are estimates assuming immediate reuse.'
    }
    foreach ($key in @('PrimaryAlert','SecondaryAlert')) {
        Set-SettingsHelp $settingsToolTip $controls[$key] 'Notifications apply to this computer''s account. 0 = off. Warnings appear once per threshold crossing.'
    }
    Set-SettingsHelp $settingsToolTip $controls.ResetAlert 'A reset notification requires weekly quota above 0%.'
    foreach ($key in @('SharedPrimaryAlert','SharedSecondaryAlert')) {
        Set-SettingsHelp $settingsToolTip $controls[$key] 'Shared notifications appear on this computer for fresh imported readings. 0 = off. Warnings appear once per threshold crossing.'
    }
    Set-SettingsHelp $settingsToolTip $controls.SharedResetAlert 'Reset alerts require weekly quota above 0%. Missing or stale files do not trigger alerts.'
    Set-SettingsHelp $settingsToolTip $controls.Layout 'Use independent settings for the second account. Side by side keeps two numeric columns at Mini size.'
    Set-SettingsHelp $settingsToolTip $controls.SharedEnabled 'Unlock shared settings and enable the selected file connections. Turning Shared off preserves your choices and stops its display, file operations and notifications after Apply or Save.'
    foreach ($key in @('WritePath','ReadPath','WriteBrowse','ReadBrowse')) {
        Set-SettingsHelp $settingsToolTip $controls[$key] 'Use different output files on the two computers. Keep shared usage outside the public widget project. Writes occur when usage or account details change, with a 30-minute check-in during automatic sharing. Manual only remains manual. Last usage change is separate from the actual last check.'
    }
    # Apply and Save share validation, live updates, and persistence.
    $applySettings = {
        # Validate all sharing paths before changing any persistent setting.
        $output = if ($controls.SharedEnabled.Checked -and $controls.WriteEnabled.Checked) { Resolve-UsageFilePath $controls.WritePath.Text } else { $controls.WritePath.Text.Trim() }
        $inputPath = if ($controls.SharedEnabled.Checked -and $controls.ReadEnabled.Checked) { Resolve-UsageFilePath $controls.ReadPath.Text } else { $controls.ReadPath.Text.Trim() }
        if ($controls.SharedEnabled.Checked -and $controls.WriteEnabled.Checked -and $controls.ReadEnabled.Checked -and $output -eq $inputPath) { throw 'Input and output must be different files.' }
        if ($controls.SharedEnabled.Checked -and $controls.WriteEnabled.Checked -and -not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($output))) { throw 'Choose an existing private output folder.' }
        $name = ($controls.Name.Text -replace '[\p{C}]','').Trim()
        if (-not $name) { $name = 'This computer' }
        if ((Get-LaunchAtSignIn) -ne $controls.Startup.Checked) { Set-LaunchAtSignIn $controls.Startup.Checked }
        # Reset imported values only when the source path changes, never on temporary sync errors.
        if ($script:UsageInputPath -ne $inputPath) { $script:RemoteUsage = $null; $script:RemoteDisplayName = 'Shared computer'; $script:ReadFileStamp=''; $script:ReadError = $null; $script:LastReadAt = $null }
        if ($script:UsageOutputPath -ne $output) { $script:PublishedTarget=''; $script:PublishedUsageKey=$null; $script:PublishedMetadataKey=$null; $script:UsageChangedAt=0; $script:LastWrittenAt = $null; $script:WriteError = $null }
        # Preserve draft connection switches and independent choices even when the master lock is off.
        $script:SharedEnabled = $controls.SharedEnabled.Checked
        $script:SharedCreditDisplayMode = @('Available','Always','Off')[$controls.SharedCredits.SelectedIndex]
        $script:SharedPrimaryResetHours = [int]$controls.SharedResetHours.Value
        $script:SharedShowWeeklyResetDate = $controls.SharedWeeklyDate.Checked
        $script:SharedPrimaryAlertThreshold = [int]$controls.SharedPrimaryAlert.Value
        $script:SharedSecondaryAlertThreshold = [int]$controls.SharedSecondaryAlert.Value
        if ($script:SharedNotifyPrimaryReset -ne $controls.SharedResetAlert.Checked) { $script:SharedAlertStates.Remove('primaryReset') }
        $script:SharedNotifyPrimaryReset = $controls.SharedResetAlert.Checked
        $script:UsageOutputPath = $output
        $script:UsageInputPath = $inputPath
        $script:LocalDisplayName = $name
        $script:WriteUsageEnabled = $controls.WriteEnabled.Checked
        $script:ReadUsageEnabled = $controls.ReadEnabled.Checked
        $script:WriteIntervalMinutes = $intervalValues[$controls.WriteInterval.SelectedIndex]
        $script:ReadIntervalMinutes = $intervalValues[$controls.ReadInterval.SelectedIndex]
        $script:NextWriteAt = [DateTimeOffset]::Now
        $script:NextReadAt = [DateTimeOffset]::Now
        $script:AccountLayout = [string]$controls.Layout.SelectedItem
        $script:SelectedAccount = if ($controls.Account.SelectedIndex -eq 1) { 'Remote' } else { 'Local' }
        $script:AccountPicker.SelectedIndex = $controls.Account.SelectedIndex
        Set-AccountScheme ([string]$controls.LocalScheme.SelectedItem)
        Set-AccountScheme ([string]$controls.RemoteScheme.SelectedItem) -Remote
        $script:CreditDisplayMode = @('Available','Always','Off')[$controls.Credits.SelectedIndex]
        $script:PrimaryResetHours = [int]$controls.ResetHours.Value
        $script:ShowWeeklyResetDate = $controls.WeeklyDate.Checked
        $script:PrimaryAlertThreshold = [int]$controls.PrimaryAlert.Value
        $script:SecondaryAlertThreshold = [int]$controls.SecondaryAlert.Value
        if ($script:NotifyPrimaryReset -ne $controls.ResetAlert.Checked) { $script:AlertStates.Remove('primaryReset') }
        $script:NotifyPrimaryReset = $controls.ResetAlert.Checked
        $window.Topmost = $controls.Topmost.Checked
        Set-RefreshInterval @(1,5,15,30,0)[$controls.Refresh.SelectedIndex]
        Update-SharingTimer
        Update-QuotaColors
        Update-PinDisplay
        # Saving an enabled connection performs an initial read/write, even in manual mode.
        Read-SharedUsage
        Write-SharedUsage -Force
        Update-Display
        if ($controls.Size.SelectedItem -ne 'Keep current size') { Set-WidgetPreset ([string]$controls.Size.SelectedItem) }
        if ($controls.Position.SelectedItem -ne 'Keep current position') { Set-WidgetCorner ([string]$controls.Position.SelectedItem) }
        Save-SharedWarnings
        Save-WarningState
        Save-WidgetState
    }
    $footer = [Windows.Forms.FlowLayoutPanel]::new()
    $footer.Dock = 'Bottom'
    $footer.Height = 45
    $footer.FlowDirection = 'RightToLeft'
    $footer.Padding = [Windows.Forms.Padding]::new(8)
    $save = [Windows.Forms.Button]::new()
    $save.Text = 'Save'
    $cancel = [Windows.Forms.Button]::new()
    $cancel.Text = 'Cancel'
    # Apply commits changes without setting a dialog result or closing the settings window.
    $apply = [Windows.Forms.Button]::new()
    $apply.Text = 'Apply'
    $apply.Add_Click({
        try { & $applySettings; & $updateStatus }
        catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Unable to apply settings') }
    })
    [void]$footer.Controls.Add($save)
    [void]$footer.Controls.Add($cancel)
    [void]$footer.Controls.Add($apply)
    [void]$dialog.Controls.Add($tabs)
    [void]$dialog.Controls.Add($footer)
    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel
    $statusTimer = [Windows.Forms.Timer]::new()
    $statusTimer.Interval = 1000
    $updateStatus = {
        # Defer status-driven layout and selector changes while any native dropdown is open.
        foreach ($control in $controls.Values) {
            if ($control -is [Windows.Forms.ComboBox] -and $control.DroppedDown) { return }
        }
        # Refresh imported nicknames without changing the draft's account selection.
        $accountIndex = $controls.Account.SelectedIndex
        $names = @($script:LocalDisplayName,$script:RemoteDisplayName)
        for ($index = 0; $index -lt 2; $index++) {
            if ([string]$controls.Account.Items[$index] -ne $names[$index]) { $controls.Account.Items[$index] = $names[$index] }
        }
        $controls.Account.SelectedIndex = $accountIndex
        # Show draft cadence alongside live operation status while the dialog is open.
        # Lock every Shared setting except the master switch, retaining all selections.
        $sharedOn = $controls.SharedEnabled.Checked
        foreach ($control in $tables.Shared.Controls) { $control.Enabled = $sharedOn }
        $controls.SharedEnabled.Enabled = $true
        $controls.SharedLock.Enabled = $true
        $controls.SharedLock.Text = if ($sharedOn) { 'Unlocked - Shared is enabled' } else { 'Locked - enable Shared to change settings' }
        $base = @(1,5,15,30,0)[$controls.Refresh.SelectedIndex]
        foreach ($kind in @('Write','Read')) {
            $enabled = $sharedOn -and $controls[$kind + 'Enabled'].Checked
            foreach ($suffix in @('Path','Browse','Interval')) { $controls[$kind + $suffix].Enabled = $enabled }
            $selected = $intervalValues[$controls[$kind + 'Interval'].SelectedIndex]
            $cadence = if ($selected -eq -1) { "matches widget: $base min (0 = manual)" } elseif ($selected -eq 0) { 'manual only' } else { "every $selected min · separate timer" }
            $controls[$kind + 'Status'].Text = (Get-SharingStatus $kind) + ' | Selected: ' + $cadence
        }
        $controls.Name.Enabled = $sharedOn -and $controls.WriteEnabled.Checked
        $controls.Account.Enabled = $sharedOn -and $controls.Layout.SelectedItem -eq 'Account picker'
        $controls.SourceStatus.Text = Get-SharingStatus Source
    }
    # Update the lock and connection controls immediately when their draft switches change.
    foreach ($key in @('SharedEnabled','WriteEnabled','ReadEnabled')) { $controls[$key].Add_CheckedChanged({ & $updateStatus }) }
    $controls.Layout.Add_SelectedIndexChanged({ & $updateStatus })
    $statusTimer.Add_Tick($updateStatus)
    & $updateStatus
    $statusTimer.Start()
    # Save validates before closing; Cancel and the title-bar X discard only unapplied drafts.
    $save.Add_Click({
        try { & $applySettings; $dialog.Close() }
        catch { [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Unable to save settings') }
    })
    $cancel.Add_Click({ $dialog.Close() })
    # A nested dispatcher keeps this draft's callbacks alive without disabling either widget window.
    Add-Type -AssemblyName WindowsFormsIntegration
    [Windows.Forms.Integration.WindowsFormsHost]::EnableWindowsFormsInterop()
    $settingsFrame = [Windows.Threading.DispatcherFrame]::new()
    $dialog.Add_FormClosed({ $settingsFrame.Continue = $false })
    $script:SettingsForm = $dialog
    try {
        $dialog.Show()
        Set-SettingsChoiceTheme $dialog $controls
        [Windows.Threading.Dispatcher]::PushFrame($settingsFrame)
    } finally {
        # Release all help and status resources when Settings or the application closes.
        $script:SettingsForm = $null
        $statusTimer.Stop(); $statusTimer.Dispose(); $settingsToolTip.Dispose(); $dialog.Dispose()
    }
}

function Update-SharingTimer {
    # Automatic matched writers also need a timer for their 30-minute check-in; manual writers stay idle.
    if (-not $script:SharingTimer) { return }
    $script:SharingTimer.Stop()
    if ($script:SharedEnabled -and (($script:WriteUsageEnabled -and ($script:WriteIntervalMinutes -gt 0 -or ($script:WriteIntervalMinutes -eq -1 -and $script:RefreshIntervalMinutes -gt 0))) -or ($script:ReadUsageEnabled -and $script:ReadIntervalMinutes -gt 0))) { $script:SharingTimer.Start() }
}

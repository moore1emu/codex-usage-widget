function New-SettingsChoice {
    param([string[]] $Choices, [string] $Selected)
    # Use native non-editable selectors so unsupported values cannot be entered.
    $control = [Windows.Forms.ComboBox]::new()
    $control.DropDownStyle = 'DropDownList'
    $control.Items.AddRange([object[]]$Choices)
    $control.SelectedItem = $Selected
    if ($control.SelectedIndex -lt 0) { $control.SelectedIndex = 0 }
    return $control
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

function Show-WidgetSettings {
    # Keep all settings in one native Windows dialog that follows the system app theme.
    $dialog = [Windows.Forms.Form]::new()
    $dialog.Text = "Codex Usage v$script:WidgetVersion · Settings"
    $dialog.ClientSize = [Drawing.Size]::new(600,655)
    $dialog.MinimumSize = [Drawing.Size]::new(540,640)
    $dialog.StartPosition = 'CenterScreen'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.TopMost = $true
    $tabs = [Windows.Forms.TabControl]::new()
    $tabs.Dock = 'Fill'
    $tables = @{}
    foreach ($name in @('General','Display','Sharing','Notifications')) {
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
    [void](Add-SettingsNote $tables.General 'Checks this computer''s Codex account. File timers use the latest available reading.')
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
    # Group layout, coordinated palettes, credit visibility, and reset appearance on Display.
    $controls.Layout = New-SettingsChoice @('Side by side','Stacked','Account picker') $script:AccountLayout
    Add-SettingsRow $tables.Display 'Account layout' $controls.Layout
    $controls.Account = New-SettingsChoice @('This computer','Other computer') $(if ($script:SelectedAccount -eq 'Remote') { 'Other computer' } else { 'This computer' })
    Add-SettingsRow $tables.Display 'Picker account' $controls.Account
    [void](Add-SettingsNote $tables.Display 'Enable Reading on Sharing to display two accounts. Side by side keeps two numeric columns at Mini size.')
    $controls.LocalScheme = New-SettingsChoice @($script:ColorSchemes.Keys) $script:LocalScheme
    $controls.RemoteScheme = New-SettingsChoice @($script:ColorSchemes.Keys) $script:RemoteScheme
    Add-SettingsRow $tables.Display 'This computer''s colors' $controls.LocalScheme
    Add-SettingsRow $tables.Display 'Other computer''s colors' $controls.RemoteScheme
    $controls.Credits = New-SettingsChoice @('When credits exist','Always show','Off') @{'Available'='When credits exist';'Always'='Always show';'Off'='Off'}[$script:CreditDisplayMode]
    Add-SettingsRow $tables.Display 'Credit display' $controls.Credits
    $controls.ResetHours = [Windows.Forms.NumericUpDown]::new()
    $controls.ResetHours.Maximum = 168
    $controls.ResetHours.Value = $script:PrimaryResetHours
    Add-SettingsRow $tables.Display '5-hour times: hours ahead' $controls.ResetHours
    [void](Add-SettingsNote $tables.Display '0 = off. Later reset times are estimates assuming immediate reuse.')
    $controls.WeeklyDate = [Windows.Forms.CheckBox]::new()
    $controls.WeeklyDate.Text = 'Show weekly reset date and time'
    $controls.WeeklyDate.AutoSize = $true
    $controls.WeeklyDate.Checked = $script:ShowWeeklyResetDate
    Add-SettingsRow $tables.Display '' $controls.WeeklyDate
    # Use independent writer and reader enable switches, paths, and frequency selectors.
    $controls.Name = [Windows.Forms.TextBox]::new()
    $controls.Name.MaxLength = 40
    $controls.Name.Text = $script:LocalDisplayName
    foreach ($kind in @('Write','Read')) {
        $enable = [Windows.Forms.CheckBox]::new()
        $enable.AutoSize = $true
        $enable.Text = if ($kind -eq 'Write') { 'Write my usage to JSON' } else { 'Read the other computer''s JSON' }
        $enable.Checked = if ($kind -eq 'Write') { $script:WriteUsageEnabled } else { $script:ReadUsageEnabled }
        $controls[$kind + 'Enabled'] = $enable
        Add-SettingsRow $tables.Sharing '' $enable
        if ($kind -eq 'Write') { Add-SettingsRow $tables.Sharing 'My display name' $controls.Name }
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
        Add-SettingsRow $tables.Sharing $(if ($kind -eq 'Write') { 'Output file' } else { 'Input file' }) $path $browse
        $interval = if ($kind -eq 'Write') { $script:WriteIntervalMinutes } else { $script:ReadIntervalMinutes }
        $choice = New-SettingsChoice $intervalChoices $intervalChoices[$intervalValues.IndexOf($interval)]
        $controls[$kind + 'Interval'] = $choice
        Add-SettingsRow $tables.Sharing ($kind + ' frequency') $choice
        $controls[$kind + 'Status'] = Add-SettingsNote $tables.Sharing ''
    }
    $controls.SourceStatus = Add-SettingsNote $tables.Sharing ''
    [void](Add-SettingsNote $tables.Sharing 'Use different output files on the two computers. Keep shared usage outside the public widget project. Writing preserves the reading''s original update time.')
    # Keep alerts local even while displaying a remote account or both accounts together.
    [void](Add-SettingsNote $tables.Notifications 'Notifications apply to this computer''s account. 0 = off. Warnings appear once per threshold crossing.')
    foreach ($entry in @(@{Key='PrimaryAlert';Label='5-hour warning below %';Value=$script:PrimaryAlertThreshold},@{Key='SecondaryAlert';Label='Weekly warning below %';Value=$script:SecondaryAlertThreshold})) {
        $input = [Windows.Forms.NumericUpDown]::new()
        $input.Maximum = 100
        $input.Value = $entry.Value
        $controls[$entry.Key] = $input
        Add-SettingsRow $tables.Notifications $entry.Label $input
    }
    $controls.ResetAlert = [Windows.Forms.CheckBox]::new()
    $controls.ResetAlert.Text = 'Notify when the 5-hour window resets'
    $controls.ResetAlert.AutoSize = $true
    $controls.ResetAlert.Checked = $script:NotifyPrimaryReset
    Add-SettingsRow $tables.Notifications '' $controls.ResetAlert
    [void](Add-SettingsNote $tables.Notifications 'A reset notification requires weekly quota above 0%.')
    $footer = [Windows.Forms.FlowLayoutPanel]::new()
    $footer.Dock = 'Bottom'
    $footer.Height = 45
    $footer.FlowDirection = 'RightToLeft'
    $footer.Padding = [Windows.Forms.Padding]::new(8)
    $save = [Windows.Forms.Button]::new()
    $save.Text = 'Save'
    $save.DialogResult = 'OK'
    $cancel = [Windows.Forms.Button]::new()
    $cancel.Text = 'Cancel'
    $cancel.DialogResult = 'Cancel'
    [void]$footer.Controls.Add($save)
    [void]$footer.Controls.Add($cancel)
    [void]$dialog.Controls.Add($tabs)
    [void]$dialog.Controls.Add($footer)
    $dialog.AcceptButton = $save
    $dialog.CancelButton = $cancel
    $statusTimer = [Windows.Forms.Timer]::new()
    $statusTimer.Interval = 1000
    $updateStatus = {
        # Show draft cadence alongside live operation status while the dialog is open.
        $base = @(1,5,15,30,0)[$controls.Refresh.SelectedIndex]
        foreach ($kind in @('Write','Read')) {
            $enabled = $controls[$kind + 'Enabled'].Checked
            foreach ($suffix in @('Path','Browse','Interval')) { $controls[$kind + $suffix].Enabled = $enabled }
            $selected = $intervalValues[$controls[$kind + 'Interval'].SelectedIndex]
            $cadence = if ($selected -eq -1) { "matches widget: $base min (0 = manual)" } elseif ($selected -eq 0) { 'manual only' } else { "every $selected min · separate timer" }
            $controls[$kind + 'Status'].Text = (Get-SharingStatus $kind) + ' | Selected: ' + $cadence
        }
        $controls.Name.Enabled = $controls.WriteEnabled.Checked
        $controls.Account.Enabled = $controls.Layout.SelectedItem -eq 'Account picker'
        $controls.SourceStatus.Text = Get-SharingStatus Source
    }
    $statusTimer.Add_Tick($updateStatus)
    & $updateStatus
    $statusTimer.Start()
    try {
        while ($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK) {
            try {
                # Validate all sharing paths before changing any persistent setting.
                $output = if ($controls.WriteEnabled.Checked) { Resolve-UsageFilePath $controls.WritePath.Text } else { $controls.WritePath.Text.Trim() }
                $inputPath = if ($controls.ReadEnabled.Checked) { Resolve-UsageFilePath $controls.ReadPath.Text } else { $controls.ReadPath.Text.Trim() }
                if ($controls.WriteEnabled.Checked -and $controls.ReadEnabled.Checked -and $output -eq $inputPath) { throw 'Input and output must be different files.' }
                if ($controls.WriteEnabled.Checked -and -not [IO.Directory]::Exists([IO.Path]::GetDirectoryName($output))) { throw 'Choose an existing private output folder.' }
                $name = ($controls.Name.Text -replace '[\p{C}]','').Trim()
                if (-not $name) { $name = 'This computer' }
                if ((Get-LaunchAtSignIn) -ne $controls.Startup.Checked) { Set-LaunchAtSignIn $controls.Startup.Checked }
                # Reset imported values only when the source path changes, never on temporary sync errors.
                if ($script:UsageInputPath -ne $inputPath) { $script:RemoteUsage = $null; $script:RemoteDisplayName = 'Other computer'; $script:ReadError = $null; $script:LastReadAt = $null }
                if ($script:UsageOutputPath -ne $output) { $script:LastWrittenFetchedAt = 0; $script:LastWrittenAt = $null; $script:WriteError = $null }
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
                Save-WarningState
                Save-WidgetState
                break
            } catch {
                # Keep draft choices available for correction instead of silently discarding them.
                [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Unable to save settings')
                $dialog.DialogResult = 'None'
            }
        }
    } finally { $statusTimer.Stop(); $statusTimer.Dispose(); $dialog.Dispose() }
}

function Update-SharingTimer {
    # Keep file polling idle when both sharing directions are disabled or manual/matched only.
    if (-not $script:SharingTimer) { return }
    $script:SharingTimer.Stop()
    if (($script:WriteUsageEnabled -and $script:WriteIntervalMinutes -gt 0) -or ($script:ReadUsageEnabled -and $script:ReadIntervalMinutes -gt 0)) { $script:SharingTimer.Start() }
}

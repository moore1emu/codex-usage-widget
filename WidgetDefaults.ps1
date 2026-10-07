# Keep General defaults separate from custom account values so overrides survive inheritance.
$script:GeneralDefaults = @{Refresh=5;ResetHours=25;WeeklyDate=$true;PrimaryAlert=0;SecondaryAlert=0;ResetAlert=$false;Credits='Available'}
$script:AccountDefaultGroups = @{Refresh=@('Refresh');Reset=@('ResetHours','WeeklyDate');Notifications=@('PrimaryAlert','SecondaryAlert','ResetAlert');Credits=@('Credits')}
# Map common preferences onto each provider's established settings without mixing connection details.
$script:AccountDefaultTargets = @{
    Local=@{Refresh='RefreshIntervalMinutes';ResetHours='PrimaryResetHours';WeeklyDate='ShowWeeklyResetDate';PrimaryAlert='PrimaryAlertThreshold';SecondaryAlert='SecondaryAlertThreshold';ResetAlert='NotifyPrimaryReset';Credits='CreditDisplayMode'}
    Remote=@{Refresh='ReadIntervalMinutes';ResetHours='SharedPrimaryResetHours';WeeklyDate='SharedShowWeeklyResetDate';PrimaryAlert='SharedPrimaryAlertThreshold';SecondaryAlert='SharedSecondaryAlertThreshold';ResetAlert='SharedNotifyPrimaryReset';Credits='SharedCreditDisplayMode'}
    Claude=@{Refresh='Interval';ResetHours='ResetHours';WeeklyDate='WeeklyDate';PrimaryAlert='PrimaryAlert';SecondaryAlert='SecondaryAlert';ResetAlert='ResetAlert'}
    SharedClaude=@{Refresh='ReadInterval';ResetHours='ResetHours';WeeklyDate='WeeklyDate';PrimaryAlert='PrimaryAlert';SecondaryAlert='SecondaryAlert';ResetAlert='ResetAlert'}
}
$script:AccountCustomSettings=@{}
$script:AccountUseDefaults=@{}

function Get-AccountDefaultTarget {
    param([string]$Account,[string]$Key)
    # Claude preferences remain inside their own option objects; Codex uses existing script variables.
    $target=$script:AccountDefaultTargets[$Account][$Key]
    if ($Account -eq 'Claude') { return $script:ClaudeOptions[$target] }
    if ($Account -eq 'SharedClaude') { return $script:SharedClaudeOptions[$target] }
    return (Get-Variable -Scope Script -Name $target -ValueOnly)
}

function Test-DefaultPreference {
    param([string]$Key,$Value,[switch]$AllowMatchedRefresh)
    # Validate persisted choices before they can change polling or notification behavior.
    switch ($Key) {
        Refresh { return ($Value -is [int] -or $Value -is [long]) -and ($Value -in @(0,1,5,15,30) -or ($AllowMatchedRefresh -and $Value -eq -1)) }
        ResetHours { return ($Value -is [int] -or $Value -is [long]) -and $Value -ge 0 -and $Value -le 168 }
        {$_ -in @('PrimaryAlert','SecondaryAlert')} { return ($Value -is [int] -or $Value -is [long]) -and $Value -ge 0 -and $Value -le 100 }
        {$_ -in @('WeeklyDate','ResetAlert')} { return $Value -is [bool] }
        Credits { return $Value -in @('Available','Always','Off') }
    }
    return $false
}

function Initialize-AccountDefaults {
    param($State)
    # Migrate existing installations with inheritance off, preserving their current account choices.
    foreach ($key in @($script:GeneralDefaults.Keys)) {
        if (Test-DefaultPreference $key $State.generalDefaults.$key) {
            # JSON integers are Int64; normalize numeric choices before dropdown lookup.
            $script:GeneralDefaults[$key]=if ($key -in @('Refresh','ResetHours','PrimaryAlert','SecondaryAlert')) {[int]$State.generalDefaults.$key} else {$State.generalDefaults.$key}
        }
    }
    foreach ($account in $script:AccountDefaultTargets.Keys) {
        $script:AccountCustomSettings[$account]=@{}
        $script:AccountUseDefaults[$account]=@{Refresh=$false;Reset=$false;Notifications=$false;Credits=$false}
        foreach ($key in $script:AccountDefaultTargets[$account].Keys) {
            $value=Get-AccountDefaultTarget $account $key
            $saved=$State.accountDefaultPreferences.$account.Custom.$key
            if (Test-DefaultPreference $key $saved -AllowMatchedRefresh:($account -in @('Remote','SharedClaude'))) { $value=$saved }
            $script:AccountCustomSettings[$account][$key]=if ($key -in @('Refresh','ResetHours','PrimaryAlert','SecondaryAlert')) {[int]$value} else {$value}
        }
        foreach ($group in $script:AccountDefaultGroups.Keys) {
            $saved=$State.accountDefaultPreferences.$account.Use.$group
            if ($saved -is [bool]) { $script:AccountUseDefaults[$account][$group]=$saved }
        }
    }
    Set-EffectiveAccountDefaults
}

function Set-EffectiveAccountDefaults {
    # Resolve inheritance only at startup/Apply, leaving quota data, names and palettes untouched.
    foreach ($account in $script:AccountDefaultTargets.Keys) {
        foreach ($group in $script:AccountDefaultGroups.Keys) {
            foreach ($key in $script:AccountDefaultGroups[$group]) {
                if (-not $script:AccountDefaultTargets[$account].ContainsKey($key)) { continue }
                $value=if ($script:AccountUseDefaults[$account][$group]) {$script:GeneralDefaults[$key]} else {$script:AccountCustomSettings[$account][$key]}
                $target=$script:AccountDefaultTargets[$account][$key]
                if ($account -eq 'Claude') { $script:ClaudeOptions[$target]=$value }
                elseif ($account -eq 'SharedClaude') { $script:SharedClaudeOptions[$target]=$value }
                else { Set-Variable -Scope Script -Name $target -Value $value }
            }
        }
    }
}

function Get-AccountDefaultState {
    # Serialize custom values separately from currently effective values.
    $saved=@{}
    foreach ($account in $script:AccountDefaultTargets.Keys) { $saved[$account]=@{Custom=$script:AccountCustomSettings[$account];Use=$script:AccountUseDefaults[$account]} }
    return $saved
}

function Get-DefaultControlValue {
    param($Control,$Values)
    # Convert UI selections to the same typed values used by each account's existing settings.
    if ($Control -is [Windows.Forms.ComboBox]) { return $Values[$Control.SelectedIndex] }
    if ($Control -is [Windows.Forms.CheckBox]) { return [bool]$Control.Checked }
    return [int]$Control.Value
}

function Set-DefaultControlValue {
    param($Control,$Values,$Value)
    # Normalize restored JSON numbers to match the native dropdown option types.
    if ($Value -is [long]) { $Value=[int]$Value }
    # Reuse native controls when previewing inherited defaults or restoring an override.
    if ($Control -is [Windows.Forms.ComboBox]) { $Control.SelectedIndex=[array]::IndexOf($Values,$Value) }
    elseif ($Control -is [Windows.Forms.CheckBox]) { $Control.Checked=[bool]$Value }
    else { $Control.Value=[decimal]$Value }
}

function Add-GeneralDefaultsControls {
    param($Tables,$Controls,$ToolTip)
    $values=@{Refresh=@(1,5,15,30,0);Credits=@('Available','Always','Off')}
    # Put shared account defaults below the General window controls.
    foreach ($key in @('Refresh','Credits','ResetHours','WeeklyDate','PrimaryAlert','SecondaryAlert','ResetAlert')) {
        $value=$script:GeneralDefaults[$key]
        if ($key -eq 'Refresh') { $choices=@('Every 1 minute','Every 5 minutes','Every 15 minutes','Every 30 minutes','Manual only');$control=New-SettingsChoice $choices $choices[[array]::IndexOf($values.Refresh,$value)] }
        elseif ($key -eq 'Credits') { $choices=@('When credits exist','Always show','Off');$control=New-SettingsChoice $choices $choices[[array]::IndexOf($values.Credits,$value)] }
        elseif ($value -is [bool]) { $control=[Windows.Forms.CheckBox]::new();$control.AutoSize=$true;$control.Checked=$value }
        else { $control=[Windows.Forms.NumericUpDown]::new();$control.Maximum=if ($key -eq 'ResetHours') {168} else {100};$control.Value=$value }
        $label=switch ($key) {Refresh {'Default refresh'} Credits {'Default Codex credits'} ResetHours {'5-hour times: hours ahead'} WeeklyDate {'Show weekly reset date and time'} PrimaryAlert {'5-hour warning below %'} SecondaryAlert {'Weekly warning below %'} ResetAlert {'Notify when the 5-hour window resets'}}
        $Controls['Default'+$key]=$control
        if ($control -is [Windows.Forms.CheckBox]) {$control.Text=$label;Add-SettingsRow $Tables.Defaults '' $control}
        else {Add-SettingsRow $Tables.Defaults $label $control}
        Set-SettingsHelp $ToolTip $control 'Used by accounts whose top Use General defaults switch is checked. Colors and connection paths stay independent.'
    }
    # Connect each account group to its existing control keys, keeping all provider logic intact.
    $maps=@{
        Local=@{Table='General';Refresh='Refresh';Credits='Credits';ResetHours='ResetHours';WeeklyDate='WeeklyDate';PrimaryAlert='PrimaryAlert';SecondaryAlert='SecondaryAlert';ResetAlert='ResetAlert'}
        Remote=@{Table='Shared';Refresh='ReadInterval';Credits='SharedCredits';ResetHours='SharedResetHours';WeeklyDate='SharedWeeklyDate';PrimaryAlert='SharedPrimaryAlert';SecondaryAlert='SharedSecondaryAlert';ResetAlert='SharedResetAlert'}
        Claude=@{Table='Claude';Refresh='ClaudeInterval';ResetHours='ClaudeResetHours';WeeklyDate='ClaudeWeeklyDate';PrimaryAlert='ClaudePrimaryAlert';SecondaryAlert='ClaudeSecondaryAlert';ResetAlert='ClaudeResetAlert'}
        SharedClaude=@{Table='Shared Claude';Refresh='SharedClaudeReadInterval';ResetHours='SharedClaudeResetHours';WeeklyDate='SharedClaudeWeeklyDate';PrimaryAlert='SharedClaudePrimaryAlert';SecondaryAlert='SharedClaudeSecondaryAlert';ResetAlert='SharedClaudeResetAlert'}
    }
    $bindings=@{}
    foreach ($account in $maps.Keys) {
        $bindings[$account]=@{}
        foreach ($group in @('Refresh','Reset','Notifications','Credits')) {
            if ($group -eq 'Credits' -and $account -in @('Claude','SharedClaude')) {continue}
            $check=[Windows.Forms.CheckBox]::new();$check.Text='Use General defaults: '+$group;$check.AutoSize=$true;$check.Checked=$script:AccountUseDefaults[$account][$group]
            $Controls[$account+'Use'+$group]=$check
            $entry=@{Check=$check;Items=@{};Custom=@{};Previous=$false}
            foreach ($key in $script:AccountDefaultGroups[$group]) {
                $control=$Controls[$maps[$account][$key]]
                $options=if ($key -eq 'Refresh' -and $account -in @('Remote','SharedClaude')) {@(-1,1,5,15,30,0)} else {$values[$key]}
                $entry.Items[$key]=@{Control=$control;Values=$options}
                $entry.Custom[$key]=$script:AccountCustomSettings[$account][$key]
                Set-DefaultControlValue $control $options $entry.Custom[$key]
            }
            # Keep legacy group flags internally so existing partial inheritance migrates safely.
            # One visible account switch replaces the repeated group controls.
            $check.Visible=$false
            $bindings[$account][$group]=$entry
        }
        # Insert the single defaults switch just below the account's enable switch.
        $master=[Windows.Forms.CheckBox]::new()
        $master.Text='Use General defaults';$master.AutoSize=$true
        $master.Tag=@{Entries=$bindings[$account];Updating=$false}
        $inherited=@($bindings[$account].Values | Where-Object {$_.Check.Checked}).Count
        $master.CheckState=if ($inherited -eq $bindings[$account].Count) {'Checked'} elseif ($inherited -eq 0) {'Unchecked'} else {'Indeterminate'}
        $master.Add_CheckedChanged({
            param($sender,$eventArgs)
            if ($sender.Tag.Updating) {return}
            # Apply this single choice to every supported setting group while retaining custom values.
            $sender.Tag.Updating=$true
            try {foreach ($entry in $sender.Tag.Entries.Values) {$entry.Check.Checked=$sender.Checked}}
            finally {$sender.Tag.Updating=$false}
        })
        $Controls[$account+'UseDefaults']=$master
        $table=$Tables[$maps[$account].Table]
        foreach ($control in @($table.Controls)) {if ($table.GetRow($control) -ge 1) {$table.SetRow($control,$table.GetRow($control)+1)}}
        $table.RowCount++;$table.RowStyles.Insert(1,[Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize))
        $table.Controls.Add($master,1,1);$table.SetColumnSpan($master,2)
        Set-SettingsHelp $ToolTip $master 'Use General refresh, reset details, notifications and Codex credit defaults for this account. Uncheck to restore manual settings. Colors and JSON connections remain independent. A mixed mark preserves earlier partial inheritance until you change this switch.'
    }
    return $bindings
}

function Update-DefaultsControls {
    param($Controls,$Bindings)
    # Match the existing master locks and never alter a native dropdown while it is open.
    foreach ($account in $Bindings.Keys) {
        $enabled=switch ($account) {Local {$Controls.LocalEnabled.Checked} Remote {$Controls.SharedEnabled.Checked} Claude {$Controls.ClaudeEnabled.Checked} SharedClaude {$Controls.SharedClaudeEnabled.Checked}}
        foreach ($group in $Bindings[$account].Keys) {
            $entry=$Bindings[$account][$group];$inherit=$entry.Check.Checked
            $entry.Check.Enabled=$enabled
            # A reader's custom cadence remains locked while that file connection is disabled.
            $groupEnabled=$enabled
            if ($group -eq 'Refresh' -and $account -eq 'Remote') { $groupEnabled=$enabled -and $Controls.ReadEnabled.Checked }
            if ($group -eq 'Refresh' -and $account -eq 'SharedClaude') { $groupEnabled=$enabled -and $Controls.SharedClaudeReadEnabled.Checked }
            foreach ($key in $entry.Items.Keys) {
                $item=$entry.Items[$key]
                if ($inherit -and -not $entry.Previous) { $entry.Custom[$key]=Get-DefaultControlValue $item.Control $item.Values }
                if ($inherit) {
                    $generalOptions=if ($key -eq 'Refresh') {@(1,5,15,30,0)} elseif ($key -eq 'Credits') {@('Available','Always','Off')} else {$null}
                    $value=Get-DefaultControlValue $Controls['Default'+$key] $generalOptions
                    Set-DefaultControlValue $item.Control $item.Values $value
                } elseif ($entry.Previous) { Set-DefaultControlValue $item.Control $item.Values $entry.Custom[$key] }
                $item.Control.Enabled=$groupEnabled -and -not $inherit
            }
            $entry.Previous=$inherit
        }
        # Reflect migrated partial choices without generating another round of checkbox events.
        $master=$Controls[$account+'UseDefaults']
        $master.Enabled=$enabled
        if (-not $master.Tag.Updating) {
            $inherited=@($Bindings[$account].Values | Where-Object {$_.Check.Checked}).Count
            $state=if ($inherited -eq $Bindings[$account].Count) {'Checked'} elseif ($inherited -eq 0) {'Unchecked'} else {'Indeterminate'}
            $master.Tag.Updating=$true
            try {$master.CheckState=$state} finally {$master.Tag.Updating=$false}
        }
    }
}

function Save-DefaultsDraft {
    param($Controls,$Bindings)
    # Commit defaults and custom overrides only after the dialog's existing path validation succeeds.
    foreach ($key in @($script:GeneralDefaults.Keys)) {
        $values=if ($key -eq 'Refresh') {@(1,5,15,30,0)} elseif ($key -eq 'Credits') {@('Available','Always','Off')} else {$null}
        $script:GeneralDefaults[$key]=Get-DefaultControlValue $Controls['Default'+$key] $values
    }
    foreach ($account in $Bindings.Keys) {
        foreach ($group in $Bindings[$account].Keys) {
            $entry=$Bindings[$account][$group]
            $script:AccountUseDefaults[$account][$group]=$entry.Check.Checked
            foreach ($key in $entry.Items.Keys) {
                $item=$entry.Items[$key]
                $script:AccountCustomSettings[$account][$key]=if ($entry.Check.Checked) {$entry.Custom[$key]} else {Get-DefaultControlValue $item.Control $item.Values}
            }
        }
    }
    Set-EffectiveAccountDefaults
}

# Verify inheritance using isolated controls, preferences and example account readings.
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
try {
    # Existing installations must retain all custom choices until inheritance is explicitly enabled.
    foreach ($account in $script:AccountUseDefaults.Keys) {
        foreach ($enabled in $script:AccountUseDefaults[$account].Values) { if ($enabled) { throw 'Migration enabled inheritance without a choice.' } }
    }
    # Reopen untouched JSON-loaded dropdowns and Apply without converting the saved intervals to Manual.
    $numericState=@{generalDefaults=@{Refresh=1};accountDefaultPreferences=@{Local=@{Custom=@{Refresh=5}};Claude=@{Custom=@{Refresh=1}}}} | ConvertTo-Json -Depth 8 | ConvertFrom-Json
    Initialize-AccountDefaults $numericState
    $numericSettings=[IO.File]::ReadAllText((Join-Path $script:TestProject 'WidgetSettings.ps1'))
    $numericSettings=$numericSettings.Replace('[Windows.Threading.Dispatcher]::PushFrame($settingsFrame)',@'
    try {
        if ($controls.DefaultRefresh.SelectedIndex -ne 0 -or $controls.Refresh.SelectedIndex -ne 1 -or $controls.ClaudeInterval.SelectedIndex -ne 0) {throw 'JSON integer widths restored refresh dropdowns to Manual.'}
        & $applySettings
        if ($script:GeneralDefaults.Refresh -ne 1 -or $script:RefreshIntervalMinutes -ne 5 -or $script:ClaudeOptions.Interval -ne 1) {throw 'Untouched Apply changed numeric refresh settings.'}
        # One account switch changes every supported group and exposes no individual inheritance controls.
        $controls.LocalUseDefaults.Checked=$true
        & $updateStatus
        if (@($defaultsBindings.Local.Values | Where-Object {-not $_.Check.Checked}).Count -or
            @($tables.General.Controls | Where-Object {$_.Text -like 'Use General defaults:*'}).Count) {throw 'The account-wide defaults switch did not replace group switches.'}
        $controls.LocalUseDefaults.Checked=$false
        & $updateStatus
        if ($controls.Refresh.SelectedIndex -ne 1) {throw 'The account-wide switch lost the saved custom refresh.'}
        # Source export controls belong to source tabs, even with both shared sources disabled.
        if ($controls.WritePath.Parent -ne $tables.General -or $controls.SharedClaudeWritePath.Parent -ne $tables.Claude -or
            $controls.ReadPath.Parent -ne $tables.Shared -or $controls.SharedClaudeReadPath.Parent -ne $tables['Shared Claude']) {throw 'Export/import controls are on the wrong account tabs.'}
        $controls.ClaudeEnabled.Checked=$true;$controls.SharedClaudeEnabled.Checked=$false
        & $updateStatus
        if (-not $controls.SharedClaudeWriteEnabled.Enabled) {throw 'Claude-only exporter remains locked behind shared Claude.'}
    } finally {$dialog.Close()}
'@)
    Invoke-Expression $numericSettings
    Show-WidgetSettings
    Initialize-AccountDefaults (Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json)
    if ($script:GeneralDefaults.Refresh -ne 1 -or $script:RefreshIntervalMinutes -ne 5 -or $script:ClaudeOptions.Interval -ne 1) {throw 'Restart changed saved refresh intervals.'}
    $script:GeneralDefaults.Refresh=15
    $script:GeneralDefaults.ResetHours=10
    $script:GeneralDefaults.PrimaryAlert=12
    $script:AccountCustomSettings.Local.Refresh=1
    $script:AccountCustomSettings.Claude.ResetHours=50
    $script:AccountUseDefaults.Local.Refresh=$true
    $script:AccountUseDefaults.Claude.Reset=$true
    $script:AccountUseDefaults.SharedClaude.Notifications=$true
    $originalPalette=$script:ClaudeOptions.Scheme
    Set-EffectiveAccountDefaults
    if ($script:RefreshIntervalMinutes -ne 15 -or $script:ClaudeOptions.ResetHours -ne 10 -or $script:SharedClaudeOptions.PrimaryAlert -ne 12 -or $script:ClaudeOptions.Scheme -ne $originalPalette) { throw 'Effective defaults did not remain independent of palettes.' }
    # Disabling one group restores its custom value while other inherited groups remain active.
    $script:AccountUseDefaults.Claude.Reset=$false
    Set-EffectiveAccountDefaults
    if ($script:ClaudeOptions.ResetHours -ne 50 -or $script:RefreshIntervalMinutes -ne 15) { throw 'Custom override was lost when disabling inheritance.' }
    $window.Show();$window.UpdateLayout();Save-WidgetState
    $saved=Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    Initialize-AccountDefaults $saved
    if ($script:AccountCustomSettings.Local.Refresh -ne 1 -or -not $script:AccountUseDefaults.Local.Refresh -or $script:RefreshIntervalMinutes -ne 15) { throw 'Restart lost custom values or inheritance flags.' }
    # Direct tray refresh selections explicitly override General without altering another provider.
    Set-RefreshInterval -Minutes 5
    if ($script:AccountUseDefaults.Local.Refresh -or $script:AccountCustomSettings.Local.Refresh -ne 5 -or $script:SharedClaudeOptions.PrimaryAlert -ne 12) { throw 'Direct refresh override changed unrelated defaults.' }
    # Drive the real settings draft without entering a permanent UI dispatcher or querying services.
    $settings=[IO.File]::ReadAllText((Join-Path $script:TestProject 'WidgetSettings.ps1'))
    $settings=$settings.Replace('[Windows.Threading.Dispatcher]::PushFrame($settingsFrame)',@'
    try {
        if (($tabs.TabPages.Text -join ',') -ne 'General,Codex,Shared Codex,Claude,Shared Claude') { throw 'General/provider tab names changed.' }
        # Stable inherited locks must never toggle twice during a status tick and cause flashing.
        $controls.SharedEnabled.Checked=$true;$controls.ReadEnabled.Checked=$true
        $controls.RemoteUseRefresh.Checked=$true
        & $updateStatus
        $script:DefaultLockTransitions=0
        $controls.ReadInterval.Add_EnabledChanged({$script:DefaultLockTransitions++})
        for ($tick=0;$tick -lt 4;$tick++) { & $updateStatus }
        if ($script:DefaultLockTransitions) {throw 'Status updates toggled an inherited shared control.'}
        $controls.RemoteUseRefresh.Checked=$false;$controls.ReadEnabled.Checked=$false;$controls.SharedEnabled.Checked=$false
        $controls.Refresh.SelectedIndex=0
        $controls.DefaultRefresh.SelectedIndex=2
        $controls.LocalUseRefresh.Checked=$true
        & $updateStatus
        if ($controls.Refresh.Enabled -or $controls.Refresh.SelectedIndex -ne 2) { throw 'Inherited refresh was not previewed and locked.' }
        $controls.LocalUseRefresh.Checked=$false
        & $updateStatus
        if (-not $controls.Refresh.Enabled -or $controls.Refresh.SelectedIndex -ne 0) { throw 'Unchecking inheritance did not restore the custom draft.' }
        $controls.LocalUseRefresh.Checked=$true
        $controls.ClaudeEnabled.Checked=$true
        $controls.ClaudeUseReset.Checked=$true
        $controls.DefaultResetHours.Value=25
        & $updateStatus
        & $applySettings
        if ($script:RefreshIntervalMinutes -ne 15 -or $script:AccountCustomSettings.Local.Refresh -ne 1 -or $script:ClaudeOptions.ResetHours -ne 25) { throw 'Apply did not save defaults and custom overrides independently.' }
        $controls.DefaultResetHours.Value=75
        & $updateStatus
        # Closing without another Apply must discard this remaining draft.
    } finally { $dialog.Close() }
'@)
    Invoke-Expression $settings
    Show-WidgetSettings
    if ($script:GeneralDefaults.ResetHours -ne 25 -or $script:ClaudeOptions.ResetHours -ne 25) { throw 'Cancel committed unapplied defaults.' }
    Write-Output 'PASS: default migration, independent groups/colors, override restoration, restart persistence, tray refresh override, Apply and Cancel.'
} finally { Close-TestWidget }

# Keep native settings lists open across status ticks using isolated state and example accounts.
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
$script:SharedEnabled=$true; $script:WriteUsageEnabled=$true; $script:ReadUsageEnabled=$true
$script:AccountLayout='Account picker'
$settings=[IO.File]::ReadAllText((Join-Path $script:TestProject 'WidgetSettings.ps1'))
# Keep the real status timer and message loop; add only a bounded interaction driver.
$settings=$settings.Replace('[Windows.Threading.Dispatcher]::PushFrame($settingsFrame)',@'
$dropdownTimer=[Windows.Forms.Timer]::new()
$dropdownTimer.Interval=1400
# Unlock draft-only Claude choices without enabling a live connection or applying settings.
$controls.ClaudeEnabled.Checked=$true;$controls.ClaudePlacement.SelectedItem='Separate window'
$controls.SharedClaudeEnabled.Checked=$true;$controls.SharedClaudeReadEnabled.Checked=$true;$controls.SharedClaudeWriteEnabled.Checked=$true
$controls.SharedClaudePlacement.SelectedItem='Separate window'
$script:DropdownChoices=@('Refresh','Size','Position','LocalScheme','Credits','Layout','RemoteScheme','WriteInterval','ReadInterval','Account','ClaudePlacement','ClaudeSize','ClaudeScheme','ClaudeInterval','SharedClaudePlacement','SharedClaudeSize','SharedClaudeScheme','SharedClaudeReadInterval','SharedClaudeWriteInterval')
$script:DropdownIndex=0
$script:OpenDropdownKey=$null
$dropdownTimer.Add_Tick({
    try {
        if ($script:OpenDropdownKey) {
            # The actual one-second callback must preserve both the open list and the draft value.
            $choice=$controls[$script:OpenDropdownKey]
            if (-not $choice.DroppedDown -or $choice.SelectedIndex -ne $script:DropdownSelection) { throw ('Status tick interrupted ' + $script:OpenDropdownKey) }
            $choice.DroppedDown=$false
        }
        if ($script:DropdownIndex -ge $script:DropdownChoices.Count) {
            # Imported names wait until a list closes, then catch up without switching accounts.
            $controls.Account.SelectedIndex=1; $controls.Account.DroppedDown=$true
            $script:RemoteDisplayName='Renamed example shared account'
            & $updateStatus
            if (-not $controls.Account.DroppedDown -or $controls.Account.Items[1] -eq $script:RemoteDisplayName) { throw 'Nickname update changed an open account list.' }
            $controls.Account.DroppedDown=$false; & $updateStatus
            if ($controls.Account.Items[1] -ne $script:RemoteDisplayName -or $controls.Account.SelectedIndex -ne 1) { throw 'Nickname update did not resume after closing the list.' }
            # Draft switches still lock and unlock settings promptly when no list is open.
            $controls.SharedEnabled.Checked=$false
            if ($controls.RemoteScheme.Enabled -or -not $controls.SharedEnabled.Enabled) { throw 'Shared lock failed.' }
            $controls.SharedEnabled.Checked=$true
            if (-not $controls.RemoteScheme.Enabled) { throw 'Shared unlock failed.' }
            $dropdownTimer.Stop(); $cancel.PerformClick(); return
        }
        # Open each real General and Shared dropdown and invoke an immediate status callback too.
        $key=$script:DropdownChoices[$script:DropdownIndex++]
        $choice=$controls[$key]
        $tabs.SelectedTab=$choice.Parent.Parent
        # Complete tab scrolling before opening the native popup; hidden rows otherwise close it later.
        $choice.Parent.Parent.ScrollControlIntoView($choice)
        $dialog.PerformLayout()
        [Windows.Forms.Application]::DoEvents()
        [void]$choice.Focus()
        [Windows.Forms.Application]::DoEvents()
        $script:DropdownSelection=$choice.SelectedIndex
        $choice.DroppedDown=$true
        & $updateStatus
        if (-not $choice.DroppedDown) { throw ('Status callback closed ' + $key) }
        $script:OpenDropdownKey=$key
    } catch {
        # Relay asynchronous failures after closing the modeless dialog instead of hanging the suite.
        $script:DropdownFailure=$_; $dropdownTimer.Stop(); $dialog.Close()
    }
})
$dropdownTimer.Start()
try { [Windows.Threading.Dispatcher]::PushFrame($settingsFrame) } finally { $dropdownTimer.Dispose() }
'@)
Invoke-Expression $settings
try {
    Show-WidgetSettings
    if ($script:DropdownFailure) { throw $script:DropdownFailure }
    Write-Output 'PASS: General/Shared dropdowns and draft selections survive status ticks; nicknames and locks resume after closing.'
} finally { Close-TestWidget }

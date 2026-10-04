# Exercise actual account rendering without accessing a live Claude or Codex session.
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
function Assert-ClaudePointer {
    param($Target,$Control)
    # Verify real hit targets, rather than raising click events underneath an intercepting card.
    $point=$Control.TranslatePoint([Windows.Point]::new($Control.ActualWidth/2,$Control.ActualHeight/2),$Target)
    $hit=$Target.InputHitTest($point)
    while ($hit -is [Windows.Media.Visual]) {
        if ([object]::ReferenceEquals($hit,$Control)) {return}
        $hit=[Windows.Media.VisualTreeHelper]::GetParent($hit)
    }
    throw ('Claude pointer target blocked: '+$Control.Name)
}
try {
    # Missing limits remain unknown; malformed data must never overwrite a valid reading.
    $missing=ConvertTo-ClaudeUsage @{}
    if ($null -ne $missing.primary -or $null -ne $missing.secondary -or $null -ne $missing.credits) {throw 'Missing Claude quotas were fabricated.'}
    foreach ($value in @(-1,101,'invalid',[double]::NaN,[double]::PositiveInfinity)) {
        $rejected=$false
        try {[void](ConvertTo-ClaudeUsage @{five_hour=@{utilization=$value}})} catch {$rejected=$true}
        if (-not $rejected) {throw 'Invalid Claude utilization was accepted.'}
    }
    # Exercise JSON's automatic DateTime conversion and every supported timestamp representation.
    $instant = [DateTimeOffset]::Now.AddHours(2)
    $epoch = $instant.ToUnixTimeSeconds()
    $jsonDate = ('{"five_hour":{"utilization":20,"resets_at":"' + $instant.ToUniversalTime().ToString('o') + '"}}') | ConvertFrom-Json
    foreach ($resetValue in @($jsonDate.five_hour.resets_at,$instant,$instant.UtcDateTime,$instant.LocalDateTime,$instant.ToOffset([TimeSpan]::FromHours(-6)).ToString('o'),[DateTime]::SpecifyKind($instant.UtcDateTime,[DateTimeKind]::Unspecified))) {
        $converted = ConvertTo-ClaudeUsage @{five_hour=@{utilization=20;resets_at=$resetValue}}
        if ($converted.primary.resetsAt -ne $epoch) { throw 'Claude reset timezone changed during normalization.' }
        if ((Format-ResetCountdown $converted.primary.resetsAt) -like '*Resetting now*') { throw 'A future Claude reset was treated as expired.' }
    }
    # Pin the reported Denver 5 PM weekly case independently of the test computer timezone.
    $weekly = ConvertTo-ClaudeUsage ('{"seven_day":{"utilization":5,"resets_at":"2026-10-08T23:00:00Z"}}' | ConvertFrom-Json)
    $denver = [TimeZoneInfo]::FindSystemTimeZoneById('Mountain Standard Time')
    $localReset = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::FromUnixTimeSeconds($weekly.secondary.resetsAt),$denver)
    if ($localReset.Hour -ne 17 -or $localReset.Day -ne 8) { throw 'Claude weekly reset no longer maps to 5 PM in Denver.' }
    $script:ClaudeUsage=ConvertTo-ClaudeUsage @{five_hour=@{utilization=20;resets_at=[DateTimeOffset]::Now.AddHours(2).ToString('o')};seven_day=@{utilization=50;resets_at=[DateTimeOffset]::Now.AddDays(4).ToString('o')};extra_usage=@{monthly_limit=10000}}
    if ($script:ClaudeUsage.primary.usedPercent -ne 20 -or $script:ClaudeUsage.secondary.usedPercent -ne 50 -or $script:ClaudeUsage.credits) {throw 'Claude quotas or credit semantics changed.'}
    $script:SharedClaudeUsage=$script:ClaudeUsage
    $script:ClaudeOptions.Enabled=$true
    $script:SharedClaudeOptions.Enabled=$true;$script:SharedClaudeOptions.ReadEnabled=$true
    $script:SharedEnabled=$true;$script:ReadUsageEnabled=$true
    $window.Show();$window.UpdateLayout()
    # Credit-bearing Codex and credit-free Claude columns must share the weekly row position.
    $script:AccountLayout='Side by side'
    $script:CreditDisplayMode='Available';$script:SharedCreditDisplayMode='Available'
    Set-WidgetPreset 'Large / Default';$window.UpdateLayout();Update-Display;$window.UpdateLayout()
    $expectedY=$script:AccountCards.Local.Bindings.secondaryArea.TranslatePoint([Windows.Point]::new(0,0),$window).Y
    foreach ($key in @('Remote','Claude','SharedClaude')) {
        $actualY=$script:AccountCards[$key].Bindings.secondaryArea.TranslatePoint([Windows.Point]::new(0,0),$window).Y
        if ([Math]::Abs($actualY-$expectedY) -gt 1) { throw ("Weekly rows misaligned for " + $key + ": " + $actualY + " vs " + $expectedY) }
    }
    # Use the real tray menu handler to switch back from Claude, including shared-only Codex.
    Show-ClaudeWidget
    if ($script:SelectedAccount -ne 'Claude' -or $trayIcon.Text -notlike '*Claude*') { throw 'Opening Claude did not select its tray meters.' }
    $trayOpenItem.PerformClick()
    if ($script:SelectedAccount -ne 'Local' -or $trayIcon.Text -notlike ('*'+$script:LocalDisplayName+'*')) { throw 'Opening Codex did not restore its tray meters.' }
    $script:LocalEnabled=$false;Show-ClaudeWidget;$trayOpenItem.PerformClick()
    if ($script:SelectedAccount -ne 'Remote' -or $trayIcon.Text -notlike ('*'+$script:RemoteDisplayName+'*')) { throw 'Opening Codex did not select the enabled shared account.' }
    $script:LocalEnabled=$true
    # Disabling credits releases the blank row instead of retaining stale reservations.
    $script:CreditDisplayMode='Off';$script:SharedCreditDisplayMode='Off';Update-Display;$window.UpdateLayout()
    if ($script:AccountCards.Claude.Visual.Child.RowDefinitions[3].MinHeight -ne 0) { throw 'Hidden credits retained reserved space.' }
    $script:CreditDisplayMode='Available';$script:SharedCreditDisplayMode='Available'
    # Reproduce mixed side-by-side content at the widths from the reported screenshots.
    $script:SharedClaudeOptions.Enabled=$false
    $script:RemoteUsage.primary.usedPercent=0;$script:RemoteUsage.credits=$null
    $script:SharedCreditDisplayMode='Always'
    $script:PrimaryResetHours=10;$script:SharedPrimaryResetHours=25;$script:ClaudeOptions.ResetHours=5
    foreach ($connectedLayout in @('Side by side','Stacked')) {
    $script:AccountLayout=$connectedLayout
    $testBounds=if ($connectedLayout -eq 'Side by side') { @(@(470,330),@(420,285),@(375,265),@(300,160),@(225,85)) } else { @(@(166,916),@(148,781),@(134,721),@(109,430),@(84,229)) }
    foreach ($bounds in $testBounds) {
        $window.Width=$bounds[0];$window.Height=$bounds[1];$window.UpdateLayout();Update-Display;$window.UpdateLayout()
        $reference=$script:AccountCards.Local
        $mini=$reference.Bindings.ultraCompactPanel.Visibility -eq 'Visible'
        foreach ($key in @('Remote','Claude')) {
            $card=$script:AccountCards[$key]
            if (($card.Bindings.ultraCompactPanel.Visibility -eq 'Visible') -ne $mini) { throw ('Connected columns changed display modes independently at '+($bounds -join 'x')) }
            $controlsToCompare=if ($mini) {@('compactPrimaryPercent','compactSecondaryPercent')} else {@('primaryPercent','secondaryPercent','primaryBar','secondaryBar')}
            foreach ($controlName in $controlsToCompare) {
                $expected=$reference.Bindings[$controlName];$actual=$card.Bindings[$controlName]
                $expectedPoint=$expected.TranslatePoint([Windows.Point]::new(0,0),$reference.Container)
                $actualPoint=$actual.TranslatePoint([Windows.Point]::new(0,0),$card.Container)
                if ([Math]::Abs($actualPoint.Y-$expectedPoint.Y) -gt 1 -or $actual.Visibility -ne $expected.Visibility) { throw ('Connected row drift: '+$key+' '+$controlName+' at '+($bounds -join 'x')) }
                if ($controlName -like '*Percent' -and $actual.FontSize -ne $expected.FontSize) { throw 'Connected percentages used different font sizes.' }
                if (-not $mini -and $controlName -like '*Percent' -and [Math]::Abs($actualPoint.X-$expectedPoint.X) -gt 1) { throw 'Connected value columns used different offsets.' }
            }
        }
        if ($mini -and $script:AccountCards.Claude.Bindings.compactCreditsPanel.Visibility -ne 'Hidden') { throw 'Claude did not retain an invisible credit slot.' }
    }
    }
    # Restore independent account choices before checking the remaining layouts.
    $script:SharedClaudeOptions.Enabled=$true;$script:SharedCreditDisplayMode='Available'
    $script:PrimaryResetHours=25;$script:SharedPrimaryResetHours=25;$script:ClaudeOptions.ResetHours=25
    # Wide, short connected cards automatically form stationary horizontal metric rows.
    $script:AccountLayout='Side by side';$window.Width=1100;$window.Height=100
    $window.UpdateLayout();Update-Display;$window.UpdateLayout()
    foreach ($key in @('Local','Remote','Claude','SharedClaude')) {
        $card=$script:AccountCards[$key]
        if ($card.Bindings.ultraCompactPanel.Child.ColumnDefinitions.Count -ne 3) { throw ('Horizontal metrics missing for '+$key) }
        $first=$card.Bindings.compactPrimaryPercent.TranslatePoint([Windows.Point]::new(0,0),$card.Container)
        $second=$card.Bindings.compactSecondaryPercent.TranslatePoint([Windows.Point]::new(0,0),$card.Container)
        $third=$card.Bindings.compactCreditsText.TranslatePoint([Windows.Point]::new(0,0),$card.Container)
        if ($first.X -ge $second.X -or $second.X -ge $third.X -or [Math]::Abs($first.Y-$second.Y) -gt 1 -or [Math]::Abs($first.Y-$third.Y) -gt 1) { throw ('Horizontal metrics failed to align for '+$key) }
    }
    # Narrowing restores vertical mini rows without retaining horizontal grid tracks.
    Set-WidgetPreset 'Mini';$window.UpdateLayout();Update-Display;$window.UpdateLayout()
    if ($script:AccountCards.Local.Bindings.ultraCompactPanel.Child.ColumnDefinitions.Count) { throw 'Horizontal layout did not revert after narrowing.' }
    # Every common layout must support all four sources and preserve distinct card names.
    foreach ($layout in @('Side by side','Stacked','Account picker','Separate windows')) {
        $script:AccountLayout=$layout
        foreach ($preset in @('Mini','Medium','Large / Default')) {
            Set-WidgetPreset $preset;$window.UpdateLayout();Update-Display;$window.UpdateLayout()
            if (@(Get-EnabledAccounts).Count -ne 4) {throw 'An enabled account disappeared.'}
            if ($script:AccountCards.Claude.Heading.Text -ne 'Claude' -or $script:AccountCards.SharedClaude.Heading.Text -ne 'Shared Claude') {throw 'Claude identity was lost.'}
            if ($script:AccountCards.Claude.Bindings.compactPrimaryPercent.Text -ne '80%') {throw 'Claude remaining quota was incorrect.'}
        }
    }
    # Both Claude shells retain usable hover actions and resize grips at the smallest size.
    foreach ($key in @('Claude','SharedClaude')) {
        $view=if ($key -eq 'Claude') {$script:ClaudeView} else {$script:SharedClaudeView}
        $view.Window.Width=72;$view.Window.Height=72;$view.Window.UpdateLayout()
        if ($key -eq 'Claude') {Update-ClaudeWindow;Invoke-ClaudeWindowAction {Update-HoverControls -IsPointerOver $true}}
        else {Update-SharedClaudeWindow;Invoke-SharedClaudeWindowAction {Update-HoverControls -IsPointerOver $true}}
        $view.Window.UpdateLayout()
        foreach ($name in @('hoverRefreshButton','hoverPinButton','hoverMinimizeButton','hoverCloseButton','leftResizeGrip','rightResizeGrip')) {
            if ($view.Bindings[$name].IsVisible) {Assert-ClaudePointer $view.Window $view.Bindings[$name]}
        }
    }
    # Disabled local Codex must collapse while shared Codex and local Claude remain visible.
    $script:AccountLayout='Side by side';$script:LocalEnabled=$false;$script:SharedClaudeOptions.Enabled=$false
    Update-Display;$window.UpdateLayout()
    if ((@(Get-EnabledAccounts) -join ',') -ne 'Remote,Claude' -or $script:AccountCards.Local.Container.Visibility -ne 'Collapsed') {throw 'Local Codex disable failed.'}
    # Independently detached Claude preserves its own geometry and hides without affecting its peers.
    $script:ClaudeOptions.Placement='Separate window';Update-Display
    Set-ClaudeWindowPreset 'Small'
    if ($script:ClaudeOptions.Bounds.width -ne 140 -or $script:ClaudeOptions.Bounds.height -ne 155) {throw 'Claude geometry was not saved.'}
    # Verify disk serialization retains nested bounds for restoration on the next launch.
    $savedState=Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    if ($savedState.claude.Bounds.width -ne 140 -or $savedState.claude.Bounds.height -ne 155 -or $savedState.localEnabled -ne $false) {throw 'Claude geometry or source switches were lost in persisted preferences.'}
    $script:ClaudeView.Window.Close()
    if ($script:ClaudeView.Window.IsVisible -or -not $window.IsVisible) {throw 'Closing Claude affected the main window.'}
    Show-ClaudeWidget
    if (-not $script:ClaudeView.Window.IsVisible) {throw 'Claude could not be reopened.'}
    # A disabled source ignores late network replies and cannot revive its stale display.
    $script:ClaudeOptions.Enabled=$false;$script:ClaudeRequestId='test-request'
    Receive-ClaudeUsage ([pscustomobject]@{Source='https://claude.ai/settings/usage';WebMessageAsJson='{"type":"widget-usage","request":"test-request","usage":{"five_hour":{"utilization":99}}}'})
    if ($script:ClaudeUsage.primary.usedPercent -ne 20) {throw 'A disabled Claude source accepted a response.'}
    Update-Display
    if ($script:ClaudeWindowActive -or $script:AccountCards.Claude.Container.Visibility -ne 'Collapsed') {throw 'Disabled Claude window remained visible.'}
    # Turning every source off leaves only the tray, then restoring a source restores its host.
    $script:SharedEnabled=$false;$script:ReadUsageEnabled=$false
    Update-Display
    if ($window.IsVisible) {throw 'Disabled sources left an empty desktop shell.'}
    $script:SharedEnabled=$true;$script:ReadUsageEnabled=$true
    Update-Display
    if (-not $window.IsVisible) {throw 'Re-enabling a source did not restore its host.'}
    Write-Output 'PASS: Claude quota validation, unknown plans, four-source layouts, independent geometry, close/restore and disabled-response isolation.'
} finally {Close-TestWidget}

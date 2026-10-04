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
    $script:ClaudeUsage=ConvertTo-ClaudeUsage @{five_hour=@{utilization=20;resets_at=[DateTimeOffset]::Now.AddHours(2).ToString('o')};seven_day=@{utilization=50;resets_at=[DateTimeOffset]::Now.AddDays(4).ToString('o')};extra_usage=@{monthly_limit=10000}}
    if ($script:ClaudeUsage.primary.usedPercent -ne 20 -or $script:ClaudeUsage.secondary.usedPercent -ne 50 -or $script:ClaudeUsage.credits) {throw 'Claude quotas or credit semantics changed.'}
    $script:SharedClaudeUsage=$script:ClaudeUsage
    $script:ClaudeOptions.Enabled=$true
    $script:SharedClaudeOptions.Enabled=$true;$script:SharedClaudeOptions.ReadEnabled=$true
    $script:SharedEnabled=$true;$script:ReadUsageEnabled=$true
    $window.Show();$window.UpdateLayout()
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

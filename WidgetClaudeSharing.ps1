# Use independent files and alert histories for the remote Claude subscription.
$script:SharedClaudeOptions=@{
    Enabled=$false
    ReadEnabled=$false
    WriteEnabled=$false
    InputPath=''
    OutputPath=''
    ReadInterval=-1
    WriteInterval=-1
    Name='Shared Claude'
    Scheme='Teal / lilac / sand'
    Placement='Follow layout'
    ResetHours=25
    WeeklyDate=$true
    PrimaryAlert=0
    SecondaryAlert=0
    ResetAlert=$false
    Bounds=$null
    SourceId=[guid]::NewGuid().ToString('N')
}
$script:SharedClaudeUsage=$null
$script:SharedClaudeStatus='Sharing is off'
$script:ClaudeFileState=@{
    PublishedTarget=''
    PublishedUsageKey=$null
    PublishedMetadataKey=$null
    PublishedCheckInReady=$false
    UsageChangedAt=0
    LastWrittenAt=$null
    WriteError=$null
    RemoteUsage=$null
    RemoteDisplayName='Shared Claude'
    RemoteSourceId=''
    RemoteRefreshMinutes=5
    RemoteCheckInMinutes=0
    RemoteUsageChangedAt=0
    ReadFileStamp=''
    LastReadAt=$null
    ReadError=$null
    SharedAlertStates=@{}
    SharedWarningSourceId=''
    LastSharedWarningState=$null
    NextWriteAt=[DateTimeOffset]::MinValue
    NextReadAt=[DateTimeOffset]::MinValue
}

function Restore-SharedClaudeSettings {
    param($State)
    # Validate remote configuration independently; missing settings never enable sharing.
    $saved=$State.sharedClaude
    if (-not $saved) {return}
    foreach ($key in @('Enabled','ReadEnabled','WriteEnabled','WeeklyDate','ResetAlert')) {if ($saved.$key -is [bool]) {$script:SharedClaudeOptions[$key]=$saved.$key}}
    foreach ($key in @('InputPath','OutputPath')) {if ($saved.$key -is [string]) {$script:SharedClaudeOptions[$key]=$saved.$key}}
    foreach ($key in @('ReadInterval','WriteInterval')) {if ($saved.$key -in @(-1,0,1,5,15,30)) {$script:SharedClaudeOptions[$key]=[int]$saved.$key}}
    foreach ($key in @('ResetHours','PrimaryAlert','SecondaryAlert')) {
        $max=if ($key -eq 'ResetHours') {168} else {100}
        if (($saved.$key -is [int] -or $saved.$key -is [long]) -and $saved.$key -ge 0 -and $saved.$key -le $max) {$script:SharedClaudeOptions[$key]=[int]$saved.$key}
    }
    if ($saved.SourceId -match '^[0-9a-f]{32}$') {$script:SharedClaudeOptions.SourceId=$saved.SourceId}
    if ($saved.Placement -in @('Follow layout','Attached','Separate window')) {$script:SharedClaudeOptions.Placement=$saved.Placement}
    if ($script:ColorSchemes.Contains([string]$saved.Scheme)) {$script:SharedClaudeOptions.Scheme=$saved.Scheme}
    $script:SharedClaudeOptions.Bounds=$saved.Bounds
    # Restore the standard source-aware warning format in Claude's own private state directory.
    Invoke-ClaudeFileContext {Initialize-SharedWarnings}
}

function Invoke-ClaudeFileContext {
    param([scriptblock]$Action)
    # Reuse atomic writing, validation, freshness and warning rules in a synchronous isolated context.
    $options=$script:SharedClaudeOptions
    $context=@{
        LocalEnabled=$script:ClaudeOptions.Enabled
        Usage=$script:ClaudeUsage
        UsageProvider='Claude'
        SuppressSharingDisplay=$true
        SharedEnabled=$options.Enabled
        WriteUsageEnabled=$options.WriteEnabled
        ReadUsageEnabled=$options.ReadEnabled
        UsageOutputPath=$options.OutputPath
        UsageInputPath=$options.InputPath
        SharingSourceId=$options.SourceId
        LocalDisplayName=$script:ClaudeOptions.Name
        RefreshIntervalMinutes=$script:ClaudeOptions.Interval
        WriteIntervalMinutes=$options.WriteInterval
        ReadIntervalMinutes=$(if ($options.ReadInterval -eq -1) {$script:ClaudeOptions.Interval} else {$options.ReadInterval})
        SharedPrimaryAlertThreshold=$options.PrimaryAlert
        SharedSecondaryAlertThreshold=$options.SecondaryAlert
        SharedNotifyPrimaryReset=$options.ResetAlert
        RefreshError=$(if ($script:ClaudeStatus -notlike 'Subscription*') {'Claude reading is not fresh'} else {$null})
        StateDirectory=(Join-Path $script:StateDirectory 'ClaudeSharing')
        SharedAlertStatePath=(Join-Path $script:StateDirectory 'ClaudeSharing/shared-warning-state.json')
    }
    foreach ($key in $script:ClaudeFileState.Keys) {$context[$key]=$script:ClaudeFileState[$key]}
    $original=@{}
    try {
        # Install only the explicit context fields; restore them even if file operations fail.
        foreach ($key in $context.Keys) {$original[$key]=Get-Variable -Scope Script -Name $key -ValueOnly -ErrorAction SilentlyContinue;Set-Variable -Scope Script -Name $key -Value $context[$key]}
        & $Action
    } finally {
        foreach ($key in @($script:ClaudeFileState.Keys)) {$script:ClaudeFileState[$key]=Get-Variable -Scope Script -Name $key -ValueOnly -ErrorAction SilentlyContinue}
        foreach ($key in $original.Keys) {Set-Variable -Scope Script -Name $key -Value $original[$key]}
    }
    $script:SharedClaudeUsage=$script:ClaudeFileState.RemoteUsage
    if ($script:SharedClaudeUsage) {$script:SharedClaudeOptions.Name=$script:ClaudeFileState.RemoteDisplayName}
}

function Invoke-ClaudeSharing {
    param([switch]$Force,[switch]$Fresh)
    # Manual connections run only on explicit refresh; automatic files share a lightweight timer.
    if (-not $script:SharedClaudeOptions.Enabled) {return}
    $options=$script:SharedClaudeOptions
    Invoke-ClaudeFileContext {
        if ($Force -or ($Fresh -and $options.ReadInterval -eq -1)) {Read-SharedUsage}
        if ($Force -or ($Fresh -and $options.WriteInterval -eq -1)) {Write-SharedUsage -Force}
        Invoke-SharingTick
        $script:SharedClaudeStatus=Get-SharingStatus Source
        if ($script:ReadError) {$script:SharedClaudeStatus='File unavailable · '+$script:SharedClaudeStatus}
        $script:ClaudeWriteStatus=Get-SharingStatus Write
        $script:ClaudeReadStatus=Get-SharingStatus Read
    }
}

function Update-ClaudeSharingTimer {
    # Run file imports even with local Claude disabled or minimized to the tray.
    if (-not $script:ClaudeSharingTimer) {
        $script:ClaudeSharingTimer=[Windows.Threading.DispatcherTimer]::new()
        $script:ClaudeSharingTimer.Interval=[TimeSpan]::FromSeconds(5)
        $script:ClaudeSharingTimer.Add_Tick({Invoke-ClaudeSharing;Update-Display;Update-TrayIcon})
    }
    $script:ClaudeSharingTimer.Stop()
    if ($script:SharedClaudeOptions.Enabled) {
        [void][IO.Directory]::CreateDirectory((Join-Path $script:StateDirectory 'ClaudeSharing'))
        # Match remote-only reads to Claude's chosen cadence even if local Claude is turned off.
        if ($script:SharedClaudeOptions.ReadInterval -eq -1) {
            $script:ClaudeSharingTimer.Interval=[TimeSpan]::FromSeconds(5)
        }
        # Manual-only and disabled file connections do not need a background timer.
        $readMinutes=if ($script:SharedClaudeOptions.ReadInterval -eq -1) {$script:ClaudeOptions.Interval} else {$script:SharedClaudeOptions.ReadInterval}
        $writeMinutes=if ($script:SharedClaudeOptions.WriteInterval -eq -1) {$script:ClaudeOptions.Interval} else {$script:SharedClaudeOptions.WriteInterval}
        if (($script:SharedClaudeOptions.ReadEnabled -and $readMinutes -gt 0) -or ($script:SharedClaudeOptions.WriteEnabled -and $script:ClaudeOptions.Enabled -and $writeMinutes -gt 0)) {$script:ClaudeSharingTimer.Start()}
        Invoke-ClaudeSharing -Force
    }
}

function Invoke-SharedClaudeWindowAction {
    param([scriptblock]$Action)
    # Reuse existing shell actions with this window's controls in a local invocation scope.
    $window=$script:SharedClaudeView.Window
    foreach ($key in $script:SharedClaudeView.Bindings.Keys) { Set-Variable -Name $key -Value $script:SharedClaudeView.Bindings[$key] }
    & $Action
}

function Save-SharedClaudeWindowBounds {
    # Save final geometry only; debounce native resize and position events separately.
    if ($script:SharedClaudeBoundsTimer) { $script:SharedClaudeBoundsTimer.Stop() }
    if (-not $script:SharedClaudeView -or -not $script:SharedClaudeView.Window.IsLoaded) { return }
    $peer=$script:SharedClaudeView.Window
    $script:SharedClaudeOptions.Bounds=@{left=$peer.Left;top=$peer.Top;width=$peer.Width;height=$peer.Height;topmost=$peer.Topmost}
    Save-WidgetState
}

function Set-SharedClaudeWindowPreset {
    param([string]$Name)
    # Resize SharedClaude alone without changing any other account's saved dimensions.
    if (-not $script:SharedClaudeView) { return }
    $index=@('Mini','Small','Medium','Large / Default').IndexOf($Name)
    if ($index -lt 0) { return }
    $sizes=@(@(72,72),@(140,155),@(190,210),@(280,290))
    $script:SharedClaudeView.Window.Width=$sizes[$index][0]; $script:SharedClaudeView.Window.Height=$sizes[$index][1]
    Update-SharedClaudeWindow
    Save-SharedClaudeWindowBounds
}

function Initialize-SharedClaudeWindow {
    # Clone the established shell so dragging, hover actions and both resize grips stay consistent.
    if ($script:SharedClaudeView) { return }
    $peer=[Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
    $bindings=@{}
    foreach ($match in [regex]::Matches($script:WidgetSource,'\$(\w+) = \$window\.FindName\(''([^'']+)''\)')) { $bindings[$match.Groups[1].Value]=$peer.FindName($match.Groups[2].Value) }
    $script:SharedClaudeView=@{Window=$peer;Bindings=$bindings}
    $peer.Icon=$window.Icon
    $peer.WindowStartupLocation='Manual'
    Restore-AccountWindowBounds $peer $(if ($script:SharedClaudeOptions.Bounds) {$script:SharedClaudeOptions.Bounds} else {@{left=$window.Left+$window.Width+8;top=$window.Top;width=280;height=290;topmost=$window.Topmost}})
    foreach ($key in @('primaryArea','secondaryArea','creditsArea','ultraCompactPanel','footerArea')) { $bindings[$key].Visibility='Collapsed' }
    # Coalesce size/location events; explicit drag completion and presets save immediately.
    $script:SharedClaudeBoundsTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:SharedClaudeBoundsTimer.Interval=[TimeSpan]::FromMilliseconds(300)
    $script:SharedClaudeBoundsTimer.Add_Tick({ Save-SharedClaudeWindowBounds })
    foreach ($key in @('leftResizeGrip','rightResizeGrip')) {
        $bindings[$key].Add_DragDelta({param($sender,$eventArgs) Resize-AccountWindow $script:SharedClaudeView.Window $sender.Tag $eventArgs.HorizontalChange $eventArgs.VerticalChange})
        $bindings[$key].Add_DragCompleted({Save-SharedClaudeWindowBounds; Invoke-SharedClaudeWindowAction {Update-HoverControls}})
    }
    foreach ($key in @('refreshButton','compactRefreshButton','hoverRefreshButton')) { $bindings[$key].Add_Click({Start-SharedClaudeRefresh -Force}) }
    foreach ($key in @('pinButton','hoverPinButton')) { $bindings[$key].Add_Click({Invoke-SharedClaudeWindowAction {$window.Topmost=-not $window.Topmost; Update-PinDisplay}; Save-SharedClaudeWindowBounds}) }
    foreach ($key in @('closeButton','hoverCloseButton','minimizeButton','hoverMinimizeButton')) { $bindings[$key].Add_Click({Save-SharedClaudeWindowBounds; $script:SharedClaudeView.Window.Hide()}) }
    foreach ($key in @('closeButton','hoverCloseButton')) {$bindings[$key].ToolTip='Hide this account to tray'}
    # Captured-pointer movement avoids Windows Snap just like the existing Codex windows.
    $bindings.outerBorder.Add_MouseLeftButtonDown({if (Test-WidgetDragSource $_.OriginalSource) {if ($_.ClickCount -eq 2) {Set-SharedClaudeWindowPreset 'Large / Default'} else {Invoke-SharedClaudeWindowAction {Start-WidgetDrag}}}})
    $bindings.outerBorder.Add_MouseMove({if ([Windows.Input.Mouse]::LeftButton -eq 'Pressed') {Invoke-SharedClaudeWindowAction {Update-WidgetDrag}}})
    $bindings.outerBorder.Add_MouseLeftButtonUp({Invoke-SharedClaudeWindowAction {if ($script:DragOrigin) {Update-WidgetDrag; $script:DragOrigin=$null; $outerBorder.ReleaseMouseCapture()}}; Save-SharedClaudeWindowBounds})
    $bindings.outerBorder.Add_LostMouseCapture({$script:DragOrigin=$null})
    $bindings.outerBorder.Add_MouseEnter({Invoke-SharedClaudeWindowAction {Update-HoverControls -IsPointerOver $true}})
    $bindings.outerBorder.Add_MouseLeave({Invoke-SharedClaudeWindowAction {Update-HoverControls -IsPointerOver $false}})
    $peer.Add_SizeChanged({Update-SharedClaudeWindow; if (-not $script:ChangingSharedClaudeWindow -and -not $script:DragOrigin -and -not $script:ResizingAccountWindow) {$script:SharedClaudeBoundsTimer.Stop();$script:SharedClaudeBoundsTimer.Start()}})
    $peer.Add_LocationChanged({if (-not $script:ChangingSharedClaudeWindow -and -not $script:DragOrigin) {$script:SharedClaudeBoundsTimer.Stop();$script:SharedClaudeBoundsTimer.Start()}})
    $peer.Add_IsVisibleChanged({Update-WidgetClock})
    $peer.Add_StateChanged({if ($script:SharedClaudeView.Window.WindowState -eq 'Minimized') {$script:SharedClaudeView.Window.Hide()}})
    $peer.Add_Closing({if (-not $script:ExitRequested) {$_.Cancel=$true;Save-SharedClaudeWindowBounds;$script:SharedClaudeView.Window.Hide()}})
}

function Update-SharedClaudeWindow {
    # Move the SharedClaude card only on an attachment transition, preserving independent window geometry.
    if ($script:ChangingSharedClaudeWindow -or -not ($window -is [Windows.Window]) -or -not $window.IsLoaded) { return }
    $separate=$script:SharedClaudeOptions.Enabled -and $script:SharedClaudeOptions.ReadEnabled -and ($script:SharedClaudeOptions.Placement -eq 'Separate window' -or ($script:SharedClaudeOptions.Placement -eq 'Follow layout' -and $script:AccountLayout -eq 'Separate windows'))
    if ($separate -ne [bool]$script:SharedClaudeWindowActive) {
        $script:ChangingSharedClaudeWindow=$true
        try {
            if ($separate) {
                Initialize-SharedClaudeWindow
                [void]$script:AccountsHost.Children.Remove($script:AccountCards.SharedClaude.Container)
                [Windows.Controls.Grid]::SetRow($script:AccountCards.SharedClaude.Container,1)
                [Windows.Controls.Grid]::SetRowSpan($script:AccountCards.SharedClaude.Container,3)
                [Windows.Controls.Grid]::SetColumn($script:AccountCards.SharedClaude.Container,0)
                [void]$script:SharedClaudeView.Bindings.outerBorder.Child.Children.Add($script:AccountCards.SharedClaude.Container)
                $script:SharedClaudeWindowActive=$true
                $script:SharedClaudeView.Window.Show()
            } else {
                Save-SharedClaudeWindowBounds
                $script:SharedClaudeView.Window.Hide()
                [void]$script:SharedClaudeView.Bindings.outerBorder.Child.Children.Remove($script:AccountCards.SharedClaude.Container)
                [Windows.Controls.Grid]::SetRowSpan($script:AccountCards.SharedClaude.Container,1)
                [void]$script:AccountsHost.Children.Add($script:AccountCards.SharedClaude.Container)
                $script:SharedClaudeWindowActive=$false
            }
            $script:LastAccountLayout=$null
        } finally {$script:ChangingSharedClaudeWindow=$false}
    }
    if (-not $script:SharedClaudeWindowActive -or -not $script:SharedClaudeView.Window.IsVisible) { return }
    # Render only into the detached shell's own dimensions and display preferences.
    $peer=$script:SharedClaudeView.Window; $bindings=$script:SharedClaudeView.Bindings
    $toolbar=$peer.ActualWidth -ge 180 -and $peer.ActualHeight -ge 125
    $bindings.outerBorder.Padding=[Windows.Thickness]::new(6)
    $bindings.dragArea.Visibility=if ($toolbar) {'Visible'} else {'Collapsed'}
    $bindings.planText.Visibility='Collapsed'; $bindings.compactRefreshButton.Visibility='Collapsed'
    $bindings.titleText.Text='CLAUDE'
    # Keep the existing restart launcher's title prefix so it closes every account window.
    $peer.Title='AI Usage Widget - '+$script:SharedClaudeOptions.Name
    $width=[Math]::Max(1,$peer.ActualWidth-14); $height=[Math]::Max(1,$peer.ActualHeight-14-$(if ($toolbar) {24} else {0}))
    $card=$script:AccountCards.SharedClaude; $card.Container.Visibility='Visible'
    $heading=Set-AccountHeadingSize $card $width $height
    Render-AccountCard -SharedClaude -Card $card -Snapshot $script:SharedClaudeUsage -Name $script:SharedClaudeOptions.Name -Status $script:SharedClaudeStatus -Scheme $script:SharedClaudeOptions.Scheme -Width $width -Height ([Math]::Max(1,$height-$heading))
    Invoke-SharedClaudeWindowAction {Update-PinDisplay;Update-HoverControls}
}

function Show-SharedClaudeWidget {
    # Restore only SharedClaude when detached; otherwise show its common host.
    if (-not $script:SharedClaudeWindowActive) {$script:SelectedAccount='SharedClaude';Update-Display;Update-TrayIcon;Show-Widget;return}
    $script:SharedClaudeView.Window.WindowState='Normal'
    $script:SharedClaudeView.Window.Show();[void]$script:SharedClaudeView.Window.Activate()
    Update-SharedClaudeWindow
}

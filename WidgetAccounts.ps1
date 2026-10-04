function New-AccountCard {
    # Clone the tested widget controls without starting another window, process, or tray icon.
    $copy = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
    $bindings = @{}
    foreach ($match in [regex]::Matches($script:WidgetSource, '\$(\w+) = \$window\.FindName\(''([^'']+)''\)')) {
        $bindings[$match.Groups[1].Value] = $copy.FindName($match.Groups[2].Value)
    }
    $visual = $copy.Content
    $copy.Content = $null
    # Let the shared window supply the background, outline, and controls.
    $visual.Background = 'Transparent'
    $visual.Effect = $null
    $visual.CornerRadius = [Windows.CornerRadius]::new(0)
    $container = [Windows.Controls.Grid]::new()
    foreach ($height in @('Auto','*')) { $row = [Windows.Controls.RowDefinition]::new(); $row.Height = [Windows.GridLengthConverter]::new().ConvertFromString($height); $container.RowDefinitions.Add($row) }
    $headingPanel = [Windows.Controls.StackPanel]::new()
    $headingPanel.Margin = [Windows.Thickness]::new(6,3,6,3)
    $heading = [Windows.Controls.TextBlock]::new()
    $heading.Foreground = '#DDE3EF'
    $heading.FontSize = 12
    $heading.TextTrimming = 'CharacterEllipsis'
    $status = [Windows.Controls.TextBlock]::new()
    $status.Foreground = '#8992A8'
    $status.FontSize = 9
    $status.TextTrimming = 'CharacterEllipsis'
    $headingPanel.Children.Add($heading) | Out-Null
    $headingPanel.Children.Add($status) | Out-Null
    $container.Children.Add($headingPanel) | Out-Null
    [Windows.Controls.Grid]::SetRow($visual,1)
    $container.Children.Add($visual) | Out-Null
    return @{ Container=$container; Visual=$visual; Bindings=$bindings; Heading=$heading; Status=$status; HeadingPanel=$headingPanel }
}

function Initialize-AccountViews {
    # Place the enabled account cards in the existing data area beneath the one shared toolbar.
    $script:WidgetSource = [IO.File]::ReadAllText((Join-Path $script:WidgetDirectory 'AIUsageWidget.ps1'))
    $script:AccountCards = @{ Local=(New-AccountCard); Remote=(New-AccountCard); Claude=(New-AccountCard); SharedClaude=(New-AccountCard) }
    $script:AccountsHost = [Windows.Controls.Grid]::new()
    $script:AccountsHost.Visibility = 'Collapsed'
    [Windows.Controls.Grid]::SetRow($script:AccountsHost,1)
    [Windows.Controls.Grid]::SetRowSpan($script:AccountsHost,3)
    $rootGrid = $outerBorder.Child
    $rootGrid.Children.Add($script:AccountsHost) | Out-Null
    # A narrow picker can be changed through Settings; the inline picker appears when it fits.
    # Override the native light selector template so its closed and expanded views match the widget.
    [xml]$pickerMarkup = @'
<ComboBox xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Background="#181B22" Foreground="#DDE3EF" BorderBrush="#413D4658">
  <ComboBox.ItemTemplate><DataTemplate><TextBlock Text="{Binding}" TextTrimming="CharacterEllipsis"/></DataTemplate></ComboBox.ItemTemplate>
  <ComboBox.Resources>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="#DDE3EF"/><Setter Property="Background" Value="#181B22"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ComboBoxItem">
        <Border x:Name="ItemBorder" Background="{TemplateBinding Background}" Padding="6,4"><ContentPresenter/></Border>
        <ControlTemplate.Triggers><Trigger Property="IsHighlighted" Value="True"><Setter TargetName="ItemBorder" Property="Background" Value="#303644"/></Trigger></ControlTemplate.Triggers>
      </ControlTemplate></Setter.Value></Setter>
    </Style>
  </ComboBox.Resources>
  <ComboBox.Template><ControlTemplate TargetType="ComboBox">
    <Grid>
      <ToggleButton Focusable="False" ClickMode="Press" IsChecked="{Binding IsDropDownOpen, RelativeSource={RelativeSource TemplatedParent}, Mode=TwoWay}">
        <ToggleButton.Template><ControlTemplate TargetType="ToggleButton"><Border Background="#181B22" BorderBrush="#413D4658" BorderThickness="1" CornerRadius="3"><TextBlock Text="▾" Foreground="#AAB2C5" HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,6,0"/></Border></ControlTemplate></ToggleButton.Template>
      </ToggleButton>
      <ContentPresenter Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" IsHitTestVisible="False" ClipToBounds="True" Margin="6,0,24,0" VerticalAlignment="Center"/>
      <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False">
        <Border Background="#181B22" BorderBrush="#413D4658" BorderThickness="1" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}"><ScrollViewer MaxHeight="240"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer></Border>
      </Popup>
    </Grid>
  </ControlTemplate></ComboBox.Template>
</ComboBox>
'@
    $script:AccountPicker = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($pickerMarkup))
    $script:AccountPicker.Height = 23
    $script:AccountPicker.Margin = [Windows.Thickness]::new(6,2,6,4)
    foreach ($label in @($script:LocalDisplayName,$script:RemoteDisplayName)) { $script:AccountPicker.Items.Add($label) | Out-Null }
    $script:AccountPicker.SelectedIndex = if ($script:SelectedAccount -eq 'Remote') { 1 } else { 0 }
    $script:AccountPicker.Add_SelectionChanged({
        if ($script:UpdatingAccountPicker) { return }
        # Save the source choice separately from the local account used for notifications.
        $script:SelectedAccount = $script:PickerKeys[$script:AccountPicker.SelectedIndex]
        Update-Display
        Update-TrayIcon
        Save-WidgetState
    })
    $script:AccountsHost.Children.Add($script:AccountPicker) | Out-Null
    foreach ($card in $script:AccountCards.Values) { $script:AccountsHost.Children.Add($card.Container) | Out-Null }
    $script:AccountDivider = [Windows.Controls.Border]::new()
    $script:AccountDivider.Background = '#413D4658'
    $script:AccountsHost.Children.Add($script:AccountDivider) | Out-Null
}

function Update-AccountNames {
    # Keep picker indices bound to stable enabled source keys, never to nickname text.
    $keys = @(Get-EnabledAccounts)
    $names = @($keys | ForEach-Object { Get-AccountName $_ })
    if ($script:SelectedAccount -notin $keys -and $keys.Count) { $script:SelectedAccount=$keys[0] }
    $script:UpdatingAccountPicker=$true
    try {
        if (($script:PickerKeys -join ',') -ne ($keys -join ',')) { $script:AccountPicker.Items.Clear(); foreach ($name in $names) { [void]$script:AccountPicker.Items.Add($name) } }
        else { for ($index=0;$index -lt $names.Count;$index++) { if ([string]$script:AccountPicker.Items[$index] -ne $names[$index]) { $script:AccountPicker.Items[$index]=$names[$index] } } }
        $script:PickerKeys=$keys
        $script:AccountPicker.SelectedIndex=[array]::IndexOf($keys,$script:SelectedAccount)
    } finally { $script:UpdatingAccountPicker=$false }
    $script:AccountPicker.ToolTip=$names -join [Environment]::NewLine
}
function Set-AccountHeadingSize {
    param($Card,[double]$Width,[double]$Height)
    # Keep a smaller, shortened name above the numbers; remove only the optional freshness line first.
    $Card.Heading.FontSize = if ($Width -ge 160 -and $Height -ge 180) { 12 } elseif ($Width -ge 100) { 10 } else { 9 }
    $Card.HeadingPanel.Margin = [Windows.Thickness]::new(3,1,3,1)
    $Card.HeadingPanel.Visibility = if ($Height -ge 52) { 'Visible' } else { 'Collapsed' }
    $Card.Status.Visibility = if ($Width -ge 160 -and $Height -ge 200) { 'Visible' } else { 'Collapsed' }
    # Reserve the actual font's line height so the retained name cannot squeeze the numeric rows.
    return $(if ($Card.HeadingPanel.Visibility -ne 'Visible') { 0 } elseif ($Card.Status.Visibility -eq 'Visible') { 29 } elseif ($Card.Heading.FontSize -eq 12) { 19 } elseif ($Card.Heading.FontSize -eq 10) { 16 } else { 14 })
}

function Render-AccountCard {
    param($Card, $Snapshot, [string] $Name, [string] $Status, [string] $Scheme, [double] $Width, [double] $Height, [switch] $Remote, [switch] $Claude, [switch] $SharedClaude, [switch] $ReserveCreditRow, [hashtable] $SharedLayout, [switch] $ProbeLayout)
    # Bind cloned controls in this invocation's scope so existing rendering code can be reused safely.
    foreach ($key in $Card.Bindings.Keys) { Set-Variable -Name $key -Value $Card.Bindings[$key] }
    $window = [pscustomobject]@{ ActualWidth=$Width; ActualHeight=$Height; Topmost=$true }
    $original = @{ SharedAccountLayout=$script:SharedAccountLayout; ProbingAccountLayout=$script:ProbingAccountLayout; ReserveCreditRow=$script:ReserveCreditRow; Usage=$script:Usage; CreditsVisible=$script:CreditsVisible; RefreshError=$script:RefreshError; RenderingAccountCard=$script:RenderingAccountCard;CreditDisplayMode=$script:CreditDisplayMode;PrimaryResetHours=$script:PrimaryResetHours;ShowWeeklyResetDate=$script:ShowWeeklyResetDate }
    try {
        # Isolate the synchronous render context; timers and alerts always retain the local snapshot.
        $script:RenderingAccountCard = $true
        # Keep weekly rows level with adjacent Codex cards that display credits.
        $script:ReserveCreditRow = [bool]$ReserveCreditRow
        # Measure connected columns first, then apply the same fit decisions to every account.
        $script:SharedAccountLayout = $SharedLayout
        $script:ProbingAccountLayout = [bool]$ProbeLayout
        $script:Usage = if ($Snapshot) { $Snapshot } else { @{primary=$null;secondary=$null;credits=$null} }
        $script:RefreshError = $null
        # Each imported card uses its own display preferences while local rendering stays intact.
        if ($Remote) {
            $script:CreditDisplayMode = $script:SharedCreditDisplayMode
            $script:PrimaryResetHours = $script:SharedPrimaryResetHours
            $script:ShowWeeklyResetDate = $script:SharedShowWeeklyResetDate
        }
        # Claude owns its reset options and has no Codex credit balance.
        if ($Claude) {
            $script:CreditDisplayMode='Off'
            $script:PrimaryResetHours=$script:ClaudeOptions.ResetHours
            $script:ShowWeeklyResetDate=$script:ClaudeOptions.WeeklyDate
        }
        # Imported Claude uses the same quota renderer with independent reset preferences.
        if ($SharedClaude) {$script:CreditDisplayMode='Off';$script:PrimaryResetHours=$script:SharedClaudeOptions.ResetHours;$script:ShowWeeklyResetDate=$script:SharedClaudeOptions.WeeklyDate}
        $colors = $script:ColorSchemes[$Scheme]
        foreach ($control in @($primaryPercent,$primaryBar,$compactPrimaryPercent)) { $control.Foreground = $colors[0] }
        foreach ($control in @($secondaryPercent,$secondaryBar,$compactSecondaryPercent)) { $control.Foreground = $colors[1] }
        foreach ($control in @($creditsText,$compactCreditsText)) { $control.Foreground = $colors[2] }
        Update-Display
        # Keep account borders and actions in the shared window instead of duplicating them.
        $outerBorder.BorderThickness = [Windows.Thickness]::new(0)
    }
    finally {
        # Restore every script-level value even when a render fails.
        foreach ($key in $original.Keys) { Set-Variable -Scope Script -Name $key -Value $original[$key] }
    }
    $Card.Heading.Text = $Name
    $Card.Status.Text = $Status
    $Card.Container.ToolTip = "$Name`n$Status"
}

function Update-AccountViews {
    # Reuse one card renderer for any enabled combination of local, shared and Claude accounts.
    if (-not $script:AccountsHost -or $script:RenderingAccountCard) { return }
    Update-AccountNames
    Update-SeparateWindows
    Update-ClaudeWindow
    Update-SharedClaudeWindow
    $keys = @(Get-EnabledAccounts | Where-Object { -not ($_ -eq 'Remote' -and $script:SeparateWindowsActive) -and -not ($_ -eq 'Claude' -and $script:ClaudeWindowActive) -and -not ($_ -eq 'SharedClaude' -and $script:SharedClaudeWindowActive) })
    $originalSingle = $keys.Count -eq 1 -and $keys[0] -eq 'Local' -and -not $script:ClaudeOptions.Enabled -and -not ($script:SharedEnabled -and $script:ReadUsageEnabled) -and -not ($script:SharedClaudeOptions.Enabled -and $script:SharedClaudeOptions.ReadEnabled)
    # Keep a disabled local account from leaving an empty desktop shell behind detached accounts.
    if (-not $keys.Count -and $window.IsLoaded) {$script:AutomaticallyHiddenHost=$true;$window.Hide()}
    elseif ($keys.Count -and $script:AutomaticallyHiddenHost) {$script:AutomaticallyHiddenHost=$false;$window.Show()}
    $script:AccountsHost.Visibility = if ($originalSingle) { 'Collapsed' } else { 'Visible' }
    $window.MinWidth=if ($script:AccountLayout -eq 'Side by side' -and -not $originalSingle) { [Math]::Max(72,75*$keys.Count) } else {72}
    $closeButton.ToolTip=if ($script:SeparateWindowsActive -or $script:ClaudeWindowActive) {'Hide this account to tray'} else {'Close AI Usage Widget'}
    $hoverCloseButton.ToolTip=$closeButton.ToolTip
    if ($originalSingle) { return }
    foreach ($control in @($primaryArea,$secondaryArea,$creditsArea,$ultraCompactPanel,$footerArea)) { $control.Visibility='Collapsed' }
    # Reserve only one toolbar; each card retains its account name while shrinking.
    $outerBorder.Padding=[Windows.Thickness]::new(6)
    $planText.Visibility='Collapsed'
    $titleText.Text=if ($window.ActualWidth -ge 250) {'USAGE'} else {'USAGE'}
    $dragArea.Height=[double]::NaN
    $toolbar=$window.ActualWidth -ge 180 -and $window.ActualHeight -ge 125
    $dragArea.Visibility=if ($toolbar) {'Visible'} else {'Collapsed'}
    $compactRefreshButton.Visibility='Collapsed'
    $width=[Math]::Max(1,$window.ActualWidth-14)
    $height=[Math]::Max(1,$window.ActualHeight-14-$(if ($toolbar) {24} else {0}))
    $picker=$script:AccountLayout -eq 'Account picker'
    $signature=$script:AccountLayout + ':' + ($keys -join ',')
    # Rebuild tracks only when layout or enabled sources change, not on countdown ticks.
    if ($script:LastAccountLayout -ne $signature) {
        $script:AccountsHost.RowDefinitions.Clear(); $script:AccountsHost.ColumnDefinitions.Clear()
        foreach ($key in $keys) { [Windows.Controls.Grid]::SetRowSpan($script:AccountCards[$key].Container,1); [Windows.Controls.Grid]::SetColumn($script:AccountCards[$key].Container,0); [Windows.Controls.Grid]::SetRow($script:AccountCards[$key].Container,0) }
        foreach ($line in @($script:AccountDivider)+@($script:ExtraAccountDividers)) { [void]$script:AccountsHost.Children.Remove($line) }
        $script:ExtraAccountDividers=@()
        if ($picker) {
            foreach ($size in @('29','*')) { $row=[Windows.Controls.RowDefinition]::new(); $row.Height=[Windows.GridLengthConverter]::new().ConvertFromString($size); $script:AccountsHost.RowDefinitions.Add($row) }
            foreach ($key in $keys) { [Windows.Controls.Grid]::SetRow($script:AccountCards[$key].Container,1) }
        } else {
            for ($index=0;$index -lt $keys.Count;$index++) {
                $side=$script:AccountLayout -eq 'Side by side'
                if ($index -gt 0) {
                    # Give every adjacent pair a divider, including all three attached accounts.
                    $line=[Windows.Controls.Border]::new(); $line.Background='#413D4658'
                    if ($side) { $track=[Windows.Controls.ColumnDefinition]::new(); $track.Width=[Windows.GridLength]::new(1); $script:AccountsHost.ColumnDefinitions.Add($track); [Windows.Controls.Grid]::SetColumn($line,2*$index-1) }
                    else { $track=[Windows.Controls.RowDefinition]::new(); $track.Height=[Windows.GridLength]::new(1); $script:AccountsHost.RowDefinitions.Add($track); [Windows.Controls.Grid]::SetRow($line,2*$index-1) }
                    $script:ExtraAccountDividers+=,$line; [void]$script:AccountsHost.Children.Add($line)
                }
                if ($side) { $track=[Windows.Controls.ColumnDefinition]::new(); $script:AccountsHost.ColumnDefinitions.Add($track); [Windows.Controls.Grid]::SetColumn($script:AccountCards[$keys[$index]].Container,2*$index) }
                else { $track=[Windows.Controls.RowDefinition]::new(); $script:AccountsHost.RowDefinitions.Add($track); [Windows.Controls.Grid]::SetRow($script:AccountCards[$keys[$index]].Container,2*$index) }
            }
        }
        $script:LastAccountLayout=$signature
    }
    $script:AccountPicker.Visibility=if ($picker -and $width -ge 100 -and $keys.Count) {'Visible'} else {'Collapsed'}
    if ($picker) { $script:AccountsHost.RowDefinitions[0].Height=[Windows.GridLength]::new($(if ($script:AccountPicker.Visibility -eq 'Visible') {29} else {0})); $height-=$script:AccountsHost.RowDefinitions[0].Height.Value }
    # Reserve equal credit space across connected panels without inventing Claude balances.
    $reserveCredits = $false
    if ($script:AccountLayout -in @('Side by side','Stacked')) {
        foreach ($source in @('Local','Remote')) {
            if ($source -notin $keys) { continue }
            $creditMode = if ($source -eq 'Local') { $script:CreditDisplayMode } else { $script:SharedCreditDisplayMode }
            $creditSnapshot = if ($source -eq 'Local') { $script:Usage } else { $script:RemoteUsage }
            $balance = [decimal]0
            $hasBalance = $creditSnapshot.credits -and [decimal]::TryParse([string]$creditSnapshot.credits.balance,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$balance)
            if ($creditMode -eq 'Always' -or ($creditMode -eq 'Available' -and ($creditSnapshot.credits.unlimited -eq $true -or ($hasBalance -and $balance -gt 0)))) { $reserveCredits = $true }
        }
    }
    # Share only presentation measurements; separate windows and other layouts remain independent.
    $sharedLayout = if ($script:AccountLayout -in @('Side by side','Stacked') -and $keys.Count -gt 1) {
        @{Widths=@{};Values=@{};ResetHeights=@{};NumberSize=20;ResetWidth=0;TickerPossible=$true;TickerFontSize=20}
    } else { $null }
    $passes = if ($sharedLayout) { @('Measure','Apply') } else { @('Apply') }
    foreach ($pass in $passes) {
        foreach ($key in @('Local','Remote','Claude','SharedClaude')) {
            $card=$script:AccountCards[$key]
            # Detached cards stay under their own shell; disabled cards collapse without stale values.
            if (($key -eq 'Remote' -and $script:SeparateWindowsActive) -or ($key -eq 'Claude' -and $script:ClaudeWindowActive) -or ($key -eq 'SharedClaude' -and $script:SharedClaudeWindowActive)) { continue }
            $card.Container.Visibility=if ($key -in $keys -and (-not $picker -or $script:SelectedAccount -eq $key)) {'Visible'} else {'Collapsed'}
            if ($card.Container.Visibility -eq 'Collapsed') { continue }
            $cardWidth=if ($script:AccountLayout -eq 'Side by side') {($width-($keys.Count-1))/$keys.Count} else {$width}
            $cardHeight=if ($script:AccountLayout -in @('Stacked','Separate windows')) {($height-($keys.Count-1))/$keys.Count} else {$height}
            $heading=Set-AccountHeadingSize $card $cardWidth $cardHeight
            switch ($key) {
                Local { $snapshot=$script:Usage; $scheme=$script:LocalScheme; $status=if ($script:RefreshError) {'Refresh failed - last reading retained'} elseif ($snapshot) {'Local account · updated '+[DateTimeOffset]::FromUnixTimeSeconds([long]$snapshot.fetchedAt).ToLocalTime().ToString('h:mm tt')} else {'Waiting for local usage'} }
                Remote { $snapshot=$script:RemoteUsage; $scheme=$script:RemoteScheme; $status=Get-SharingStatus Source; if ($script:ReadError) {$status='File unavailable · '+$status} }
                Claude { $snapshot=$script:ClaudeUsage; $scheme=$script:ClaudeOptions.Scheme; $status=$script:ClaudeStatus }
                SharedClaude {$snapshot=$script:SharedClaudeUsage;$scheme=$script:SharedClaudeOptions.Scheme;$status=$script:SharedClaudeStatus}
            }
            # Retain the chosen nickname while identifying the provider in status text and hover help.
            $provider = switch ($key) { Local {'Codex'} Remote {'Shared Codex'} Claude {'Claude'} SharedClaude {'Shared Claude'} }
            $status = $provider + ' · ' + $status
            $plan=if ($snapshot.planType) {([string]$snapshot.planType).ToUpperInvariant()+' · '} else {''}
            Render-AccountCard -SharedLayout $sharedLayout -ProbeLayout:($pass -eq 'Measure') -ReserveCreditRow:$reserveCredits -Remote:($key -eq 'Remote') -Claude:($key -eq 'Claude') -SharedClaude:($key -eq 'SharedClaude') -Card $card -Snapshot $snapshot -Name (Get-AccountName $key) -Status ($plan+$status) -Scheme $scheme -Width $cardWidth -Height ([Math]::Max(1,$cardHeight-$heading))
        }
    }
    # With no attached account, Settings and the tray remain available to re-enable sources.
    $script:AccountsHost.ToolTip=if (-not $keys.Count) {'No attached accounts enabled. Open Settings from the tray.'} else {$null}
    Update-HoverControls
}
function Set-WidgetPreset {
    param([ValidateSet('Mini','Small','Medium','Large / Default')] [string] $Name)
    # Preserve the old single-account presets and use dimensions suitable for each two-account layout.
    $sizes = @(@(72,72),@(140,155),@(190,210),@(280,290))
    if ($script:SharedEnabled -and $script:ReadUsageEnabled) {
        $sizes = switch ($script:AccountLayout) {
            'Side by side' { @(@(150,72),@(300,180),@(400,250),@(560,330)) }
            'Stacked' { @(@(72,144),@(180,320),@(240,470),@(300,600)) }
            'Account picker' { @(@(72,72),@(160,180),@(220,260),@(300,330)) }
            'Separate windows' { @(@(72,72),@(140,155),@(190,210),@(280,290)) }
        }
    }
    $index = @('Mini','Small','Medium','Large / Default').IndexOf($Name)
    # Size the main host for its enabled, attached cards; detached accounts keep their own presets.
    $count=@(Get-EnabledAccounts | Where-Object {-not ($_ -eq 'Remote' -and $script:SeparateWindowsActive) -and -not ($_ -eq 'Claude' -and $script:ClaudeWindowActive) -and -not ($_ -eq 'SharedClaude' -and $script:SharedClaudeWindowActive)}).Count
    if ($count -gt 1 -and $script:AccountLayout -eq 'Side by side') {$sizes=@(@((75*$count),72),@((150*$count),180),@((200*$count),250),@((280*$count),330))}
    if ($count -gt 1 -and $script:AccountLayout -in @('Stacked','Separate windows')) {$sizes=@(@(72,(72*$count)),@(180,(160*$count)),@(240,(235*$count)),@(300,(300*$count)))}
    $window.Width = $sizes[$index][0]
    $window.Height = $sizes[$index][1]
    Update-Display
    Save-WidgetState
}

function Invoke-SeparateWindowAction {
    param([scriptblock]$Action)
    # Bind only the detached shell for pointer and toolbar actions; local usage remains untouched.
    $window = $script:SeparateView.Window
    foreach ($key in $script:SeparateView.Bindings.Keys) { Set-Variable -Name $key -Value $script:SeparateView.Bindings[$key] }
    & $Action
}

function Test-WidgetDragSource {
    param($Source)
    # Buttons, selectors, and the resize grip keep their own input instead of starting a drag.
    while ($Source -is [Windows.DependencyObject]) {
        if ($Source -is [Windows.Controls.Primitives.ButtonBase] -or $Source -is [Windows.Controls.ComboBox] -or $Source -is [Windows.Controls.Primitives.Thumb]) { return $false }
        if (-not ($Source -is [Windows.Media.Visual])) { break }
        $Source = [Windows.Media.VisualTreeHelper]::GetParent($Source)
    }
    return $true
}

function Resize-AccountWindow {
    param($Target,[string]$Corner,[double]$HorizontalChange,[double]$VerticalChange)
    # Anchor the opposite edge and clamp size so both corners behave consistently at minimum size.
    $width = [Math]::Max($Target.MinWidth,$Target.Width + $(if ($Corner -eq 'Left') { -$HorizontalChange } else { $HorizontalChange }))
    $height = [Math]::Max($Target.MinHeight,$Target.Height + $VerticalChange)
    # Avoid scheduling intermediate saves while one corner movement updates several properties.
    $previousResize = $script:ResizingAccountWindow
    $script:ResizingAccountWindow = $true
    try {
        if ($Corner -eq 'Left') { $Target.Left += $Target.Width - $width }
        $Target.Width = $width; $Target.Height = $height
    } finally { $script:ResizingAccountWindow = $previousResize }
}

function Save-SeparateWindowBounds {
    # A completed drag, preset or shutdown already saves the final bounds; discard queued duplicates.
    if ($script:SeparateBoundsSaveTimer) { $script:SeparateBoundsSaveTimer.Stop() }
    # Persist the imported window independently, including its own always-on-top choice.
    if (-not $script:SeparateView -or -not $script:SeparateView.Window.IsLoaded) { return }
    $peer = $script:SeparateView.Window
    $script:SeparateRemoteBounds = @{ left=$peer.Left;top=$peer.Top;width=$peer.Width;height=$peer.Height;topmost=$peer.Topmost }
    Save-WidgetState
}

function Schedule-SeparateWindowBoundsSave {
    # Custom dragging saves on release; debounce other size and position events until they settle.
    if ($script:ChangingAccountWindows -or $script:ResizingAccountWindow -or $script:DragOrigin) { return }
    $bindings = $script:SeparateView.Bindings
    if ($bindings.leftResizeGrip.IsDragging -or $bindings.rightResizeGrip.IsDragging) { return }
    $script:SeparateBoundsSaveTimer.Stop()
    $script:SeparateBoundsSaveTimer.Start()
}

function Restore-AccountWindowBounds {
    param($Target,$Bounds)
    # Accept finite, reachable saved dimensions while keeping windows on a connected display.
    if (-not $Bounds) { return }
    try {
        foreach ($key in @('width','height','left','top')) {
            if ($null -eq $Bounds.$key) { return }
            $value = [double]$Bounds.$key
            if ([double]::IsNaN($value) -or [double]::IsInfinity($value)) { return }
        }
    } catch { return }
    $Target.Width = [Math]::Min(3000,[Math]::Max(72,[double]$Bounds.width))
    $Target.Height = [Math]::Min(3000,[Math]::Max(58,[double]$Bounds.height))
    $screenLeft = [Windows.SystemParameters]::VirtualScreenLeft
    $screenTop = [Windows.SystemParameters]::VirtualScreenTop
    $Target.Left = [Math]::Max($screenLeft,[Math]::Min([double]$Bounds.left,$screenLeft + [Windows.SystemParameters]::VirtualScreenWidth - $Target.Width))
    $Target.Top = [Math]::Max($screenTop,[Math]::Min([double]$Bounds.top,$screenTop + [Windows.SystemParameters]::VirtualScreenHeight - $Target.Height))
    if ($Bounds.topmost -is [bool]) { $Target.Topmost = $Bounds.topmost }
}

function Initialize-SeparateWindow {
    # Clone the existing shell once; both accounts still share one process, reader and tray icon.
    if ($script:SeparateView) { return }
    $peer = [Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
    $bindings = @{}
    foreach ($match in [regex]::Matches($script:WidgetSource,'\$(\w+) = \$window\.FindName\(''([^'']+)''\)')) { $bindings[$match.Groups[1].Value] = $peer.FindName($match.Groups[2].Value) }
    $script:SeparateView = @{ Window=$peer; Bindings=$bindings }
    # Coalesce native size and location changes into one settings write after a short idle period.
    $script:SeparateBoundsSaveTimer = [Windows.Threading.DispatcherTimer]::new()
    $script:SeparateBoundsSaveTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:SeparateBoundsSaveTimer.Add_Tick({ Save-SeparateWindowBounds })
    # Give the imported shell the same hover-only resize behavior without changing the local window.
    foreach ($key in @('leftResizeGrip','rightResizeGrip')) {
        $bindings[$key].Add_DragDelta({ param($sender,$eventArgs) Resize-AccountWindow $script:SeparateView.Window $sender.Tag $eventArgs.HorizontalChange $eventArgs.VerticalChange })
        $bindings[$key].Add_DragCompleted({ Save-SeparateWindowBounds; Invoke-SeparateWindowAction { Update-HoverControls } })
    }
    $peer.Icon = $window.Icon
    $peer.WindowStartupLocation = 'Manual'
    $peer.Left = $window.Left + $window.Width + 8
    $peer.Top = $window.Top
    $initialBounds = if ($script:SeparateRemoteBounds) { $script:SeparateRemoteBounds } else { @{left=$peer.Left;top=$peer.Top;width=$peer.Width;height=$peer.Height;topmost=$window.Topmost} }
    Restore-AccountWindowBounds $peer $initialBounds
    # Hide the shell's duplicate data controls and place the existing imported card beneath its toolbar.
    foreach ($key in @('primaryArea','secondaryArea','creditsArea','ultraCompactPanel','footerArea')) { $bindings[$key].Visibility = 'Collapsed' }
    foreach ($key in @('refreshButton','compactRefreshButton','hoverRefreshButton')) { $bindings[$key].Add_Click({ Invoke-WidgetRefresh }) }
    foreach ($key in @('pinButton','hoverPinButton')) {
        $bindings[$key].Add_Click({ Invoke-SeparateWindowAction { $window.Topmost = -not $window.Topmost; Update-PinDisplay }; Save-SeparateWindowBounds })
    }
    foreach ($key in @('closeButton','hoverCloseButton','minimizeButton','hoverMinimizeButton')) {
        $bindings[$key].Add_Click({ Save-SeparateWindowBounds; $script:SeparateView.Window.Hide() })
    }
    foreach ($key in @('closeButton','hoverCloseButton')) { $bindings[$key].ToolTip = 'Hide this account to tray' }
    # Use the same captured-pointer dragging as the main window so Windows Snap stays out of the way.
    $bindings.outerBorder.Add_MouseLeftButtonDown({
        if (Test-WidgetDragSource $_.OriginalSource) {
            if ($_.ClickCount -eq 2) { Set-SeparateWindowPreset 'Large / Default' }
            else { Invoke-SeparateWindowAction { Start-WidgetDrag } }
        }
    })
    $bindings.outerBorder.Add_MouseMove({ if ([Windows.Input.Mouse]::LeftButton -eq 'Pressed') { Invoke-SeparateWindowAction { Update-WidgetDrag } } })
    $bindings.outerBorder.Add_MouseLeftButtonUp({
        Invoke-SeparateWindowAction { if ($script:DragOrigin) { Update-WidgetDrag; $script:DragOrigin=$null; $outerBorder.ReleaseMouseCapture() } }
        Save-SeparateWindowBounds
    })
    $bindings.outerBorder.Add_LostMouseCapture({ $script:DragOrigin=$null })
    $bindings.outerBorder.Add_MouseEnter({ Invoke-SeparateWindowAction { Update-HoverControls -IsPointerOver $true } })
    $bindings.outerBorder.Add_MouseLeave({ Invoke-SeparateWindowAction { Update-HoverControls -IsPointerOver $false } })
    # Keep rendering responsive while deferring repeated disk writes during resizing and movement.
    $peer.Add_SizeChanged({ if (-not $script:ChangingAccountWindows) { Update-SeparateWindow; Schedule-SeparateWindowBoundsSave } })
    $peer.Add_LocationChanged({ Schedule-SeparateWindowBoundsSave })
    $peer.Add_StateChanged({ if ($script:SeparateView.Window.WindowState -eq 'Minimized') { $script:SeparateView.Window.Hide() } })
    $peer.Add_IsVisibleChanged({ Update-WidgetClock })
    $peer.Add_Closing({
        # A per-account close hides only this window; Exit shuts down both and the tray.
        if (-not $script:ExitRequested) { $_.Cancel=$true; Save-SeparateWindowBounds; $script:SeparateView.Window.Hide() }
    })
}

function Set-SeparateWindowPreset {
    param([string]$Name)
    # Tray presets target the imported window without altering the local window's dimensions.
    $sizes = @(@(72,72),@(140,155),@(190,210),@(280,290))
    $index = @('Mini','Small','Medium','Large / Default').IndexOf($Name)
    if ($index -lt 0) { return }
    $peer = $script:SeparateView.Window
    $peer.Width = $sizes[$index][0]; $peer.Height = $sizes[$index][1]
    Update-SeparateWindow
    Save-SeparateWindowBounds
}

function Show-SharedWidget {
    # Reopen only the imported window when the separate layout is active.
    if (-not $script:SeparateWindowsActive) { Show-Widget; return }
    $peer = $script:SeparateView.Window
    $peer.WindowState = 'Normal'; $peer.Show(); [void]$peer.Activate()
    Update-SeparateWindow
}

function Update-WidgetClock {
    # Keep countdowns running while either account window remains visible.
    if (-not $clockTimer) { return }
    if ($window.IsVisible -or ($script:SeparateView -and $script:SeparateView.Window.IsVisible) -or ($script:ClaudeView -and $script:ClaudeView.Window.IsVisible) -or ($script:SharedClaudeView -and $script:SharedClaudeView.Window.IsVisible)) { $clockTimer.Start() }
    else { $clockTimer.Stop() }
}

function Update-SeparateWindows {
    # Transition windows only after startup has loaded real bounds, avoiding duplicate shells in tests.
    if ($script:ChangingAccountWindows -or -not ($window -is [Windows.Window]) -or -not $window.IsLoaded) { return }
    $separate = $script:LocalEnabled -and $script:SharedEnabled -and $script:ReadUsageEnabled -and $script:AccountLayout -eq 'Separate windows'
    if ($separate -ne [bool]$script:SeparateWindowsActive) {
        $script:ChangingAccountWindows = $true
        try {
            if ($separate) {
                # A restored Separate layout already has combined geometry saved from its previous session.
                if (-not $script:RestoredSeparateLayout) { $script:CombinedWindowBounds = @{ left=$window.Left;top=$window.Top;width=$window.Width;height=$window.Height;topmost=$window.Topmost } }
                $script:RestoredSeparateLayout = $false
                Initialize-SeparateWindow
                # Move the imported visual rather than maintaining a third set of usage controls.
                [void]$script:AccountsHost.Children.Remove($script:AccountCards.Remote.Container)
                $peerHost = $script:SeparateView.Bindings.outerBorder.Child
                [Windows.Controls.Grid]::SetRow($script:AccountCards.Remote.Container,1)
                [Windows.Controls.Grid]::SetRowSpan($script:AccountCards.Remote.Container,3)
                [Windows.Controls.Grid]::SetColumn($script:AccountCards.Remote.Container,0)
                $peerHost.Children.Add($script:AccountCards.Remote.Container) | Out-Null
                Restore-AccountWindowBounds $window $script:SeparateLocalBounds
                if (-not $script:SeparateLocalBounds) { $window.Width=280; $window.Height=290 }
                $script:SeparateWindowsActive = $true
                $script:SeparateView.Window.Show()
            } else {
                $script:SeparateLocalBounds = @{ left=$window.Left;top=$window.Top;width=$window.Width;height=$window.Height;topmost=$window.Topmost }
                Save-SeparateWindowBounds
                $script:SeparateView.Window.Hide()
                [void]$script:SeparateView.Bindings.outerBorder.Child.Children.Remove($script:AccountCards.Remote.Container)
                [Windows.Controls.Grid]::SetRowSpan($script:AccountCards.Remote.Container,1)
                $script:AccountsHost.Children.Add($script:AccountCards.Remote.Container) | Out-Null
                $script:SeparateWindowsActive = $false
                Restore-AccountWindowBounds $window $script:CombinedWindowBounds
            }
            $script:LastAccountLayout = $null
        } finally { $script:ChangingAccountWindows = $false }
        Update-WidgetClock
    }
    if ($script:SeparateWindowsActive) { Update-SeparateWindow }
}

function Update-SeparateWindow {
    # Render the imported card into its own shell without borrowing the local window's dimensions.
    if (-not $script:SeparateWindowsActive -or $script:ChangingAccountWindows) { return }
    $peer = $script:SeparateView.Window
    if (-not $peer.IsVisible) { return }
    $bindings = $script:SeparateView.Bindings
    $width = [Math]::Max(1,$peer.ActualWidth - 14)
    $toolbar = $peer.ActualWidth -ge 180 -and $peer.ActualHeight -ge 125
    $bindings.outerBorder.Padding = [Windows.Thickness]::new(6)
    $bindings.dragArea.Visibility = if ($toolbar) { 'Visible' } else { 'Collapsed' }
    $bindings.planText.Visibility = 'Collapsed'
    $bindings.titleText.Text = 'CODEX'
    $bindings.compactRefreshButton.Visibility = 'Collapsed'
    $peer.Title = 'AI Usage Widget - ' + $script:RemoteDisplayName
    $bindings.statusDot.Fill = if ($script:ReadError) { '#E8B44C' } else { '#91B8B0' }
    $height = [Math]::Max(1,$peer.ActualHeight - 14 - $(if ($toolbar) {24} else {0}))
    $card = $script:AccountCards.Remote
    $card.Container.Visibility = 'Visible'
    $headingHeight = Set-AccountHeadingSize $card $width $height
    $status = Get-SharingStatus Source
    if ($script:ReadError) { $status = 'File unavailable · ' + $status }
    Render-AccountCard -Remote -Card $card -Snapshot $script:RemoteUsage -Name $script:RemoteDisplayName -Status $status -Scheme $script:RemoteScheme -Width $width -Height ([Math]::Max(1,$height-$headingHeight))
    # Use the detached shell's hover and pin controls after the card context has been restored.
    Invoke-SeparateWindowAction { Update-PinDisplay; Update-HoverControls }
}

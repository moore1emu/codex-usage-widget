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
    # Place the two account cards in the existing data area beneath the one shared toolbar.
    $script:WidgetSource = [IO.File]::ReadAllText((Join-Path $script:WidgetDirectory 'CodexUsageWidget.ps1'))
    $script:AccountCards = @{ Local=(New-AccountCard); Remote=(New-AccountCard) }
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
        $script:SelectedAccount = if ($script:AccountPicker.SelectedIndex -eq 1) { 'Remote' } else { 'Local' }
        Update-Display
        Save-WidgetState
    })
    $script:AccountsHost.Children.Add($script:AccountPicker) | Out-Null
    foreach ($card in $script:AccountCards.Values) { $script:AccountsHost.Children.Add($card.Container) | Out-Null }
    $script:AccountDivider = [Windows.Controls.Border]::new()
    $script:AccountDivider.Background = '#413D4658'
    $script:AccountsHost.Children.Add($script:AccountDivider) | Out-Null
}

function Update-AccountNames {
    # Update labels in place so synced nickname changes never change the selected account index.
    $names = @($script:LocalDisplayName,$script:RemoteDisplayName)
    $selected = if ($script:SelectedAccount -eq 'Remote') { 1 } else { 0 }
    $script:UpdatingAccountPicker = $true
    try {
        for ($index = 0; $index -lt 2; $index++) {
            if ([string]$script:AccountPicker.Items[$index] -ne $names[$index]) { $script:AccountPicker.Items[$index] = $names[$index] }
        }
        $script:AccountPicker.SelectedIndex = $selected
    } finally { $script:UpdatingAccountPicker = $false }
    $script:AccountPicker.ToolTip = $names -join [Environment]::NewLine
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
    param($Card, $Snapshot, [string] $Name, [string] $Status, [string] $Scheme, [double] $Width, [double] $Height, [switch] $Remote)
    # Bind cloned controls in this invocation's scope so existing rendering code can be reused safely.
    foreach ($key in $Card.Bindings.Keys) { Set-Variable -Name $key -Value $Card.Bindings[$key] }
    $window = [pscustomobject]@{ ActualWidth=$Width; ActualHeight=$Height; Topmost=$true }
    $original = @{ Usage=$script:Usage; CreditsVisible=$script:CreditsVisible; RefreshError=$script:RefreshError; RenderingAccountCard=$script:RenderingAccountCard;CreditDisplayMode=$script:CreditDisplayMode;PrimaryResetHours=$script:PrimaryResetHours;ShowWeeklyResetDate=$script:ShowWeeklyResetDate }
    try {
        # Isolate the synchronous render context; timers and alerts always retain the local snapshot.
        $script:RenderingAccountCard = $true
        $script:Usage = if ($Snapshot) { $Snapshot } else { @{primary=$null;secondary=$null;credits=$null} }
        $script:RefreshError = $null
        # Each imported card uses its own display preferences while local rendering stays intact.
        if ($Remote) {
            $script:CreditDisplayMode = $script:SharedCreditDisplayMode
            $script:PrimaryResetHours = $script:SharedPrimaryResetHours
            $script:ShowWeeklyResetDate = $script:SharedShowWeeklyResetDate
        }
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
    # Leave the established single-account layout intact until importing is explicitly enabled.
    if (-not $script:AccountsHost -or $script:RenderingAccountCard) { return }
    Update-AccountNames
    # Move the imported card between its shared host and independent window only when the layout changes.
    Update-SeparateWindows
    # Explain the per-account close action only while the independent layout is active.
    $closeButton.ToolTip = if ($script:SeparateWindowsActive) { 'Hide this account to tray' } else { 'Close Codex Usage' }
    $hoverCloseButton.ToolTip = $closeButton.ToolTip
    $script:AccountsHost.Visibility = if ($script:SharedEnabled -and $script:ReadUsageEnabled) { 'Visible' } else { 'Collapsed' }
    $window.MinWidth = if ($script:SharedEnabled -and $script:ReadUsageEnabled -and $script:AccountLayout -eq 'Side by side') { 150 } else { 72 }
    if (-not $script:SharedEnabled -or -not $script:ReadUsageEnabled) { return }
    foreach ($control in @($primaryArea,$secondaryArea,$creditsArea,$ultraCompactPanel,$footerArea)) { $control.Visibility = 'Collapsed' }
    # Reserve only the shared toolbar; each account owns its name and freshness label.
    $outerBorder.Padding = [Windows.Thickness]::new(6)
    $planText.Visibility = 'Collapsed'
    $titleText.Text = if ($window.ActualWidth -ge 250) { 'CODEX USAGE' } else { 'CODEX' }
    $dragArea.Height = [double]::NaN
    $toolbar = $window.ActualWidth -ge 180 -and $window.ActualHeight -ge 125
    $dragArea.Visibility = if ($toolbar) { 'Visible' } else { 'Collapsed' }
    $compactRefreshButton.Visibility = 'Collapsed'
    $width = [Math]::Max(1,$window.ActualWidth - 14)
    $height = [Math]::Max(1,$window.ActualHeight - 14 - $(if ($toolbar) { 24 } else { 0 }))
    # Rebuild grid tracks only when layout changes, not on every countdown tick.
    if ($script:LastAccountLayout -ne $script:AccountLayout) {
        $script:AccountsHost.RowDefinitions.Clear()
        $script:AccountsHost.ColumnDefinitions.Clear()
        if ($script:AccountLayout -eq 'Separate windows') {
            $column = [Windows.Controls.ColumnDefinition]::new(); $script:AccountsHost.ColumnDefinitions.Add($column)
            [Windows.Controls.Grid]::SetColumn($script:AccountCards.Local.Container,0)
        } elseif ($script:AccountLayout -eq 'Side by side') {
            foreach ($size in @('*','1','*')) { $column = [Windows.Controls.ColumnDefinition]::new(); $column.Width = [Windows.GridLengthConverter]::new().ConvertFromString($size); $script:AccountsHost.ColumnDefinitions.Add($column) }
            [Windows.Controls.Grid]::SetColumn($script:AccountCards.Local.Container,0)
            [Windows.Controls.Grid]::SetColumn($script:AccountCards.Remote.Container,2)
            [Windows.Controls.Grid]::SetColumn($script:AccountDivider,1)
        } else {
            foreach ($size in @('*','1','*')) { $row = [Windows.Controls.RowDefinition]::new(); $row.Height = [Windows.GridLengthConverter]::new().ConvertFromString($size); $script:AccountsHost.RowDefinitions.Add($row) }
            foreach ($card in $script:AccountCards.Values) { [Windows.Controls.Grid]::SetColumn($card.Container,0) }
            [Windows.Controls.Grid]::SetColumn($script:AccountDivider,0)
        }
        [Windows.Controls.Grid]::SetRow($script:AccountCards.Local.Container,0)
        # The detached card stays below its own toolbar, rather than following the shared grid's first row.
        [Windows.Controls.Grid]::SetRow($script:AccountCards.Remote.Container,$(if ($script:AccountLayout -eq 'Separate windows') { 1 } elseif ($script:AccountLayout -eq 'Stacked') { 2 } else { 0 }))
        [Windows.Controls.Grid]::SetRow($script:AccountDivider,$(if ($script:AccountLayout -eq 'Stacked') { 1 } else { 0 }))
        $script:LastAccountLayout = $script:AccountLayout
    }
    $picker = $script:AccountLayout -eq 'Account picker'
    $script:AccountPicker.Visibility = if ($picker -and $width -ge 170) { 'Visible' } else { 'Collapsed' }
    $script:AccountDivider.Visibility = if ($picker -or $script:AccountLayout -eq 'Separate windows') { 'Collapsed' } else { 'Visible' }
    # Let the picker use one full-height card below its optional selector.
    if ($picker) {
        $script:AccountsHost.RowDefinitions[0].Height = [Windows.GridLength]::new($(if ($script:AccountPicker.Visibility -eq 'Visible') { 29 } else { 0 }))
        $script:AccountsHost.RowDefinitions[1].Height = [Windows.GridLength]::new(1,'Star')
        $script:AccountsHost.RowDefinitions[2].Height = [Windows.GridLength]::new(0)
        foreach ($card in $script:AccountCards.Values) { [Windows.Controls.Grid]::SetRow($card.Container,1) }
        $height -= $(if ($script:AccountPicker.Visibility -eq 'Visible') { 29 } else { 0 })
    }
    foreach ($key in @('Local','Remote')) {
        if ($key -eq 'Remote' -and $script:AccountLayout -eq 'Separate windows') { continue }
        $card = $script:AccountCards[$key]
        $card.Container.Visibility = if (-not $picker -or $script:SelectedAccount -eq $key) { 'Visible' } else { 'Collapsed' }
        if ($card.Container.Visibility -eq 'Collapsed') { continue }
        $cardWidth = if ($script:AccountLayout -eq 'Side by side') { ($width - 1) / 2 } else { $width }
        $cardHeight = if ($script:AccountLayout -eq 'Stacked') { ($height - 1) / 2 } else { $height }
        # Reserve a compact identity row before giving remaining space to usage values.
        $headingHeight = Set-AccountHeadingSize $card $cardWidth $cardHeight
        $snapshot = if ($key -eq 'Local') { $script:Usage } else { $script:RemoteUsage }
        $name = if ($key -eq 'Local') { $script:LocalDisplayName } else { $script:RemoteDisplayName }
        $plan = if ($snapshot.planType) { ([string]$snapshot.planType).ToUpperInvariant() + ' · ' } else { '' }
        $status = if ($key -eq 'Remote') { Get-SharingStatus Source } elseif ($script:RefreshError) { 'Refresh failed · last reading retained' } else { 'Local account · ' + $(if ($snapshot) { 'updated ' + [DateTimeOffset]::FromUnixTimeSeconds([long]$snapshot.fetchedAt).ToLocalTime().ToString('h:mm tt') } else { 'waiting' }) }
        if ($key -eq 'Remote' -and $script:ReadError) { $status = 'File unavailable · ' + $status }
        $scheme = if ($key -eq 'Local') { $script:LocalScheme } else { $script:RemoteScheme }
        Render-AccountCard -Remote:($key -eq 'Remote') -Card $card -Snapshot $snapshot -Name $name -Status ($plan + $status) -Scheme $scheme -Width $cardWidth -Height ([Math]::Max(1,$cardHeight - $headingHeight))
    }
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
    if ($Corner -eq 'Left') { $Target.Left += $Target.Width - $width }
    $Target.Width = $width; $Target.Height = $height
}

function Save-SeparateWindowBounds {
    # Persist the imported window independently, including its own always-on-top choice.
    if (-not $script:SeparateView -or -not $script:SeparateView.Window.IsLoaded) { return }
    $peer = $script:SeparateView.Window
    $script:SeparateRemoteBounds = @{ left=$peer.Left;top=$peer.Top;width=$peer.Width;height=$peer.Height;topmost=$peer.Topmost }
    Save-WidgetState
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
    $peer.Add_SizeChanged({ if (-not $script:ChangingAccountWindows) { Update-SeparateWindow; Save-SeparateWindowBounds } })
    $peer.Add_LocationChanged({ if (-not $script:ChangingAccountWindows -and -not $script:DragOrigin) { Save-SeparateWindowBounds } })
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
    if ($window.IsVisible -or ($script:SeparateView -and $script:SeparateView.Window.IsVisible)) { $clockTimer.Start() }
    else { $clockTimer.Stop() }
}

function Update-SeparateWindows {
    # Transition windows only after startup has loaded real bounds, avoiding duplicate shells in tests.
    if ($script:ChangingAccountWindows -or -not ($window -is [Windows.Window]) -or -not $window.IsLoaded) { return }
    $separate = $script:SharedEnabled -and $script:ReadUsageEnabled -and $script:AccountLayout -eq 'Separate windows'
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
    $peer.Title = 'Codex Usage - ' + $script:RemoteDisplayName
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

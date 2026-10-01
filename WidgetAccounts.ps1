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
    $script:AccountPicker = [Windows.Controls.ComboBox]::new()
    $script:AccountPicker.Height = 23
    $script:AccountPicker.Margin = [Windows.Thickness]::new(6,2,6,4)
    foreach ($label in @('This computer','Shared computer')) { $script:AccountPicker.Items.Add($label) | Out-Null }
    $script:AccountPicker.SelectedIndex = if ($script:SelectedAccount -eq 'Remote') { 1 } else { 0 }
    $script:AccountPicker.Add_SelectionChanged({
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
        if ($script:AccountLayout -eq 'Side by side') {
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
        [Windows.Controls.Grid]::SetRow($script:AccountCards.Remote.Container,$(if ($script:AccountLayout -eq 'Stacked') { 2 } else { 0 }))
        [Windows.Controls.Grid]::SetRow($script:AccountDivider,$(if ($script:AccountLayout -eq 'Stacked') { 1 } else { 0 }))
        $script:LastAccountLayout = $script:AccountLayout
    }
    $picker = $script:AccountLayout -eq 'Account picker'
    $script:AccountPicker.Visibility = if ($picker -and $width -ge 170) { 'Visible' } else { 'Collapsed' }
    $script:AccountDivider.Visibility = if ($picker) { 'Collapsed' } else { 'Visible' }
    # Let the picker use one full-height card below its optional selector.
    if ($picker) {
        $script:AccountsHost.RowDefinitions[0].Height = [Windows.GridLength]::new($(if ($script:AccountPicker.Visibility -eq 'Visible') { 29 } else { 0 }))
        $script:AccountsHost.RowDefinitions[1].Height = [Windows.GridLength]::new(1,'Star')
        $script:AccountsHost.RowDefinitions[2].Height = [Windows.GridLength]::new(0)
        foreach ($card in $script:AccountCards.Values) { [Windows.Controls.Grid]::SetRow($card.Container,1) }
        $height -= $(if ($script:AccountPicker.Visibility -eq 'Visible') { 29 } else { 0 })
    }
    foreach ($key in @('Local','Remote')) {
        $card = $script:AccountCards[$key]
        $card.Container.Visibility = if (-not $picker -or $script:SelectedAccount -eq $key) { 'Visible' } else { 'Collapsed' }
        if ($card.Container.Visibility -eq 'Collapsed') { continue }
        $cardWidth = if ($script:AccountLayout -eq 'Side by side') { ($width - 1) / 2 } else { $width }
        $cardHeight = if ($script:AccountLayout -eq 'Stacked') { ($height - 1) / 2 } else { $height }
        # Drop names before numeric mini readouts; keep full identities and freshness on hover.
        $showName = $cardWidth -ge 125 -and $cardHeight -ge 150
        $card.HeadingPanel.Visibility = if ($showName) { 'Visible' } else { 'Collapsed' }
        $snapshot = if ($key -eq 'Local') { $script:Usage } else { $script:RemoteUsage }
        $name = if ($key -eq 'Local') { $script:LocalDisplayName } else { $script:RemoteDisplayName }
        $plan = if ($snapshot.planType) { ([string]$snapshot.planType).ToUpperInvariant() + ' · ' } else { '' }
        $status = if ($key -eq 'Remote') { Get-SharingStatus Source } elseif ($script:RefreshError) { 'Refresh failed · last reading retained' } else { 'Local account · ' + $(if ($snapshot) { 'updated ' + [DateTimeOffset]::FromUnixTimeSeconds([long]$snapshot.fetchedAt).ToLocalTime().ToString('h:mm tt') } else { 'waiting' }) }
        if ($key -eq 'Remote' -and $script:ReadError) { $status = 'File unavailable · ' + $status }
        $scheme = if ($key -eq 'Local') { $script:LocalScheme } else { $script:RemoteScheme }
        Render-AccountCard -Remote:($key -eq 'Remote') -Card $card -Snapshot $snapshot -Name $name -Status ($plan + $status) -Scheme $scheme -Width $cardWidth -Height ([Math]::Max(1,$cardHeight - $(if ($showName) { 36 } else { 0 })))
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
        }
    }
    $index = @('Mini','Small','Medium','Large / Default').IndexOf($Name)
    $window.Width = $sizes[$index][0]
    $window.Height = $sizes[$index][1]
    Update-Display
    Save-WidgetState
}

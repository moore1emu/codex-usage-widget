# Keep resource preferences and readings local; quota exports deliberately omit them.
$script:ResourceOptions = @{ Local=$false; Claude=$false }
# Keep one shared hardware placement, with independent local monitoring switches.
$script:ResourcePlacement = 'Side column'
$script:ResourceReadings = @{}
$script:ResourceNextSample = [DateTimeOffset]::MinValue

function Get-ResourcePlacement {
    param([string]$Key,[double]$Width,[double]$Height)
    # Imported accounts never acquire local hardware readings or a placement preference.
    if (-not $script:ResourceOptions[$Key]) { return 'Off' }
    $choice=$script:ResourcePlacement
    if ($choice -eq 'Automatic') {
        # Use a footer when a roomy panel can carry a readable strip, retaining columns in compact shapes.
        return $(if ($Width -ge 240 -and $Height -ge 140) {'Bottom bar'} else {'Side column'})
    }
    return $choice
}

function Get-AppResourceSnapshot {
    param([int]$WidgetProcessId, [int]$SessionId)
    # Read process identities once off the UI thread; never inspect command lines or credentials.
    $processes = @(Get-CimInstance Win32_Process -OperationTimeoutSec 5 -ErrorAction Stop | Where-Object SessionId -eq $SessionId)
    $byId = @{}
    foreach ($process in $processes) { $byId[[int]$process.ProcessId]=$process }
    # Exclude the widget and all helpers it starts, even when Codex originally launched it.
    $excluded = [Collections.Generic.HashSet[int]]::new()
    [void]$excluded.Add($WidgetProcessId)
    do {
        $added=$false
        foreach ($process in $processes) {
            if ($excluded.Contains([int]$process.ParentProcessId) -and $excluded.Add([int]$process.ProcessId)) { $added=$true }
        }
    } while ($added)
    # Sample private working set and normalized CPU, avoiding shared-page double counting.
    $performance = @{}
    foreach ($counter in @(Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -OperationTimeoutSec 5 -ErrorAction Stop)) { $performance[[int]$counter.IDProcess]=$counter }
    $cpuCount=[Math]::Max(1,[Environment]::ProcessorCount)
    # GPU counters are optional; unavailable support must not become a misleading zero.
    $gpu=$null
    try { $gpu=@(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -OperationTimeoutSec 5 -ErrorAction Stop) } catch { }
    $result=@{}
    foreach ($app in @('Local','Claude')) {
        # Recognize versioned desktop package paths, including Codex's ChatGPT.exe name.
        $pattern=if ($app -eq 'Local') {'[\\/]OpenAI\.Codex_[^\\/]+[\\/]'} else {'[\\/]Claude_[^\\/]+[\\/]'}
        $name=if ($app -eq 'Local') {'ChatGPT.exe'} else {'claude.exe'}
        $ids=[Collections.Generic.HashSet[int]]::new()
        foreach ($process in $processes) {
            if ($process.Name -ieq $name -and $process.ExecutablePath -match $pattern -and -not $excluded.Contains([int]$process.ProcessId)) { [void]$ids.Add([int]$process.ProcessId) }
        }
        # Follow only verified descendants; creation time prevents recycled parent IDs from joining.
        do {
            $added=$false
            foreach ($process in $processes) {
                $parent=$byId[[int]$process.ParentProcessId]
                if ($parent -and $ids.Contains([int]$parent.ProcessId) -and $parent.CreationDate -le $process.CreationDate -and -not $excluded.Contains([int]$process.ProcessId) -and $ids.Add([int]$process.ProcessId)) { $added=$true }
            }
        } while ($added)
        if (-not $ids.Count) { $result[$app]=@{ Available=$false; Reason='Desktop app not running or inaccessible' }; continue }
        $cpu=0.0; $memory=0.0; $matched=0
        foreach ($id in $ids) {
            if ($performance.ContainsKey($id)) {
                $counter=$performance[$id]; $matched++
                $cpu += [double]$counter.PercentProcessorTime / $cpuCount
                $memory += [double]$counter.WorkingSetPrivate
            }
        }
        # Sum this app's processes within each physical GPU engine, then report the busiest engine.
        $engines=@{}
        foreach ($counter in $gpu) {
            if ($counter.Name -match '^pid_(\d+)_(.+)$' -and $ids.Contains([int]$Matches[1])) {
                $engine=$Matches[2]; $engines[$engine]=[double]$engines[$engine]+[double]$counter.UtilizationPercentage
            }
        }
        $gpuValue=if ($null -eq $gpu) {$null} elseif ($engines.Count) { [Math]::Min(100,($engines.Values | Measure-Object -Maximum).Maximum) } else {0}
        $result[$app]=@{ Available=($matched -gt 0); Cpu=[Math]::Min(100,$cpu); Memory=$memory; Gpu=$gpuValue; Count=$ids.Count; SampledAt=[DateTimeOffset]::Now }
    }
    return $result
}

function Format-ResourceMemory {
    param([double]$Bytes,[switch]$Detailed)
    # Keep the requested MB/GB threshold; show whole numbers while hover details can retain precision.
    $mb=$Bytes/1000000
    if ($mb -gt 1000) { return $(if ($Detailed) { '{0:0.00} GB' -f ($mb/1000) } else { '{0:0} GB' -f ($mb/1000) }) }
    return ('{0:0} MB' -f $mb)
}

function New-ResourceRow {
    # Build independent text controls so labels can shrink without losing the colored values.
    $panel=[Windows.Controls.StackPanel]::new(); $panel.Orientation='Horizontal'
    $panel.HorizontalAlignment='Center'; $panel.Margin=[Windows.Thickness]::new(3,2,3,2); $panel.Visibility='Collapsed'
    $items=@(); $labels=@(); $cells=@()
    foreach ($metric in @('CPU','RAM','GPU')) {
        $text=[Windows.Controls.TextBlock]::new(); $text.Foreground='#DDE3EF'; $text.FontSize=11
        # Separate names and values into real columns rather than spacing a combined string.
        $label=[Windows.Controls.TextBlock]::new(); $label.Text=$metric; $label.HorizontalAlignment='Left'; $label.VerticalAlignment='Center'
        $cell=[Windows.Controls.Grid]::new(); $cell.HorizontalAlignment='Left'; $cell.Margin=[Windows.Thickness]::new(0,0,3,0)
        [void]$cell.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())
        $valueColumn=[Windows.Controls.ColumnDefinition]::new(); $valueColumn.Width=[Windows.GridLength]::Auto; [void]$cell.ColumnDefinitions.Add($valueColumn)
        [Windows.Controls.Grid]::SetColumn($text,1); $text.HorizontalAlignment='Left'; $text.VerticalAlignment='Center'
        [void]$cell.Children.Add($label); [void]$cell.Children.Add($text)
        [void]$panel.Children.Add($cell); $items+=$text; $labels+=$label; $cells+=$cell
    }
    $items[2].Margin=[Windows.Thickness]::new(0)
    # Scale the complete resource group at tiny sizes instead of hiding individual values.
    $resourceHost=[Windows.Controls.Viewbox]::new(); $resourceHost.Child=$panel; $resourceHost.Stretch='Uniform'; $resourceHost.StretchDirection='DownOnly'
    $resourceHost.VerticalAlignment='Center'; $resourceHost.Visibility='Collapsed'
    # Give normal rows independent scale boxes so long RAM text cannot shift the other row positions.
    $aligned=[Windows.Controls.Canvas]::new(); $aligned.Visibility='Collapsed'
    $boxes=@()
    for ($index=0;$index -lt 3;$index++) {
        $box=[Windows.Controls.Viewbox]::new(); $box.Stretch='Uniform'; $box.StretchDirection='DownOnly'
        [void]$aligned.Children.Add($box); $boxes+=$box
    }
    $container=[Windows.Controls.Grid]::new(); $container.Visibility='Collapsed'
    [void]$container.Children.Add($resourceHost); [void]$container.Children.Add($aligned)
    return @{Panel=$panel;Host=$container;Group=$resourceHost;Aligned=$aligned;Boxes=$boxes;Items=$items;Labels=$labels;Cells=$cells;NaturalWidth=1}
}

function Update-ResourceRow {
    param($Row,[string]$Key,[double]$Width,[double]$Height,[switch]$HideLabels,[double]$FontSize=11,[switch]$SingleLine,[string[]]$Colors,[hashtable]$SharedLayout,[switch]$ProbeLayout)
    # Enabled hardware values persist through every layout; unavailable readings retain their placeholders.
    $Row.Panel.Visibility='Collapsed'; $Row.Host.Visibility='Collapsed'
    # Restore the simple group before selecting the next responsive layout.
    foreach ($box in $Row.Boxes) { $box.Child=$null }
    $Row.Panel.Children.Clear()
    foreach ($cell in $Row.Cells) { $cell.Width=[double]::NaN; [void]$Row.Panel.Children.Add($cell) }
    $Row.Group.Visibility='Visible'; $Row.Aligned.Visibility='Collapsed'
    if (-not $script:ResourceOptions[$Key]) { return 0 }
    $reading=$script:ResourceReadings[$Key]
    $available=$reading.Available -and ([DateTimeOffset]::Now-$reading.SampledAt).TotalSeconds -lt 15
    $values=if ($available) { @('{0:0}%' -f $reading.Cpu; Format-ResourceMemory $reading.Memory; $(if ($null -ne $reading.Gpu) {'{0:0}%' -f $reading.Gpu} else {'—'})) } else {@('—','—','—')}
    $labels=@('CPU','RAM','GPU')
    $measure=[Windows.Size]::new([double]::PositiveInfinity,[double]::PositiveInfinity)
    $labelWidth=0; $valueWidth=0
    # Follow the quota label stage, preserving units while compacting unnecessary spaces and dots.
    for ($index=0;$index -lt 3;$index++) {
        $item=$Row.Items[$index]; $item.FontSize=$FontSize; $item.Margin=[Windows.Thickness]::new(0)
        # Follow this account's quota palette: CPU uses 5-hour, RAM weekly, and GPU credits.
        if ($Colors.Count -eq 3) { $item.Foreground=$Colors[$index] }
        $item.FontWeight=if ($HideLabels) {'SemiBold'} else {'Normal'}
        $item.Text=if ($HideLabels) {$values[$index] -replace ' ',''} else {$values[$index]}
        $caption=$Row.Labels[$index]; $caption.FontSize=$FontSize; $caption.Foreground=$item.Foreground
        $caption.Visibility=if ($HideLabels) {'Collapsed'} else {'Visible'}
        $caption.Measure($measure); $item.Measure($measure)
        $labelWidth=[Math]::Max($labelWidth,$caption.DesiredSize.Width); $valueWidth=[Math]::Max($valueWidth,$item.DesiredSize.Width)
        $detail=if ($index -eq 1 -and $available) {Format-ResourceMemory $reading.Memory -Detailed} else {$values[$index]}
        $item.ToolTip=$labels[$index]+': '+$detail+$(if ($available) {"`nLocal desktop app and child processes: $($reading.Count)`nSampled $($reading.SampledAt.ToLocalTime().ToString('h:mm:ss tt'))"} else {"`nNo recent desktop resource reading"})
        $caption.ToolTip=$item.ToolTip
    }
    # Connected accounts measure one common hardware width so different MB/GB lengths cannot shift value starts.
    if ($SharedLayout) {
        if ($ProbeLayout) {
            $SharedLayout.ResourceNameWidth=[Math]::Max([double]$SharedLayout.ResourceNameWidth,$labelWidth)
            $SharedLayout.ResourceValueWidth=[Math]::Max([double]$SharedLayout.ResourceValueWidth,$valueWidth)
        } else { $labelWidth=[double]$SharedLayout.ResourceNameWidth; $valueWidth=[double]$SharedLayout.ResourceValueWidth }
    }
    # Use one name-column width and one scale width for all hardware rows, preserving both left edges.
    $nameTrack=if ($HideLabels) {0} else {$labelWidth+5}
    $Row.NaturalWidth=$nameTrack+$valueWidth
    foreach ($cell in $Row.Cells) { $cell.ColumnDefinitions[0].Width=[Windows.GridLength]::new($nameTrack) }
    # A one-line widget keeps the three readings in one line too; taller cards stack them vertically.
    $Row.Panel.Orientation=if ($SingleLine) {'Horizontal'} else {'Vertical'}
    # Anchor the footer to its left edge instead of centering the scaled hardware group.
    $Row.Group.HorizontalAlignment=if ($SingleLine) {'Left'} else {'Stretch'}
    $Row.Panel.HorizontalAlignment=if ($SingleLine) {'Left'} else {'Center'}
    if ($Row.Panel.Orientation -eq 'Horizontal') {
        for ($index=0;$index -lt 3;$index++) { $Row.Items[$index].Margin=[Windows.Thickness]::new(0,0,$(if ($index -eq 2) {0} else {3}),0) }
    }
    # Bound the whole group to its allocated column; uniform scaling keeps every number inside it.
    $Row.Host.Width=[Math]::Max(1,$Width); $Row.Host.MaxHeight=[Math]::Max(1,$Height)
    $Row.Group.MaxHeight=[Math]::Max(1,$Height)
    $Row.Panel.Visibility='Visible'; $Row.Host.Visibility='Visible'
    return [Math]::Max(1,$Width)
}

function Set-ResourceRowAlignment {
    param($Card)
    $row=$Card.Resources
    # Follow final WPF coordinates after resize; menu-height readings retain their single-line group.
    if ($row.Aligned.Visibility -ne 'Visible' -or -not $row.Host.IsVisible) { return }
    $bindings=$Card.Bindings
    $targets=if ($bindings.ultraCompactPanel.Visibility -eq 'Visible') {
        @($bindings.compactPrimaryPercent,$bindings.compactSecondaryPercent,$bindings.compactCreditsText)
    } else { @($bindings.primaryPercent,$bindings.secondaryPercent,$bindings.creditsText) }
    for ($index=0;$index -lt 3;$index++) {
        $target=$targets[$index]
        # Hidden credit slots still have a row; full views derive its location from the grid tracks.
        if ($index -eq 2 -and $bindings.creditsArea.Visibility -ne 'Visible' -and $bindings.ultraCompactPanel.Visibility -ne 'Visible') {
            $grid=$bindings.outerBorder.Child
            $top=0; for ($track=0;$track -lt 3;$track++) { $top+=$grid.RowDefinitions[$track].ActualHeight }
            $center=$grid.TranslatePoint([Windows.Point]::new(0,$top+13.5),$row.Host).Y
            $height=27
            $reference=$bindings.primaryPercent
            $baseline=$center+$reference.BaselineOffset-$reference.ActualHeight/2
        } else {
            $height=[Math]::Max(1,$target.ActualHeight)
            $baseline=$target.TranslatePoint([Windows.Point]::new(0,$target.BaselineOffset),$row.Host).Y
        }
        # Position only when geometry changes, avoiding another layout cycle on steady countdown ticks.
        # Scale equal-width name/value grids so neither column shifts with different value lengths.
        $box=$row.Boxes[$index]; $width=[Math]::Max(1,[Math]::Min($row.NaturalWidth,$row.Host.ActualWidth-6))
        if ([Math]::Abs($box.Width-$width) -gt 0.1 -or [double]::IsNaN($box.Width)) { $box.Width=$width }
        if ([Math]::Abs($box.Height-$height) -gt 0.1 -or [double]::IsNaN($box.Height)) { $box.Height=$height }
        # Use the actual transformed glyph baseline, including WPF scaling and pixel rounding.
        $actualBaseline=$row.Items[$index].TranslatePoint([Windows.Point]::new(0,$row.Items[$index].BaselineOffset),$row.Host).Y
        $currentTop=[Windows.Controls.Canvas]::GetTop($box)
        if ([double]::IsNaN($currentTop)) { $currentTop=0 }
        $position=$currentTop+$baseline-$actualBaseline
        if ([Math]::Abs([Windows.Controls.Canvas]::GetTop($box)-$position) -gt 0.1 -or [double]::IsNaN([Windows.Controls.Canvas]::GetTop($box))) { [Windows.Controls.Canvas]::SetTop($box,$position) }
        [Windows.Controls.Canvas]::SetLeft($box,3)
    }
}

function Enable-AlignedResourceRows {
    param($Row)
    # Reuse the existing colored readings and their hover help in the matching quota rows.
    $Row.Panel.Children.Clear()
    for ($index=0;$index -lt 3;$index++) {
        $Row.Items[$index].Margin=[Windows.Thickness]::new(0)
        $Row.Cells[$index].Width=$Row.NaturalWidth
        $Row.Cells[$index].Margin=[Windows.Thickness]::new(0)
        $Row.Boxes[$index].Child=$Row.Cells[$index]
    }
    $Row.Group.Visibility='Collapsed'; $Row.Aligned.Visibility='Visible'
}

function Stop-ResourceSampling {
    # Cancel and dispose background work when disabled or shutting down.
    if ($script:ResourceWorker) {
        $script:ResourceWorker.Stop(); $script:ResourceWorker.Dispose()
        $script:ResourceWorker=$null; $script:ResourceOperation=$null
    }
}

function Invoke-ResourceTick {
    # Poll a completed background task without blocking window interaction or dropdowns.
    if ($script:ResourceWorker -and $script:ResourceOperation.IsCompleted) {
        try {
            $output=$script:ResourceWorker.EndInvoke($script:ResourceOperation)
            if ($output.Count) { $script:ResourceReadings=$output[0] }
        } catch { $script:ResourceReadings=@{} }
        finally { $script:ResourceWorker.Dispose(); $script:ResourceWorker=$null; $script:ResourceOperation=$null }
    }
    # Hidden windows need no live display readings; never overlap collection requests.
    $wanted=($script:LocalEnabled -and $script:ResourceOptions.Local) -or ($script:ClaudeOptions.Enabled -and $script:ResourceOptions.Claude)
    $visible=$window.IsVisible -or ($script:ClaudeView -and $script:ClaudeView.Window.IsVisible)
    if (-not $wanted -or -not $visible) { Stop-ResourceSampling; return }
    if ($script:ResourceWorker -or [DateTimeOffset]::Now -lt $script:ResourceNextSample) { return }
    # Isolate slow Windows counters in one reusable PowerShell worker per sample.
    $script:ResourceNextSample=[DateTimeOffset]::Now.AddSeconds(3)
    $script:ResourceWorker=[PowerShell]::Create()
    [void]$script:ResourceWorker.AddScript(${function:Get-AppResourceSnapshot}.ToString()).AddArgument($PID).AddArgument([Diagnostics.Process]::GetCurrentProcess().SessionId)
    $script:ResourceOperation=$script:ResourceWorker.BeginInvoke()
}

# Exercise the real resource controls with synthetic processes and counters only.
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
function Assert-Resource($Condition,[string]$Message) { if (-not $Condition) { Close-TestWidget; throw $Message } }
Assert-Resource ((Format-ResourceMemory 1000000000) -eq '1000 MB') 'Threshold should stay in MB.'
Assert-Resource ((Format-ResourceMemory 1280000000) -eq '1 GB') 'RAM should switch to decimal GB.'
# Give the widget a child within Codex's tree to verify neither enters app totals.
$created=[datetime]'2026-01-01'
$script:FakeProcesses=@(
    @{ProcessId=10;ParentProcessId=1;Name='ChatGPT.exe';ExecutablePath='C:\Program Files\WindowsApps\OpenAI.Codex_1\app\ChatGPT.exe';SessionId=2;CreationDate=$created},
    @{ProcessId=11;ParentProcessId=10;Name='ChatGPT.exe';SessionId=2;CreationDate=$created.AddSeconds(1)},
    @{ProcessId=12;ParentProcessId=10;Name='node.exe';SessionId=2;CreationDate=$created.AddSeconds(1)},
    @{ProcessId=20;ParentProcessId=10;Name='pwsh.exe';SessionId=2;CreationDate=$created.AddSeconds(1)},
    @{ProcessId=21;ParentProcessId=20;Name='msedgewebview2.exe';SessionId=2;CreationDate=$created.AddSeconds(2)},
    @{ProcessId=30;ParentProcessId=1;Name='claude.exe';ExecutablePath='C:\Program Files\WindowsApps\Claude_1\app\claude.exe';SessionId=2;CreationDate=$created},
    @{ProcessId=40;ParentProcessId=1;Name='ChatGPT Classic.exe';ExecutablePath='C:\Program Files\WindowsApps\OpenAI.ChatGPT-Desktop_1\app\ChatGPT Classic.exe';SessionId=2;CreationDate=$created},
    @{ProcessId=41;ParentProcessId=10;Name='unrelated.exe';SessionId=2;CreationDate=$created.AddSeconds(-1)}
)
# Mock only the Windows collection boundary, preserving production grouping and aggregation.
function Get-CimInstance {
    param([string]$ClassName,$ErrorAction,$OperationTimeoutSec)
    switch ($ClassName) {
        Win32_Process { return $script:FakeProcesses }
        Win32_PerfFormattedData_PerfProc_Process {
            foreach ($id in @(10,11,12,20,21,30,40,41)) { @{IDProcess=$id;PercentProcessorTime=20;WorkingSetPrivate=1000000} }
        }
        Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine {
            if ($script:NoGpu) { throw 'GPU unavailable' }
            @{Name='pid_10_luid_1_phys_0_eng_0_engtype_3D';UtilizationPercentage=20}
            @{Name='pid_11_luid_1_phys_0_eng_0_engtype_3D';UtilizationPercentage=30}
            @{Name='pid_12_luid_1_phys_0_eng_1_engtype_Copy';UtilizationPercentage=40}
            @{Name='pid_21_luid_1_phys_0_eng_0_engtype_3D';UtilizationPercentage=99}
        }
    }
}
$sample=Get-AppResourceSnapshot -WidgetProcessId 20 -SessionId 2
Assert-Resource ($sample.Local.Count -eq 3 -and $sample.Local.Memory -eq 3000000) 'App grouping included unrelated or widget processes.'
Assert-Resource ($sample.Local.Gpu -eq 50) 'GPU should report the busiest combined engine.'
Assert-Resource ((Format-ResourceMemory 1280000000 -Detailed) -eq '1.28 GB') 'Detailed memory should retain its precision.'
Assert-Resource ([Math]::Abs($sample.Local.Cpu-(60/[Environment]::ProcessorCount)) -lt 0.001) 'CPU must normalize across logical processors.'
$script:NoGpu=$true
$sample=Get-AppResourceSnapshot -WidgetProcessId 20 -SessionId 2
Assert-Resource ($null -eq $sample.Local.Gpu) 'Missing GPU support must remain unavailable.'
# Retain all three readings even when the complete group must scale to a mini or thin view.
$script:ResourceOptions.Local=$true; $script:ResourceOptions.Claude=$true
$script:ResourceReadings.Local=@{Available=$true;Cpu=3;Memory=1280000000;Gpu=1;Count=3;SampledAt=[DateTimeOffset]::Now}
$script:ResourceReadings.Claude=@{Available=$true;Cpu=2;Memory=610000000;Gpu=0;Count=3;SampledAt=[DateTimeOffset]::Now}
$row=New-ResourceRow
[void](Update-ResourceRow $row Local 110 300)
Assert-Resource ($row.Items[0].Text -eq '3%' -and $row.Labels[0].Visibility -eq 'Visible' -and $row.Host.Visibility -eq 'Visible') 'Labeled resources should be visible.'
[void](Update-ResourceRow $row Local 30 50 -HideLabels)
Assert-Resource ($row.Items[0].Text -eq '3%' -and $row.Items[1].Text -eq '1GB' -and $row.Items[2].Text -eq '1%' -and $row.Host.Visibility -eq 'Visible') 'Mini resources must retain all three values without labels.'
[void](Update-ResourceRow $row Local 110 14 -HideLabels -SingleLine)
Assert-Resource ($row.Host.Visibility -eq 'Visible' -and $row.Panel.Orientation -eq 'Horizontal') 'Thin views must retain the full resource group on one line.'
# Check every connected layout through full, narrow, mini, and menu-height dimensions.
$script:ClaudeOptions.Enabled=$true; $script:ClaudeUsage=$script:Usage
$window.Show()
foreach ($layout in @('Side by side','Stacked','Account picker')) {
    $script:AccountLayout=$layout
    foreach ($size in @(@(600,840),@(490,604),@(600,300),@(360,240),@(300,180),@(150,144),@(600,70))) {
        $window.Width=$size[0]; $window.Height=$size[1]
        Wait-TestDispatcher 50
        foreach ($reading in $script:ResourceReadings.Values) {$reading.SampledAt=[DateTimeOffset]::Now}
        Update-Display; $window.UpdateLayout(); Wait-TestDispatcher 20; $window.UpdateLayout()
        $cards=if ($layout -eq 'Account picker') {@($script:AccountCards[$script:SelectedAccount])} else {@($script:AccountCards.Local,$script:AccountCards.Claude)}
        foreach ($card in $cards) {
            Assert-Resource ($card.Resources.Host.Visibility -eq 'Visible' -and $card.Resources.Items.Count -eq 3) ('Enabled readings disappeared in '+$layout+' at '+($size -join 'x'))
            Assert-Resource ($card.Container.RowDefinitions[3].Height.Value -eq 0 -and $card.Container.ColumnDefinitions[1].Width.Value -gt 0) 'Persistent resource columns should consume only width.'
            $bindings=$card.Bindings
            $quotaLabels=$bindings.primaryArea.Visibility -eq 'Visible' -or ($bindings.ultraCompactPanel.Visibility -eq 'Visible' -and $bindings.compactPrimaryCaption.Visibility -eq 'Visible')
            if ($bindings.inlineUsagePanel.Visibility -eq 'Visible') {$quotaLabels=$bindings.inlineUsagePanel.Child.Children[1].Visibility -eq 'Visible'}
            # Check the visible row structure after repeated transitions, not just formatted strings.
            if ($bindings.ultraCompactPanel.Visibility -eq 'Visible') {
                Assert-Resource ($bindings.ultraCompactPanel.Child.ColumnDefinitions.Count -eq 0) 'Compact quotas should use stacked rows.'
                foreach ($quota in $card.CompactRows) {
                    Assert-Resource ($quota.Line.Children.Count -eq 2 -and $quota.Value.Parent -eq $quota.Line) 'Compact labels and values must remain together after resizing.'
                }
                Assert-Resource ($bindings.compactPrimaryCaption.FontSize -eq $bindings.compactPrimaryPercent.FontSize) 'Compact labels should match their numeric font size.'
            }
            Assert-Resource (($card.Resources.Labels[0].Visibility -eq 'Visible') -eq $quotaLabels) 'Resource names must follow the actual 5-hour label visibility.'
            Assert-Resource ($card.Resources.Host.ActualWidth -le $card.Container.ColumnDefinitions[1].Width.Value+0.1 -and $card.Resources.Host.ActualHeight -gt 0) 'Resource group should stay inside its column with actual drawing height.'
            foreach ($item in $card.Resources.Items) { Assert-Resource ($item.IsVisible -and $item.ActualWidth -gt 0 -and $item.ActualHeight -gt 0) 'Every hardware value must have visible text bounds.' }
            # Quota names and values have independent, stable left edges in full and compact rows.
            if ($bindings.primaryArea.Visibility -eq 'Visible' -or ($bindings.ultraCompactPanel.Visibility -eq 'Visible' -and $quotaLabels)) {
                $names=if ($bindings.primaryArea.Visibility -eq 'Visible') {@($bindings.primaryLabel,$bindings.secondaryLabel)} else {@($bindings.compactPrimaryCaption,$bindings.compactSecondaryCaption)}
                $values=if ($bindings.primaryArea.Visibility -eq 'Visible') {@($bindings.primaryPercent,$bindings.secondaryPercent)} else {@($bindings.compactPrimaryPercent,$bindings.compactSecondaryPercent)}
                if ($bindings.creditsArea.Visibility -eq 'Visible') {$names+=$bindings.creditsLabel;$values+=$bindings.creditsText}
                for ($index=0;$index -lt $names.Count;$index++) {
                    $nameBaseline=$names[$index].TranslatePoint([Windows.Point]::new(0,$names[$index].BaselineOffset),$card.Container).Y
                    $valueBaseline=$values[$index].TranslatePoint([Windows.Point]::new(0,$values[$index].BaselineOffset),$card.Container).Y
                    Assert-Resource ([Math]::Abs($nameBaseline-$valueBaseline) -lt 0.5) 'Usage name and value baselines did not line up.'
                }
                foreach ($column in @(@{Items=$names},@{Items=$values})) {
                    $reference=$column.Items[0].TranslatePoint([Windows.Point]::new(0,0),$card.Container).X
                    foreach ($text in $column.Items) {
                        $left=$text.TranslatePoint([Windows.Point]::new(0,0),$card.Container).X
                        Assert-Resource ([Math]::Abs($left-$reference) -lt 1) 'Quota column first characters did not line up.'
                    }
                }
            }
            # Compare actual drawn centers after WPF transforms, including narrow RAM scaling.
            if ($card.Resources.Aligned.Visibility -eq 'Visible') {
                $targets=if ($bindings.ultraCompactPanel.Visibility -eq 'Visible') { @($bindings.compactPrimaryPercent,$bindings.compactSecondaryPercent,$bindings.compactCreditsText) } else { @($bindings.primaryPercent,$bindings.secondaryPercent,$bindings.creditsText) }
                for ($index=0;$index -lt 3;$index++) {
                    $item=$card.Resources.Items[$index]
                    $actual=$item.TranslatePoint([Windows.Point]::new(0,$item.ActualHeight/2),$card.Container).Y
                    # Text with different lengths must start at the same hardware-column edge.
                    $left=$item.TranslatePoint([Windows.Point]::new(0,0),$card.Resources.Host).X
                    $referenceLeft=$card.Resources.Items[0].TranslatePoint([Windows.Point]::new(0,0),$card.Resources.Host).X
                    Assert-Resource ([Math]::Abs($left-$referenceLeft) -lt 1) 'Hardware values should share the same first-character position.'
                    if ($quotaLabels) {
                        $nameLeft=$card.Resources.Labels[$index].TranslatePoint([Windows.Point]::new(0,0),$card.Resources.Host).X
                        Assert-Resource ([Math]::Abs($nameLeft-3) -lt 1) 'Hardware names should share the same left edge.'
                    }
                    if ($index -eq 2 -and $bindings.creditsArea.Visibility -ne 'Visible' -and $bindings.ultraCompactPanel.Visibility -ne 'Visible') {
                        $grid=$bindings.outerBorder.Child
                        Assert-Resource ($grid.RowDefinitions[3].ActualHeight -ge 27) 'GPU needs a reserved credit track when no balance exists.'
                        $top=0; for ($track=0;$track -lt 3;$track++) { $top+=$grid.RowDefinitions[$track].ActualHeight }
                        $expected=$grid.TranslatePoint([Windows.Point]::new(0,$top+13.5),$card.Container).Y
                    } else { $expected=$targets[$index].TranslatePoint([Windows.Point]::new(0,$targets[$index].ActualHeight/2),$card.Container).Y }
                    # Compare glyph baselines too, detecting top-aligned values beside centered labels.
                    if ($targets[$index].IsVisible) {
                        $expectedBaseline=$targets[$index].TranslatePoint([Windows.Point]::new(0,$targets[$index].BaselineOffset),$card.Container).Y
                        $actualBaseline=$item.TranslatePoint([Windows.Point]::new(0,$item.BaselineOffset),$card.Container).Y
                        Assert-Resource ([Math]::Abs($actualBaseline-$expectedBaseline) -lt 0.5) 'Hardware and quota baselines did not line up.'
                    }
                    # A reserved empty credit track has no glyph; only that slot uses a center comparison.
                    if (-not $targets[$index].IsVisible -and $bindings.ultraCompactPanel.Visibility -ne 'Visible') {
                        Assert-Resource ([Math]::Abs($actual-$expected) -lt 2) 'GPU drifted from the reserved credit track.'
                    }
                }
            }

        }
        if ($layout -ne 'Account picker') { Assert-Resource ($cards[0].Container.ColumnDefinitions[1].Width.Value -eq $cards[1].Container.ColumnDefinitions[1].Width.Value) 'Connected resource columns must stay aligned.' }
        # Different memory units must not shift the hardware value column between connected accounts.
        if ($layout -ne 'Account picker' -and $cards[0].Resources.Aligned.Visibility -eq 'Visible') {
            $first=$cards[0].Resources.Items[0].TranslatePoint([Windows.Point]::new(0,0),$cards[0].Container).X
            $second=$cards[1].Resources.Items[0].TranslatePoint([Windows.Point]::new(0,0),$cards[1].Container).X
            Assert-Resource ([Math]::Abs($first-$second) -lt 1) 'Connected hardware values used different column starts.'
        }

    }
}
# Restore a horizontal footer at every size and keep connected quota spacing consistent.
$script:ResourcePlacement='Bottom bar'
foreach ($layout in @('Side by side','Stacked','Account picker')) {
    $script:AccountLayout=$layout
    foreach ($size in @(@(600,600),@(300,240),@(150,144),@(600,70))) {
        $window.Width=$size[0]; $window.Height=$size[1]; Wait-TestDispatcher 30
        Update-Display; Wait-TestDispatcher 20; $window.UpdateLayout()
        $cards=if ($layout -eq 'Account picker') {@($script:AccountCards[$script:SelectedAccount])} else {@($script:AccountCards.Local,$script:AccountCards.Claude)}
        foreach ($card in $cards) {
            Assert-Resource ($card.ResourcePlacement -eq 'Bottom bar' -and [Windows.Controls.Grid]::GetRow($card.Resources.Host) -eq 3) 'Bottom placement did not restore the footer.'
            Assert-Resource ($card.Resources.Host.IsVisible -and $card.Resources.Panel.Orientation -eq 'Horizontal' -and $card.Container.ColumnDefinitions[1].Width.Value -eq 0) 'Footer should reclaim the resource column and retain all readings.'
            foreach ($item in $card.Resources.Items) { Assert-Resource ($item.IsVisible -and $item.ActualHeight -gt 0) 'A footer value disappeared while shrinking.' }
        }
    }
}
# Automatic placement follows each actual account panel, with one placement governing both local accounts.
$script:AccountLayout='Stacked'; $script:ResourcePlacement='Automatic'
$window.Width=600; $window.Height=600; Wait-TestDispatcher 30; Update-Display
Assert-Resource ($script:AccountCards.Local.ResourcePlacement -eq 'Bottom bar') 'Automatic should use a footer in a roomy panel.'
$window.Width=150; $window.Height=144; Wait-TestDispatcher 30; Update-Display
Assert-Resource ($script:AccountCards.Local.ResourcePlacement -eq 'Side column') 'Automatic should retain columns in compact panels.'
# A single choice governs both local accounts.
$script:ResourcePlacement='Bottom bar'; Update-Display
Assert-Resource ($script:AccountCards.Local.ResourcePlacement -eq 'Bottom bar' -and $script:AccountCards.Claude.ResourcePlacement -eq 'Bottom bar') 'The common placement did not apply to both accounts.'
$script:ResourcePlacement='Side column'
# Detached Claude uses the same persistent column even at its mini size.
$script:ClaudeOptions.Placement='Separate window'; Update-Display; Wait-TestDispatcher 50
$script:ClaudeView.Window.Width=72; $script:ClaudeView.Window.Height=72
Wait-TestDispatcher 50; Update-Display
Assert-Resource ($script:AccountCards.Claude.Resources.Host.Visibility -eq 'Visible') 'Detached mini view must keep its resource group.'
# Verify detached mini readings line up too, rather than only checking their visibility.
$script:ClaudeView.Window.UpdateLayout()
$detached=$script:AccountCards.Claude
for ($index=0;$index -lt 3;$index++) {
    $item=$detached.Resources.Items[$index]; $value=$detached.CompactRows[$index].Value
    $actual=$item.TranslatePoint([Windows.Point]::new(0,$item.BaselineOffset),$detached.Container).Y
    $expected=$value.TranslatePoint([Windows.Point]::new(0,$value.BaselineOffset),$detached.Container).Y
    Assert-Resource ([Math]::Abs($actual-$expected) -lt 1) 'Detached hardware readings must follow their compact quota rows.'
}

$script:ClaudeOptions.Placement='Follow layout'
# A lone local account also keeps resources in its smallest supported window.
$script:ClaudeOptions.Enabled=$false; $script:SharedEnabled=$false; $script:AccountLayout='Stacked'
$window.Width=72; $window.Height=72; Wait-TestDispatcher 50; Update-Display
Assert-Resource ($script:AccountCards.Local.Resources.Host.Visibility -eq 'Visible' -and $script:AccountCards.Local.Resources.Panel.Orientation -eq 'Vertical') 'Single-account mini view must retain hardware values in three rows.'
Save-WidgetState
$saved=Get-Content -LiteralPath (Join-Path $script:TestState 'widget-state.json') -Raw | ConvertFrom-Json
Assert-Resource ($saved.resourceOptions.Local -eq $true -and $saved.resourcePlacement -eq 'Side column') 'Resource switches and placement should persist locally.'
# Check migration and real settings Apply/Cancel without contacting either account service.
$script:ResourceOptions.Local=$false
Restore-ClaudeSettings $saved
Assert-Resource $script:ResourceOptions.Local 'Restart should restore the local resource switch.'
Assert-Resource ($script:ResourcePlacement -eq 'Side column') 'Restart should restore the common placement.'
Restore-ClaudeSettings @{resourceOptions=@{Local=$true;Claude=$true};resourcePlacements=@{Local='Bottom bar';Claude='Side column'}}
Assert-Resource ($script:ResourcePlacement -eq 'Bottom bar') 'Upgrade should prefer the monitored Codex placement when both accounts differ.'
Restore-ClaudeSettings @{localEnabled=$false;resourceOptions=@{Local=$false;Claude=$true};resourcePlacements=@{Local='Side column';Claude='Automatic'}}
Assert-Resource ($script:ResourcePlacement -eq 'Automatic') 'Claude-only upgrade should retain its active placement.'
Restore-ClaudeSettings $saved

$settings=[IO.File]::ReadAllText((Join-Path $script:TestProject 'WidgetSettings.ps1'))
$settings=$settings.Replace('$dialog.Show()',@'
        $dialog.Show()
        try {
            $controls.LocalResources.Checked=$false; $controls.ClaudeResources.Checked=$true
            Assert-Resource ($controls.LocalResources.Parent -eq $tables.Defaults -and $controls.ClaudeResources.Parent -eq $tables.Defaults -and $controls.ResourcePlacement.Parent -eq $tables.Defaults) 'Hardware controls should all live on General.'
            $controls.ResourcePlacement.SelectedItem='Bottom bar'
            & $applySettings
            Assert-Resource (-not $script:ResourceOptions.Local -and $script:ResourceOptions.Claude -and $script:ResourcePlacement -eq 'Bottom bar') 'Apply should commit independent resource switches and placements.'
            $controls.LocalResources.Checked=$true; $controls.ClaudeResources.Checked=$false
            $controls.ResourcePlacement.SelectedItem='Side column'
            $cancel.PerformClick()
            Assert-Resource (-not $script:ResourceOptions.Local -and $script:ResourceOptions.Claude -and $script:ResourcePlacement -eq 'Bottom bar') 'Cancel should discard uncommitted switches and placement.'
        } finally { $dialog.Close() }
'@)
Invoke-Expression $settings
Show-WidgetSettings
Close-TestWidget
Write-Output 'PASS: local process grouping, resource formatting, compact rows, alignment and persistence.'

# Exercise the real resource controls with synthetic processes and counters only.
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
function Assert-Resource($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
Assert-Resource ((Format-ResourceMemory 1000000000) -eq '1000 MB') 'Threshold should stay in MB.'
Assert-Resource ((Format-ResourceMemory 1280000000) -eq '1.28 GB') 'RAM should switch to decimal GB.'
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
Assert-Resource ($row.Items[0].Text -eq 'CPU 3%' -and $row.Host.Visibility -eq 'Visible') 'Labeled resources should be visible.'
[void](Update-ResourceRow $row Local 30 50 -HideLabels)
Assert-Resource ($row.Items[0].Text -eq '3%' -and $row.Items[1].Text -eq '1.28GB' -and $row.Items[2].Text -eq '1%' -and $row.Host.Visibility -eq 'Visible') 'Mini resources must retain all three values without labels.'
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
        Update-Display; $window.UpdateLayout()
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
            Assert-Resource (($card.Resources.Items[0].Text -match 'CPU') -eq $quotaLabels) 'Resource names must follow the actual 5-hour label visibility.'
            Assert-Resource ($card.Resources.Host.ActualWidth -le $card.Container.ColumnDefinitions[1].Width.Value+0.1 -and $card.Resources.Host.ActualHeight -gt 0) 'Resource group should stay inside its column with actual drawing height.'
            foreach ($item in $card.Resources.Items) { Assert-Resource ($item.IsVisible -and $item.ActualWidth -gt 0 -and $item.ActualHeight -gt 0) 'Every hardware value must have visible text bounds.' }
            # Compare actual drawn centers after WPF transforms, including narrow RAM scaling.
            if ($card.Resources.Aligned.Visibility -eq 'Visible') {
                $targets=if ($bindings.ultraCompactPanel.Visibility -eq 'Visible') { @($bindings.compactPrimaryPercent,$bindings.compactSecondaryPercent,$bindings.compactCreditsText) } else { @($bindings.primaryPercent,$bindings.secondaryPercent,$bindings.creditsText) }
                for ($index=0;$index -lt 3;$index++) {
                    $item=$card.Resources.Items[$index]
                    $actual=$item.TranslatePoint([Windows.Point]::new(0,$item.ActualHeight/2),$card.Container).Y
                    if ($index -eq 2 -and $bindings.creditsArea.Visibility -ne 'Visible' -and $bindings.ultraCompactPanel.Visibility -ne 'Visible') {
                        $grid=$bindings.outerBorder.Child
                        Assert-Resource ($grid.RowDefinitions[3].ActualHeight -ge 27) 'GPU needs a reserved credit track when no balance exists.'
                        $top=0; for ($track=0;$track -lt 3;$track++) { $top+=$grid.RowDefinitions[$track].ActualHeight }
                        $expected=$grid.TranslatePoint([Windows.Point]::new(0,$top+13.5),$card.Container).Y
                    } else { $expected=$targets[$index].TranslatePoint([Windows.Point]::new(0,$targets[$index].ActualHeight/2),$card.Container).Y }
                    Assert-Resource ([Math]::Abs($actual-$expected) -lt 1) ('Hardware reading is not aligned to its quota row: '+$index+' in '+$layout+' at '+($size -join 'x'))
                }
            }

        }
        if ($layout -ne 'Account picker') { Assert-Resource ($cards[0].Container.ColumnDefinitions[1].Width.Value -eq $cards[1].Container.ColumnDefinitions[1].Width.Value) 'Connected resource columns must stay aligned.' }
    }
}
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
    $actual=$item.TranslatePoint([Windows.Point]::new(0,$item.ActualHeight/2),$detached.Container).Y
    $expected=$value.TranslatePoint([Windows.Point]::new(0,$value.ActualHeight/2),$detached.Container).Y
    Assert-Resource ([Math]::Abs($actual-$expected) -lt 1) 'Detached hardware readings must follow their compact quota rows.'
}

$script:ClaudeOptions.Placement='Follow layout'
# A lone local account also keeps resources in its smallest supported window.
$script:ClaudeOptions.Enabled=$false; $script:SharedEnabled=$false; $script:AccountLayout='Stacked'
$window.Width=72; $window.Height=72; Wait-TestDispatcher 50; Update-Display
Assert-Resource ($script:AccountCards.Local.Resources.Host.Visibility -eq 'Visible' -and $script:AccountCards.Local.Resources.Panel.Orientation -eq 'Vertical') 'Single-account mini view must retain hardware values in three rows.'
Save-WidgetState
$saved=Get-Content -LiteralPath (Join-Path $script:TestState 'widget-state.json') -Raw | ConvertFrom-Json
Assert-Resource ($saved.resourceOptions.Local -eq $true) 'Resource switches should persist locally.'
# Check migration and real settings Apply/Cancel without contacting either account service.
$script:ResourceOptions.Local=$false
Restore-ClaudeSettings $saved
Assert-Resource $script:ResourceOptions.Local 'Restart should restore the local resource switch.'
$settings=[IO.File]::ReadAllText((Join-Path $script:TestProject 'WidgetSettings.ps1'))
$settings=$settings.Replace('$dialog.Show()',@'
        $dialog.Show()
        try {
            $controls.LocalResources.Checked=$false; $controls.ClaudeResources.Checked=$true
            & $applySettings
            Assert-Resource (-not $script:ResourceOptions.Local -and $script:ResourceOptions.Claude) 'Apply should commit independent resource switches.'
            $controls.LocalResources.Checked=$true; $controls.ClaudeResources.Checked=$false
            $cancel.PerformClick()
            Assert-Resource (-not $script:ResourceOptions.Local -and $script:ResourceOptions.Claude) 'Cancel should discard uncommitted resource switches.'
        } finally { $dialog.Close() }
'@)
Invoke-Expression $settings
Show-WidgetSettings
Close-TestWidget
Write-Output 'PASS: local process grouping, resource formatting, compact rows, alignment and persistence.'

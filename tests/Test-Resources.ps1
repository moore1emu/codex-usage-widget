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
# Use long values to check label removal, retained GPU, and disappearance before small quota views.
$script:ResourceOptions.Local=$true
$script:ResourceReadings.Local=@{Available=$true;Cpu=3;Memory=1280000000;Gpu=1;Count=3;SampledAt=[DateTimeOffset]::Now}
$row=New-ResourceRow
[void](Update-ResourceRow $row Local 280 300)
Assert-Resource ($row.Items[0].Text -match 'CPU' -and $row.Panel.Visibility -eq 'Visible') 'Wide row should show labels.'
[void](Update-ResourceRow $row Local 145 300)
Assert-Resource ($row.Items[0].Text -notmatch 'CPU' -and $row.Items[2].Text -match '1%' -and $row.Panel.Visibility -eq 'Visible') ('Compact row should retain all three values without labels: '+($row.Items.Text -join ',')+'; '+$row.Panel.Visibility+'; width='+$row.Panel.DesiredSize.Width)
[void](Update-ResourceRow $row Local 145 150)
Assert-Resource ($row.Panel.Visibility -eq 'Collapsed') 'Short quota views should hide resources first.'
# Long values must never overflow when even the smallest complete row does not fit.
$script:ResourceReadings.Local.Memory=999999999999999999
[void](Update-ResourceRow $row Local 105 300)
Assert-Resource ($row.Panel.Visibility -eq 'Collapsed') 'A row that cannot fit all three values must collapse.'
$script:ResourceReadings.Local.Memory=1280000000
# Render connected panels with one enabled resource row and ensure equal reserved heights.
$script:ClaudeOptions.Enabled=$true; $script:AccountLayout='Stacked'
$script:ClaudeUsage=$script:Usage
$window.Width=600; $window.Height=840; $window.Show(); Wait-TestDispatcher 100
Update-Display
Assert-Resource ($script:AccountCards.Local.Container.RowDefinitions[3].Height.Value -eq 20) 'Local card should reserve its resource row.'
Assert-Resource ($script:AccountCards.Claude.Container.RowDefinitions[3].Height.Value -eq 20) 'Connected account rows should remain aligned.'
# Side-by-side resources use width instead of height and survive a short horizontal view.
$script:AccountLayout='Side by side'; $window.Width=600; $window.Height=150
Wait-TestDispatcher 100; Update-Display
$localCard=$script:AccountCards.Local; $claudeCard=$script:AccountCards.Claude
Assert-Resource ($localCard.Resources.Panel.Orientation -eq 'Vertical' -and $localCard.Resources.Panel.Visibility -eq 'Visible') 'Short side-by-side view must retain all three resources vertically.'
Assert-Resource ($localCard.Resources.Items[2].Text -match '1%') 'GPU must remain in the column.'
Assert-Resource ($localCard.Container.ColumnDefinitions[1].Width.Value -eq $claudeCard.Container.ColumnDefinitions[1].Width.Value) 'Connected quota widths must reserve equal resource columns.'
Assert-Resource ($localCard.Container.RowDefinitions[3].Height.Value -eq 0) 'Vertical resources must not consume quota height.'
# Switching back to stacked cards restores the footer, without leaving an empty side column.
$script:AccountLayout='Stacked'; $window.Width=600; $window.Height=840
Wait-TestDispatcher 100; Update-Display
Assert-Resource ($localCard.Resources.Panel.Orientation -eq 'Horizontal' -and $localCard.Container.ColumnDefinitions[1].Width.Value -eq 0) 'Stacked view should restore the horizontal footer.'
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

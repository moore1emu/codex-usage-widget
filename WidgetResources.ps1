# Keep resource preferences and readings local; quota exports deliberately omit them.
$script:ResourceOptions = @{ Local=$false; Claude=$false }
$script:ResourceReadings = @{}
$script:ResourceNextSample = [DateTimeOffset]::MinValue

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
    param([double]$Bytes)
    # Use the requested decimal threshold: above 1,000 MB becomes GB with two decimals.
    $mb=$Bytes/1000000
    if ($mb -gt 1000) { return ('{0:0.00} GB' -f ($mb/1000)) }
    return ('{0:0} MB' -f $mb)
}

function New-ResourceRow {
    # Build independent text controls so labels can shrink without losing the colored values.
    $panel=[Windows.Controls.StackPanel]::new(); $panel.Orientation='Horizontal'
    $panel.HorizontalAlignment='Center'; $panel.Margin=[Windows.Thickness]::new(3,2,3,2); $panel.Visibility='Collapsed'
    $items=@()
    foreach ($metric in @('CPU','RAM','GPU')) {
        $text=[Windows.Controls.TextBlock]::new(); $text.Foreground='#DDE3EF'; $text.FontSize=11
        $text.Margin=[Windows.Thickness]::new(0,0,7,0); [void]$panel.Children.Add($text); $items+=$text
    }
    $items[2].Margin=[Windows.Thickness]::new(0)
    # Scale the complete resource group at tiny sizes instead of hiding individual values.
    $resourceHost=[Windows.Controls.Viewbox]::new(); $resourceHost.Child=$panel; $resourceHost.Stretch='Uniform'; $resourceHost.StretchDirection='DownOnly'
    $resourceHost.VerticalAlignment='Center'; $resourceHost.Visibility='Collapsed'
    return @{Panel=$panel;Host=$resourceHost;Items=$items}
}

function Update-ResourceRow {
    param($Row,[string]$Key,[double]$Width,[double]$Height,[switch]$HideLabels,[double]$FontSize=11,[switch]$SingleLine,[string[]]$Colors)
    # Enabled hardware values persist through every layout; unavailable readings retain their placeholders.
    $Row.Panel.Visibility='Collapsed'; $Row.Host.Visibility='Collapsed'
    if (-not $script:ResourceOptions[$Key]) { return 0 }
    $reading=$script:ResourceReadings[$Key]
    $available=$reading.Available -and ([DateTimeOffset]::Now-$reading.SampledAt).TotalSeconds -lt 15
    $values=if ($available) { @('{0:0}%' -f $reading.Cpu; Format-ResourceMemory $reading.Memory; $(if ($null -ne $reading.Gpu) {'{0:0}%' -f $reading.Gpu} else {'—'})) } else {@('—','—','—')}
    $labels=@('CPU','RAM','GPU')
    # Follow the quota label stage, preserving units while compacting unnecessary spaces and dots.
    for ($index=0;$index -lt 3;$index++) {
        $item=$Row.Items[$index]; $item.FontSize=$FontSize
        # Follow this account's quota palette: CPU uses 5-hour, RAM weekly, and GPU credits.
        if ($Colors.Count -eq 3) { $item.Foreground=$Colors[$index] }
        $item.FontWeight=if ($HideLabels) {'SemiBold'} else {'Normal'}
        $item.Text=if ($HideLabels) {$values[$index] -replace ' ',''} else {'● '+$labels[$index]+' '+$values[$index]}
        $item.ToolTip=$labels[$index]+': '+$values[$index]+$(if ($available) {"`nLocal desktop app and child processes: $($reading.Count)`nSampled $($reading.SampledAt.ToLocalTime().ToString('h:mm:ss tt'))"} else {"`nNo recent desktop resource reading"})
        $item.Margin=[Windows.Thickness]::new(0,0,0,$(if ($index -eq 2) {0} else {1}))
    }
    # A one-line widget keeps the three readings in one line too; taller cards stack them vertically.
    $Row.Panel.Orientation=if ($SingleLine) {'Horizontal'} else {'Vertical'}
    if ($Row.Panel.Orientation -eq 'Horizontal') {
        for ($index=0;$index -lt 3;$index++) { $Row.Items[$index].Margin=[Windows.Thickness]::new(0,0,$(if ($index -eq 2) {0} else {3}),0) }
    }
    # Bound the whole group to its allocated column; uniform scaling keeps every number inside it.
    $Row.Host.Width=[Math]::Max(1,$Width); $Row.Host.MaxHeight=[Math]::Max(1,$Height)
    $Row.Panel.Visibility='Visible'; $Row.Host.Visibility='Visible'
    return [Math]::Max(1,$Width)
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

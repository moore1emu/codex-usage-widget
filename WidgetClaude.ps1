# Leave existing Codex installations unchanged until Claude is explicitly enabled.
$script:LocalEnabled = $true
$script:ClaudeOptions = @{
    Enabled=$false
    Name='Claude'
    Scheme='Rose / periwinkle / seafoam'
    Placement='Follow layout'
    Interval=5
    ResetHours=25
    WeeklyDate=$true
    PrimaryAlert=0
    SecondaryAlert=0
    ResetAlert=$false
    Bounds=$null
}
$script:ClaudeUsage = $null
$script:ClaudeStatus = 'Not connected - use Connect in Settings'
$script:ClaudeAlertStates = @{}
$script:ClaudeNextRefresh = [DateTimeOffset]::MinValue

function ConvertTo-ClaudeUsage {
    param($Payload)
    # Convert only subscription quotas; extra-usage spending is not a Codex credit balance.
    $snapshot = @{ fetchedAt=[DateTimeOffset]::Now.ToUnixTimeSeconds(); planType=''; ordinaryUsageAllowed=$false; credits=$null }
    foreach ($entry in @(@{Key='primary';Source='five_hour';Minutes=300},@{Key='secondary';Source='seven_day';Minutes=10080})) {
        $quota = $Payload.($entry.Source)
        if (-not $quota -or $null -eq $quota.utilization) { $snapshot[$entry.Key]=$null; continue }
        # Validate both percentages and dates before a reading can update the display or alerts.
        $used = [double]0
        if (-not [double]::TryParse([string]$quota.utilization,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$used) -or [double]::IsNaN($used) -or [double]::IsInfinity($used) -or $used -lt 0 -or $used -gt 100) { throw 'Claude returned an invalid usage percentage.' }
        $reset = $null
        if ($quota.resets_at) {
            $date = [DateTimeOffset]::MinValue
            # Preserve typed JSON dates instead of reinterpreting their local clock time as UTC.
            if ($quota.resets_at -is [DateTimeOffset]) {
                $date = $quota.resets_at
            } elseif ($quota.resets_at -is [DateTime]) {
                $instant = $quota.resets_at
                # Offset-free API dates represent UTC; local and UTC dates retain their existing kind.
                if ($instant.Kind -eq [DateTimeKind]::Unspecified) { $instant = [DateTime]::SpecifyKind($instant,[DateTimeKind]::Utc) }
                $date = [DateTimeOffset]::new($instant)
            } elseif (-not [DateTimeOffset]::TryParse([string]$quota.resets_at,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::AssumeUniversal,[ref]$date)) {
                throw 'Claude returned an invalid reset date.'
            }
            $reset = $date.ToUnixTimeSeconds()
        }
        $snapshot[$entry.Key] = @{usedPercent=$used;resetsAt=$reset;windowDurationMins=$entry.Minutes}
    }
    # Unknown quotas stay unknown, including plans which do not provide these meters.
    $snapshot.ordinaryUsageAllowed = $snapshot.primary -and $snapshot.primary.usedPercent -lt 100
    return [pscustomobject]$snapshot
}

function Get-EnabledAccounts {
    # Use stable source keys rather than display names, which may be identical.
    if ($script:LocalEnabled) { 'Local' }
    if ($script:SharedEnabled -and $script:ReadUsageEnabled) { 'Remote' }
    if ($script:ClaudeOptions.Enabled) { 'Claude' }
    if ($script:SharedClaudeOptions.Enabled -and $script:SharedClaudeOptions.ReadEnabled) { 'SharedClaude' }
}

function Get-AccountName {
    param([string]$Key)
    switch ($Key) { Local { $script:LocalDisplayName }; Remote { $script:RemoteDisplayName }; Claude { $script:ClaudeOptions.Name }; SharedClaude {$script:SharedClaudeOptions.Name} }
}

function Save-ClaudeWarnings {
    # Persist sent flags separately and only when changed, so restarts cannot repeat warnings.
    if (-not $script:StateDirectory) { return }
    $json = @{source=$script:ClaudeWarningSource;states=$script:ClaudeAlertStates} | ConvertTo-Json -Compress -Depth 5
    if ($json -ne $script:LastClaudeWarningState) {
        $json | Set-Content -LiteralPath (Join-Path $script:StateDirectory 'claude-warning-state.json') -Encoding utf8
        $script:LastClaudeWarningState = $json
    }
}

function Show-ClaudeUsageWarnings {
    # Reuse the tested quota rules only for successful, fresh Claude readings.
    if (-not $script:ClaudeOptions.Enabled -or -not $script:ClaudeUsage) { return }
    $original = @{Usage=$script:Usage;PrimaryAlertThreshold=$script:PrimaryAlertThreshold;SecondaryAlertThreshold=$script:SecondaryAlertThreshold;NotifyPrimaryReset=$script:NotifyPrimaryReset;AlertStates=$script:AlertStates;ProcessingClaudeWarnings=$script:ProcessingClaudeWarnings}
    try {
        $script:Usage=$script:ClaudeUsage
        $script:PrimaryAlertThreshold=$script:ClaudeOptions.PrimaryAlert
        $script:SecondaryAlertThreshold=$script:ClaudeOptions.SecondaryAlert
        $script:NotifyPrimaryReset=$script:ClaudeOptions.ResetAlert
        $script:AlertStates=$script:ClaudeAlertStates
        $script:ProcessingClaudeWarnings=$true
        Show-UsageWarnings -AccountName $script:ClaudeOptions.Name
    } finally {
        # Restore Codex state even if Windows refuses a balloon notification.
        foreach ($key in $original.Keys) { Set-Variable -Scope Script -Name $key -Value $original[$key] }
    }
}

function Restore-ClaudeSettings {
    param($State)
    # Migrate old preferences without enabling new connections or disabling local Codex.
    if ($State.localEnabled -is [bool]) { $script:LocalEnabled=$State.localEnabled }
    $saved = $State.claude
    if (-not $saved) { return }
    foreach ($key in @('Enabled','WeeklyDate','ResetAlert')) { if ($saved.$key -is [bool]) { $script:ClaudeOptions[$key]=$saved.$key } }
    foreach ($key in @('ResetHours','PrimaryAlert','SecondaryAlert')) {
        $max = if ($key -eq 'ResetHours') {168} else {100}
        if (($saved.$key -is [int] -or $saved.$key -is [long]) -and $saved.$key -ge 0 -and $saved.$key -le $max) { $script:ClaudeOptions[$key]=[int]$saved.$key }
    }
    if ($saved.Interval -in @(0,1,5,15,30)) { $script:ClaudeOptions.Interval=[int]$saved.Interval }
    if ($saved.Placement -in @('Follow layout','Attached','Separate window')) { $script:ClaudeOptions.Placement=$saved.Placement }
    if ($script:ColorSchemes.Contains([string]$saved.Scheme)) { $script:ClaudeOptions.Scheme=$saved.Scheme }
    if ($saved.Name -is [string] -and $saved.Name.Trim()) { $script:ClaudeOptions.Name=($saved.Name -replace '[\p{C}]','').Trim().Substring(0,[Math]::Min(40,($saved.Name -replace '[\p{C}]','').Trim().Length)) }
    $script:ClaudeOptions.Bounds=$saved.Bounds
    # Restore only well-formed alert flags; a changed organization starts a new notification history.
    $path = Join-Path $script:StateDirectory 'claude-warning-state.json'
    if (Test-Path -LiteralPath $path) {
        try {
            $history = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
            if ($history.source -is [string] -and $history.states -is [Collections.IDictionary]) {
                $script:ClaudeWarningSource=$history.source
                foreach ($key in @('primary','secondary','primaryReset')) {
                    $item=$history.states[$key]
                    if ($item -is [Collections.IDictionary] -and $item.Notified -is [bool] -and ($key -ne 'primaryReset' -or ($item.ResetsAt -gt 0 -and $null -ne $item.UsedPercent -and $item.UsedPercent -ge 0 -and $item.UsedPercent -le 100))) { $script:ClaudeAlertStates[$key]=$item }
                }
            }
        } catch { $script:ClaudeAlertStates=@{} }
    }
}

function Start-ClaudeConnection {
    param([switch]$Show)
    # Keep sign-in on Claude's own website; never inspect cookies, passwords, or desktop credentials.
    if (-not $script:ClaudeOptions.Enabled) { return }
    if ($Show) { $script:ClaudeShowConnection=$true }
    if ($script:ClaudeBrowserWindow) {
        if ($Show) { $script:ClaudeBrowserWindow.Show(); [void]$script:ClaudeBrowserWindow.Activate() }
        Start-ClaudeRefresh -Force
        return
    }
    if ($script:ClaudeSetupProcess -or $script:ClaudeEnvironmentTask) { return }
    # Install optional SDK files asynchronously, outside both the checkout and synced folders.
    $sdkRoot=Join-Path $script:StateDirectory 'WebView2SDK'
    $sdk=Join-Path $sdkRoot '1.0.3800.47'
    if (-not (Test-Path -LiteralPath (Join-Path $sdk 'lib/net462/Microsoft.Web.WebView2.Wpf.dll'))) {
        $info=[Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
        foreach ($argument in @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $script:WidgetDirectory 'Setup-ClaudeWebView.ps1'),'-Destination',$sdkRoot)) { $info.ArgumentList.Add($argument) }
        $info.UseShellExecute=$false; $info.CreateNoWindow=$true
        $script:ClaudeSetupProcess=[Diagnostics.Process]::Start($info)
        $script:ClaudeSetupStarted=[DateTimeOffset]::Now
        $script:ClaudeStatus='Installing optional Microsoft WebView2 support…'
        return
    }
    try {
        # Resolve the native loader for the current PowerShell architecture without changing PATH.
        Add-Type -Path (Join-Path $sdk 'lib/net462/Microsoft.Web.WebView2.Core.dll')
        Add-Type -Path (Join-Path $sdk 'lib/net462/Microsoft.Web.WebView2.Wpf.dll')
        $arch=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant()
        if (-not $script:ClaudeSdkLoaded) {
            [Microsoft.Web.WebView2.Core.CoreWebView2Environment]::SetLoaderDllFolderPath((Join-Path $sdk "runtimes/win-$arch/native"))
            $script:ClaudeSdkLoaded=$true
        }
        $profile=Join-Path $script:StateDirectory 'ClaudeBrowserProfile'
        $script:ClaudeEnvironmentTask=[Microsoft.Web.WebView2.Core.CoreWebView2Environment]::CreateAsync($null,$profile,$null)
        $script:ClaudeStatus='Connecting to Claude…'
    } catch { $script:ClaudeStatus='WebView2 unavailable. Install the Microsoft Edge WebView2 Runtime and reconnect.' }
}

function Initialize-ClaudeBrowser {
    param($Environment)
    # Keep the dedicated Usage window separate from account display windows.
    $script:ClaudeBrowserWindow=[Windows.Window]::new()
    $script:ClaudeBrowserWindow.Title='Claude Usage - sign in on claude.ai'
    $script:ClaudeBrowserWindow.Width=850; $script:ClaudeBrowserWindow.Height=700
    $script:ClaudeBrowserWindow.ShowActivated=[bool]$script:ClaudeShowConnection
    $script:ClaudeBrowser=[Microsoft.Web.WebView2.Wpf.WebView2]::new()
    $script:ClaudeBrowserWindow.Content=$script:ClaudeBrowser
    # Initializing an invisible window avoids stealing focus during an automatic reconnect.
    if (-not $script:ClaudeShowConnection) { $script:ClaudeBrowserWindow.Opacity=0 }
    $script:ClaudeBrowserWindow.Show()
    $script:ClaudeBrowserTask=$script:ClaudeBrowser.EnsureCoreWebView2Async($Environment)
    $script:ClaudeBrowserWindow.Add_Closing({ if (-not $script:ExitRequested -and -not $script:ClosingClaudeConnection) { $_.Cancel=$true; $script:ClaudeBrowserWindow.Hide() } })
}

function Start-ClaudeRefresh {
    param([switch]$Force)
    # A disabled account or in-flight request cannot produce network work or duplicate alerts.
    if (-not $script:ClaudeOptions.Enabled -or -not $script:ClaudeBrowserReady -or $script:ClaudeRequestId) { return }
    if (-not $Force -and ($script:ClaudeOptions.Interval -eq 0 -or [DateTimeOffset]::Now -lt $script:ClaudeNextRefresh)) { return }
    if ([DateTimeOffset]::Now -lt $script:ClaudeBackoffUntil) { return }
    if ($script:ClaudeBrowser.CoreWebView2.Source -notmatch '^https://claude\.ai/') { $script:ClaudeStatus='Sign in using Connect in Settings'; return }
    # Execute same-origin requests within the signed-in browser; export only whitelisted quota fields.
    $script:ClaudeRequestId=[guid]::NewGuid().ToString('N')
    $script:ClaudeRequestStarted=[DateTimeOffset]::Now
    $request=$script:ClaudeRequestId | ConvertTo-Json -Compress
    $javascript=@'
(async () => {
  const request = REQUEST_ID;
  const controller = new AbortController();
  // Bound all network work so offline connections cannot leave refresh stuck.
  const timeout = setTimeout(() => controller.abort(), 15000);
  const read = async path => {
    const response = await fetch(path, {credentials:'same-origin', cache:'no-store', signal:controller.signal});
    if (!response.ok) throw {status:response.status, retry:Number(response.headers.get('Retry-After')) || 0};
    return response.json();
  };
  try {
    const orgs = await read('/api/organizations');
    let active = null;
    try { active = (await read('/api/bootstrap')).account?.lastActiveOrgId; } catch (error) { if (error.status === 429) throw error; }
    // Follow Claude's active subscription; do not guess between multiple organizations.
    const chat = orgs.filter(org => (org.capabilities || []).includes('chat'));
    const candidates = chat.length ? chat : orgs;
    const org = orgs.find(org => (org.uuid || org.id) === active) || (candidates.length === 1 ? candidates[0] : null);
    if (!org) throw {status:409};
    const id = org.uuid || org.id;
    const usage = await read('/api/organizations/' + encodeURIComponent(id) + '/usage');
    const quota = value => value ? {utilization:value.utilization ?? null, resets_at:value.resets_at ?? null} : null;
    chrome.webview.postMessage({type:'widget-usage',request,source:id,usage:{five_hour:quota(usage.five_hour),seven_day:quota(usage.seven_day)}});
  } catch (error) {
    // Never send response bodies or authentication information into widget logs.
    chrome.webview.postMessage({type:'widget-usage',request,status:error.status || 0,retry:error.retry || 0});
  } finally { clearTimeout(timeout); }
})();
'@
    $script:ClaudeScriptTask=$script:ClaudeBrowser.ExecuteScriptAsync($javascript.Replace('REQUEST_ID',$request))
}

function Receive-ClaudeUsage {
    param($Event)
    # Ignore messages from sign-in redirects, unrelated pages, or superseded requests.
    if ($Event.Source -notmatch '^https://claude\.ai/' -or -not $script:ClaudeOptions.Enabled) { return }
    try {
        $message=$Event.WebMessageAsJson | ConvertFrom-Json
        if ($message.type -ne 'widget-usage' -or -not $script:ClaudeRequestId -or $message.request -ne $script:ClaudeRequestId) { return }
        $script:ClaudeRequestId=$null
        $script:ClaudeNextRefresh=[DateTimeOffset]::Now.AddMinutes([Math]::Max(1,$script:ClaudeOptions.Interval))
        if ($message.status) {
            if ($message.status -eq 429) {
                $script:ClaudeBackoffUntil=[DateTimeOffset]::Now.AddSeconds([Math]::Min(3600,[Math]::Max(900,[double]$message.retry)))
                $script:ClaudeStatus='Rate limited - refresh paused temporarily; last reading retained'
            } elseif ($message.status -in @(401,403)) { $script:ClaudeStatus='Sign in using Connect in Settings - last reading retained'; $script:ClaudeNextRefresh=[DateTimeOffset]::Now.AddMinutes(30) }
            elseif ($message.status -eq 409) { $script:ClaudeStatus='Choose your subscription in the Claude Usage window, then Refresh' }
            else { $script:ClaudeStatus='Unable to refresh - last reading retained' }
        } elseif ($message.usage) {
            $snapshot=ConvertTo-ClaudeUsage $message.usage
            # Reset notification history when the signed-in subscription changes.
            if ($message.source -ne $script:ClaudeWarningSource) { $script:ClaudeWarningSource=[string]$message.source; $script:ClaudeAlertStates=@{} }
            $script:ClaudeUsage=$snapshot
            $script:ClaudeStatus='Subscription · updated ' + [DateTime]::Now.ToString('h:mm tt')
            Show-ClaudeUsageWarnings
            # Publish only quota changes; matched sharing also reads the other Claude computer.
            Invoke-ClaudeSharing -Fresh
        }
    } catch { $script:ClaudeRequestId=$null; $script:ClaudeStatus='Unrecognized Claude response - last reading retained' }
    Update-Display
    Update-TrayIcon
}

function Invoke-ClaudeTick {
    # Poll completed tasks on the UI thread rather than blocking PowerShell's message loop.
    try {
        if ($script:ClaudeSetupProcess) {
            if (([DateTimeOffset]::Now-$script:ClaudeSetupStarted).TotalSeconds -gt 65 -and -not $script:ClaudeSetupProcess.HasExited) { $script:ClaudeSetupProcess.Kill($true) }
            if (-not $script:ClaudeSetupProcess.HasExited) { return }
            $ok=$script:ClaudeSetupProcess.ExitCode -eq 0
            $script:ClaudeSetupProcess.Dispose(); $script:ClaudeSetupProcess=$null
            if ($ok) { Start-ClaudeConnection } else { $script:ClaudeStatus='WebView2 setup failed - use Connect to retry' }
        }
        if ($script:ClaudeEnvironmentTask -and $script:ClaudeEnvironmentTask.IsCompleted) {
            $task=$script:ClaudeEnvironmentTask; $script:ClaudeEnvironmentTask=$null
            Initialize-ClaudeBrowser ($task.GetAwaiter().GetResult())
        }
        if ($script:ClaudeBrowserTask -and $script:ClaudeBrowserTask.IsCompleted) {
            $task=$script:ClaudeBrowserTask; $script:ClaudeBrowserTask=$null
            [void]$task.GetAwaiter().GetResult()
            $core=$script:ClaudeBrowser.CoreWebView2
            $core.Add_WebMessageReceived({ param($sender,$eventArgs) Receive-ClaudeUsage $eventArgs })
            $core.Add_NavigationCompleted({ if ($script:ClaudeOptions.Enabled) { Start-ClaudeRefresh -Force } })
            $script:ClaudeBrowserReady=$true
            $core.Navigate('https://claude.ai/settings/usage')
            if (-not $script:ClaudeShowConnection) { $script:ClaudeBrowserWindow.Hide() }
            $script:ClaudeBrowserWindow.Opacity=1
        }
        # Expire a request if navigation or a changed site prevented its completion message.
        if ($script:ClaudeRequestId -and (([DateTimeOffset]::Now-$script:ClaudeRequestStarted).TotalSeconds -gt 25 -or ($script:ClaudeScriptTask -and $script:ClaudeScriptTask.IsFaulted))) {
            $script:ClaudeRequestId=$null; $script:ClaudeStatus='Refresh timed out - last reading retained'; $script:ClaudeNextRefresh=[DateTimeOffset]::Now.AddMinutes([Math]::Max(1,$script:ClaudeOptions.Interval))
        }
        Start-ClaudeRefresh
    } catch {
        # Discard a failed browser initialization so Connect can make a clean retry.
        $script:ClaudeStatus='Claude connection failed - use Connect in Settings'; $script:ClaudeBrowserReady=$false
        if ($script:ClaudeBrowserWindow) {$script:ClaudeBrowserWindow.Hide();$script:ClaudeBrowserWindow.Content=$null;$script:ClaudeBrowser.Dispose();$script:ClaudeBrowserWindow=$null}
        $script:ClaudeEnvironmentTask=$null;$script:ClaudeBrowserTask=$null
    }
}

function Update-ClaudeConnection {
    # Disabled accounts stop their service timer and reject any already-running response.
    if (-not $script:ClaudeTimer) {
        $script:ClaudeTimer=[Windows.Threading.DispatcherTimer]::new()
        $script:ClaudeTimer.Interval=[TimeSpan]::FromSeconds(1)
        $script:ClaudeTimer.Add_Tick({ Invoke-ClaudeTick })
    }
    if ($script:ClaudeOptions.Enabled) { $script:ClaudeTimer.Start(); Start-ClaudeConnection }
    else {
        $script:ClaudeTimer.Stop(); $script:ClaudeRequestId=$null
        # Release the browser too, so its website cannot keep polling after Claude is disabled.
        $script:ClosingClaudeConnection=$true
        try {
            if ($script:ClaudeBrowserWindow) {$script:ClaudeBrowserWindow.Close();$script:ClaudeBrowser.Dispose()}
        } finally {
            # Keep the private sign-in profile on disk for the next enable, but release live resources.
            $script:ClosingClaudeConnection=$false;$script:ClaudeBrowserWindow=$null;$script:ClaudeBrowser=$null
            $script:ClaudeBrowserReady=$false;$script:ClaudeEnvironmentTask=$null;$script:ClaudeBrowserTask=$null;$script:ClaudeShowConnection=$false
        }
        if ($script:ClaudeSetupProcess) {
            if (-not $script:ClaudeSetupProcess.HasExited) {$script:ClaudeSetupProcess.Kill($true)}
            $script:ClaudeSetupProcess.Dispose();$script:ClaudeSetupProcess=$null
        }
    }
}

function Invoke-ClaudeWindowAction {
    param([scriptblock]$Action)
    # Reuse existing shell actions with this window's controls in a local invocation scope.
    $window=$script:ClaudeView.Window
    foreach ($key in $script:ClaudeView.Bindings.Keys) { Set-Variable -Name $key -Value $script:ClaudeView.Bindings[$key] }
    & $Action
}

function Save-ClaudeWindowBounds {
    # Save final geometry only; debounce native resize and position events separately.
    if ($script:ClaudeBoundsTimer) { $script:ClaudeBoundsTimer.Stop() }
    if (-not $script:ClaudeView -or -not $script:ClaudeView.Window.IsLoaded) { return }
    $peer=$script:ClaudeView.Window
    $script:ClaudeOptions.Bounds=@{left=$peer.Left;top=$peer.Top;width=$peer.Width;height=$peer.Height;topmost=$peer.Topmost}
    Save-WidgetState
}

function Set-ClaudeWindowPreset {
    param([string]$Name)
    # Resize Claude alone without changing any other account's saved dimensions.
    if (-not $script:ClaudeView) { return }
    $index=@('Mini','Small','Medium','Large / Default').IndexOf($Name)
    if ($index -lt 0) { return }
    $sizes=@(@(72,72),@(140,155),@(190,210),@(280,290))
    $script:ClaudeView.Window.Width=$sizes[$index][0]; $script:ClaudeView.Window.Height=$sizes[$index][1]
    Update-ClaudeWindow
    Save-ClaudeWindowBounds
}

function Initialize-ClaudeWindow {
    # Clone the established shell so dragging, hover actions and both resize grips stay consistent.
    if ($script:ClaudeView) { return }
    $peer=[Windows.Markup.XamlReader]::Load([System.Xml.XmlNodeReader]::new($xaml))
    $bindings=@{}
    foreach ($match in [regex]::Matches($script:WidgetSource,'\$(\w+) = \$window\.FindName\(''([^'']+)''\)')) { $bindings[$match.Groups[1].Value]=$peer.FindName($match.Groups[2].Value) }
    $script:ClaudeView=@{Window=$peer;Bindings=$bindings}
    $peer.Icon=$window.Icon
    $peer.WindowStartupLocation='Manual'
    Restore-AccountWindowBounds $peer $(if ($script:ClaudeOptions.Bounds) {$script:ClaudeOptions.Bounds} else {@{left=$window.Left+$window.Width+8;top=$window.Top;width=280;height=290;topmost=$window.Topmost}})
    foreach ($key in @('primaryArea','secondaryArea','creditsArea','ultraCompactPanel','footerArea')) { $bindings[$key].Visibility='Collapsed' }
    # Coalesce size/location events; explicit drag completion and presets save immediately.
    $script:ClaudeBoundsTimer=[Windows.Threading.DispatcherTimer]::new()
    $script:ClaudeBoundsTimer.Interval=[TimeSpan]::FromMilliseconds(300)
    $script:ClaudeBoundsTimer.Add_Tick({ Save-ClaudeWindowBounds })
    foreach ($key in @('leftResizeGrip','rightResizeGrip')) {
        $bindings[$key].Add_DragDelta({param($sender,$eventArgs) Resize-AccountWindow $script:ClaudeView.Window $sender.Tag $eventArgs.HorizontalChange $eventArgs.VerticalChange})
        $bindings[$key].Add_DragCompleted({Save-ClaudeWindowBounds; Invoke-ClaudeWindowAction {Update-HoverControls}})
    }
    foreach ($key in @('refreshButton','compactRefreshButton','hoverRefreshButton')) { $bindings[$key].Add_Click({Start-ClaudeRefresh -Force}) }
    foreach ($key in @('pinButton','hoverPinButton')) { $bindings[$key].Add_Click({Invoke-ClaudeWindowAction {$window.Topmost=-not $window.Topmost; Update-PinDisplay}; Save-ClaudeWindowBounds}) }
    foreach ($key in @('closeButton','hoverCloseButton','minimizeButton','hoverMinimizeButton')) { $bindings[$key].Add_Click({Save-ClaudeWindowBounds; $script:ClaudeView.Window.Hide()}) }
    foreach ($key in @('closeButton','hoverCloseButton')) {$bindings[$key].ToolTip='Hide this account to tray'}
    # Captured-pointer movement avoids Windows Snap just like the existing Codex windows.
    $bindings.outerBorder.Add_MouseLeftButtonDown({if (Test-WidgetDragSource $_.OriginalSource) {if ($_.ClickCount -eq 2) {Set-ClaudeWindowPreset 'Large / Default'} else {Invoke-ClaudeWindowAction {Start-WidgetDrag}}}})
    $bindings.outerBorder.Add_MouseMove({if ([Windows.Input.Mouse]::LeftButton -eq 'Pressed') {Invoke-ClaudeWindowAction {Update-WidgetDrag}}})
    $bindings.outerBorder.Add_MouseLeftButtonUp({Invoke-ClaudeWindowAction {if ($script:DragOrigin) {Update-WidgetDrag; $script:DragOrigin=$null; $outerBorder.ReleaseMouseCapture()}}; Save-ClaudeWindowBounds})
    $bindings.outerBorder.Add_LostMouseCapture({$script:DragOrigin=$null})
    $bindings.outerBorder.Add_MouseEnter({Invoke-ClaudeWindowAction {Update-HoverControls -IsPointerOver $true}})
    $bindings.outerBorder.Add_MouseLeave({Invoke-ClaudeWindowAction {Update-HoverControls -IsPointerOver $false}})
    $peer.Add_SizeChanged({Update-ClaudeWindow; if (-not $script:ChangingClaudeWindow -and -not $script:DragOrigin -and -not $script:ResizingAccountWindow) {$script:ClaudeBoundsTimer.Stop();$script:ClaudeBoundsTimer.Start()}})
    $peer.Add_LocationChanged({if (-not $script:ChangingClaudeWindow -and -not $script:DragOrigin) {$script:ClaudeBoundsTimer.Stop();$script:ClaudeBoundsTimer.Start()}})
    $peer.Add_IsVisibleChanged({Update-WidgetClock})
    $peer.Add_StateChanged({if ($script:ClaudeView.Window.WindowState -eq 'Minimized') {$script:ClaudeView.Window.Hide()}})
    $peer.Add_Closing({if (-not $script:ExitRequested) {$_.Cancel=$true;Save-ClaudeWindowBounds;$script:ClaudeView.Window.Hide()}})
}

function Update-ClaudeWindow {
    # Move the Claude card only on an attachment transition, preserving independent window geometry.
    if ($script:ChangingClaudeWindow -or -not ($window -is [Windows.Window]) -or -not $window.IsLoaded) { return }
    $separate=$script:ClaudeOptions.Enabled -and ($script:ClaudeOptions.Placement -eq 'Separate window' -or ($script:ClaudeOptions.Placement -eq 'Follow layout' -and $script:AccountLayout -eq 'Separate windows'))
    if ($separate -ne [bool]$script:ClaudeWindowActive) {
        $script:ChangingClaudeWindow=$true
        try {
            if ($separate) {
                Initialize-ClaudeWindow
                [void]$script:AccountsHost.Children.Remove($script:AccountCards.Claude.Container)
                [Windows.Controls.Grid]::SetRow($script:AccountCards.Claude.Container,1)
                [Windows.Controls.Grid]::SetRowSpan($script:AccountCards.Claude.Container,3)
                [Windows.Controls.Grid]::SetColumn($script:AccountCards.Claude.Container,0)
                [void]$script:ClaudeView.Bindings.outerBorder.Child.Children.Add($script:AccountCards.Claude.Container)
                $script:ClaudeWindowActive=$true
                $script:ClaudeView.Window.Show()
            } else {
                Save-ClaudeWindowBounds
                $script:ClaudeView.Window.Hide()
                [void]$script:ClaudeView.Bindings.outerBorder.Child.Children.Remove($script:AccountCards.Claude.Container)
                [Windows.Controls.Grid]::SetRowSpan($script:AccountCards.Claude.Container,1)
                [void]$script:AccountsHost.Children.Add($script:AccountCards.Claude.Container)
                $script:ClaudeWindowActive=$false
            }
            $script:LastAccountLayout=$null
        } finally {$script:ChangingClaudeWindow=$false}
    }
    if (-not $script:ClaudeWindowActive -or -not $script:ClaudeView.Window.IsVisible) { return }
    # Render only into the detached shell's own dimensions and display preferences.
    $peer=$script:ClaudeView.Window; $bindings=$script:ClaudeView.Bindings
    $toolbar=$peer.ActualWidth -ge 180 -and $peer.ActualHeight -ge 125
    $bindings.outerBorder.Padding=[Windows.Thickness]::new(6)
    $bindings.dragArea.Visibility=if ($toolbar) {'Visible'} else {'Collapsed'}
    $bindings.planText.Visibility='Collapsed'; $bindings.compactRefreshButton.Visibility='Collapsed'
    $bindings.titleText.Text='CLAUDE'
    # Keep the existing restart launcher's title prefix so it closes every account window.
    $peer.Title='Codex Usage - '+$script:ClaudeOptions.Name
    $width=[Math]::Max(1,$peer.ActualWidth-14); $height=[Math]::Max(1,$peer.ActualHeight-14-$(if ($toolbar) {24} else {0}))
    $card=$script:AccountCards.Claude; $card.Container.Visibility='Visible'
    $heading=Set-AccountHeadingSize $card $width $height
    Render-AccountCard -Claude -Card $card -Snapshot $script:ClaudeUsage -Name $script:ClaudeOptions.Name -Status $script:ClaudeStatus -Scheme $script:ClaudeOptions.Scheme -Width $width -Height ([Math]::Max(1,$height-$heading))
    Invoke-ClaudeWindowAction {Update-PinDisplay;Update-HoverControls}
}

function Show-ClaudeWidget {
    # Restore only Claude when detached; otherwise show its common host.
    if (-not $script:ClaudeWindowActive) {$script:SelectedAccount='Claude';Update-Display;Update-TrayIcon;Show-Widget;return}
    $script:ClaudeView.Window.WindowState='Normal'
    $script:ClaudeView.Window.Show();[void]$script:ClaudeView.Window.Activate()
    Update-ClaudeWindow
}

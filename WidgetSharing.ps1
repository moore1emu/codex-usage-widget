# Keep shared account display and notification preferences independent of the local account.
$script:SharedEnabled = $false
$script:SharedCreditDisplayMode = 'Available'
$script:SharedPrimaryResetHours = 25
$script:SharedShowWeeklyResetDate = $true
$script:SharedPrimaryAlertThreshold = 0
$script:SharedSecondaryAlertThreshold = 0
$script:SharedNotifyPrimaryReset = $false
$script:SharedAlertStates = @{}
$script:SharedWarningSourceId = ''
$script:RemoteSourceId = ''
$script:LastSharedWarningState = $null
# Keep sharing opt-in and preferences local to this Windows user.
$script:WriteUsageEnabled = $false
$script:ReadUsageEnabled = $false
$script:UsageOutputPath = ''
$script:UsageInputPath = ''
$script:LocalDisplayName = 'This computer'
$script:AccountLayout = 'Side by side'
$script:SelectedAccount = 'Local'
$script:LocalScheme = 'Blue / purple / sage'
$script:RemoteScheme = 'Teal / lilac / sand'
# Use -1 for the widget interval, zero for manual, and positive values for minutes.
$script:WriteIntervalMinutes = -1
$script:ReadIntervalMinutes = -1
$script:SharingSourceId = [guid]::NewGuid().ToString('N')
$script:RemoteUsage = $null
$script:RemoteDisplayName = 'Shared computer'
$script:WriteError = $null
$script:ReadError = $null
$script:LastWrittenAt = $null
$script:LastReadAt = $null
$script:LastWrittenFetchedAt = 0
$script:NextWriteAt = [DateTimeOffset]::Now
$script:NextReadAt = [DateTimeOffset]::Now
# Define each approved palette once for both accounts and the settings selectors.
$script:ColorSchemes = [ordered]@{
    'Blue / purple / sage' = @('#669CFF','#A97BFF','#91B8B0')
    'Teal / lilac / sand' = @('#80B7BA','#B49ACB','#BFAE8F')
    'Rose / periwinkle / seafoam' = @('#D49AA8','#9A9CD4','#91B5B5')
    'Slate / peach / olive' = @('#8EA9C6','#C7A08E','#A5B89B')
    'Silver / gray / charcoal' = @('#D0D0D0','#939393','#606060')
    'Fuchsia / mauve / mist' = @('#C98DB8','#AF9CCB','#91AFBD')
}

function Resolve-UsageFilePath {
    param([string] $Path)
    # Expand Windows environment variables while rejecting paths inside this public project.
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if (-not [IO.Path]::IsPathFullyQualified($expanded) -or $expanded -match '%[^%]+%') { throw 'Choose a full file path using Browse.' }
    $full = [IO.Path]::GetFullPath($expanded)
    $project = [IO.Path]::GetFullPath($script:WidgetDirectory).TrimEnd('\') + '\'
    if ($full.StartsWith($project, [StringComparison]::OrdinalIgnoreCase)) { throw 'Choose a private folder outside the widget project.' }
    if ([IO.Path]::GetExtension($full) -ne '.json' -or [IO.Path]::GetFileName($full) -in @('auth.json','credentials.json')) { throw 'Choose a usage JSON file, not a credentials file.' }
    return $full
}

function ConvertTo-SharedUsage {
    param($Usage)
    # Accept only a bounded numeric timestamp and supported snapshot fields.
    $fetched = [long]0
    if (-not [long]::TryParse([string]$Usage.fetchedAt, [ref]$fetched) -or $fetched -le 0) { throw 'The usage update time is missing or invalid.' }
    try { [void][DateTimeOffset]::FromUnixTimeSeconds($fetched) } catch { throw 'The usage update time is invalid.' }
    if ($fetched -gt [DateTimeOffset]::Now.AddMinutes(5).ToUnixTimeSeconds()) { throw 'The usage update time is in the future.' }
    $snapshot = [ordered]@{ fetchedAt=$fetched; planType=([string]$Usage.planType -replace '[\p{C}]','').Substring(0,[Math]::Min(32,([string]$Usage.planType -replace '[\p{C}]','').Length)); ordinaryUsageAllowed=($Usage.ordinaryUsageAllowed -eq $true) }
    foreach ($name in @('primary','secondary')) {
        # Preserve unavailable windows rather than inventing quota or reset dates.
        $quota = $Usage.$name
        if ($null -eq $quota) { $snapshot[$name] = $null; continue }
        $used = $null
        if ($null -ne $quota.usedPercent) {
            $number = [double]0
            if (-not [double]::TryParse([string]$quota.usedPercent, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$number) -or
                [double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -lt 0 -or $number -gt 100) { throw 'A usage percentage is invalid.' }
            $used = $number
        }
        $reset = [long]0
        if ($null -ne $quota.resetsAt) {
            if (-not [long]::TryParse([string]$quota.resetsAt, [ref]$reset) -or $reset -lt 0) { throw 'A reset timestamp is invalid.' }
            try { [void][DateTimeOffset]::FromUnixTimeSeconds($reset) } catch { throw 'A reset timestamp is invalid.' }
        }
        # Duration is used only for projecting later reset times; ignore unsupported values.
        $duration = [double]0
        if (-not [double]::TryParse([string]$quota.windowDurationMins, [ref]$duration) -or $duration -le 0 -or $duration -gt 10080 -or [double]::IsNaN($duration)) { $duration = 0 }
        $snapshot[$name] = @{ usedPercent=$used; resetsAt=$reset; windowDurationMins=$duration }
    }
    # Export credit units only; never copy raw account responses or authentication fields.
    $snapshot.credits = $null
    if ($null -ne $Usage.credits) {
        $balance = [decimal]0
        $balanceText = $null
        if ($null -ne $Usage.credits.balance) {
            if (-not [decimal]::TryParse([string]$Usage.credits.balance, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$balance) -or $balance -lt 0) { throw 'The credit balance is invalid.' }
            $balanceText = $balance.ToString([Globalization.CultureInfo]::InvariantCulture)
        }
        $snapshot.credits = @{ balance=$balanceText; hasCredits=($Usage.credits.hasCredits -eq $true); unlimited=($Usage.credits.unlimited -eq $true) }
    }
    return [pscustomobject]$snapshot
}

function Write-SharedUsage {
    param([switch] $Force)
    # A file timer may publish the latest reading, but must never change its original age.
    if (-not $script:SharedEnabled -or -not $script:WriteUsageEnabled -or -not $script:Usage -or $script:RefreshError) { return }
    if (-not $Force -and [long]$script:Usage.fetchedAt -eq $script:LastWrittenFetchedAt) { return }
    $temporary = $null
    try {
        $target = Resolve-UsageFilePath $script:UsageOutputPath
        # Never overwrite another computer's export or an unrelated existing JSON file.
        if ([IO.File]::Exists($target)) {
            if ([IO.FileInfo]::new($target).Length -gt 65536) { throw 'The output file already exists and is not this widget''s snapshot.' }
            $existing = [IO.File]::ReadAllText($target) | ConvertFrom-Json
            if ($existing.schemaVersion -ne 1 -or $existing.sourceId -ne $script:SharingSourceId) { throw 'The output file belongs to another source. Choose a different filename.' }
        }
        if ($script:ReadUsageEnabled -and $target -eq (Resolve-UsageFilePath $script:UsageInputPath)) { throw 'Input and output must be different files.' }
        # Require the selected directory to exist; the widget does not create arbitrary folders.
        $directory = [IO.Path]::GetDirectoryName($target)
        if (-not [IO.Directory]::Exists($directory)) { throw 'The output folder is unavailable.' }
        $snapshot = ConvertTo-SharedUsage $script:Usage
        $payload = @{ schemaVersion=1; sourceId=$script:SharingSourceId; displayName=$script:LocalDisplayName; refreshIntervalMinutes=$script:RefreshIntervalMinutes; writtenAt=[DateTimeOffset]::Now.ToUnixTimeSeconds(); usage=$snapshot }
        # Write beside the destination and replace it atomically to avoid partial reads during sync.
        $temporary = Join-Path $directory ('.codex-usage-' + [guid]::NewGuid().ToString('N') + '.tmp')
        [IO.File]::WriteAllText($temporary, ($payload | ConvertTo-Json -Depth 7 -Compress), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $target, $true)
        $script:LastWrittenFetchedAt = $snapshot.fetchedAt
        $script:LastWrittenAt = [DateTimeOffset]::Now
        $script:WriteError = $null
    } catch { $script:WriteError = $_.Exception.Message }
    finally {
        # Remove only this attempt's known temporary file after a failed replacement.
        if ($temporary -and [IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Read-SharedUsage {
    if (-not $script:SharedEnabled -or -not $script:ReadUsageEnabled) { return }
    try {
        $path = Resolve-UsageFilePath $script:UsageInputPath
        if ($script:WriteUsageEnabled -and $path -eq (Resolve-UsageFilePath $script:UsageOutputPath)) { throw 'Input and output must be different files.' }
        # Limit file size and sharing mode so malformed or actively synced files cannot hang parsing.
        $file = [IO.FileInfo]::new($path)
        if (-not $file.Exists) { throw 'The input file has not arrived yet.' }
        if ($file.Length -gt 65536) { throw 'The input file is too large to be a usage snapshot.' }
        $text = [IO.File]::ReadAllText($path)
        if ($text.Length -gt 65536) { throw 'The input file is too large to be a usage snapshot.' }
        $incoming = $text | ConvertFrom-Json
        if ($incoming.schemaVersion -ne 1 -or $incoming.sourceId -notmatch '^[0-9a-f]{32}$' -or -not $incoming.usage) { throw 'This is not a supported usage snapshot.' }
        if ($incoming.sourceId -eq $script:SharingSourceId) { throw 'This file belongs to this computer; select the shared computer''s file.' }
        $snapshot = ConvertTo-SharedUsage $incoming.usage
        # Keep the last valid reading if an older OneDrive copy temporarily replaces the file.
        if ($script:RemoteUsage -and $script:RemoteSourceId -eq [string]$incoming.sourceId -and $snapshot.fetchedAt -lt $script:RemoteUsage.fetchedAt) { throw 'An older synced copy arrived; keeping the newer reading.' }
        $label = ([string]$incoming.displayName -replace '[\p{C}]','').Trim()
        $script:RemoteDisplayName = if ($label) { $label.Substring(0,[Math]::Min(40,$label.Length)) } else { 'Shared computer' }
        $script:RemoteSourceId = [string]$incoming.sourceId
        $script:RemoteUsage = $snapshot
        $script:RemoteRefreshMinutes = if ($incoming.refreshIntervalMinutes -in @(0,1,5,15,30)) { [int]$incoming.refreshIntervalMinutes } else { 5 }
        $script:LastReadAt = [DateTimeOffset]::Now
        $script:ReadError = $null
    } catch { $script:ReadError = $_.Exception.Message }
    # File failures and notification failures remain separate from each other.
    if (-not $script:ReadError) {
        try { Show-SharedUsageWarnings; $script:SharedAlertError = $null } catch { $script:SharedAlertError = $_.Exception.Message }
    }
}

function Get-SharingStatus {
    param([ValidateSet('Write','Read','Source')] [string] $Kind)
    # Report file operations separately from the source account's actual update time.
    if ($Kind -eq 'Source') {
        if (-not $script:SharedEnabled -or -not $script:ReadUsageEnabled) { return '' }
        if (-not $script:RemoteUsage) { return 'Shared computer: waiting for a valid reading' }
        $age = [Math]::Max(0,([DateTimeOffset]::Now.ToUnixTimeSeconds() - $script:RemoteUsage.fetchedAt))
        $limit = [Math]::Max(120, 2 * $script:RemoteRefreshMinutes * 60)
        $ageText = if ($age -lt 60) { '{0}s' -f [int]$age } elseif ($age -lt 3600) { '{0}m' -f [int]($age / 60) } else { '{0:N1}h' -f ($age / 3600) }
        return "$script:RemoteDisplayName · usage updated $ageText ago" + $(if ($age -gt $limit) { ' · stale' } else { '' })
    }
    $enabled = if ($Kind -eq 'Write') { $script:WriteUsageEnabled } else { $script:ReadUsageEnabled }
    if (-not $script:SharedEnabled -or -not $enabled) { return "$Kind is off" }
    $errorText = if ($Kind -eq 'Write') { $script:WriteError } else { $script:ReadError }
    if ($errorText) { return "$Kind`: $errorText" }
    $last = if ($Kind -eq 'Write') { $script:LastWrittenAt } else { $script:LastReadAt }
    $interval = if ($Kind -eq 'Write') { $script:WriteIntervalMinutes } else { $script:ReadIntervalMinutes }
    $cadence = if ($interval -eq -1) { "matches widget ($script:RefreshIntervalMinutes min; 0 = manual)" } elseif ($interval -eq 0) { 'manual only' } else { "every $interval min" }
    return "$Kind`: " + $(if ($last) { 'last completed ' + $last.ToLocalTime().ToString('h:mm:ss tt') } else { 'waiting' }) + " · $cadence"
}

function Invoke-SharingTick {
    # Check independent file timers even while the desktop window is minimized to the tray.
    if (-not $script:SharedEnabled) { return }
    $now = [DateTimeOffset]::Now
    if ($script:WriteUsageEnabled -and $script:WriteIntervalMinutes -gt 0 -and $now -ge $script:NextWriteAt) {
        Write-SharedUsage
        $script:NextWriteAt = $now.AddMinutes($script:WriteIntervalMinutes)
    }
    if ($script:ReadUsageEnabled -and $script:ReadIntervalMinutes -gt 0 -and $now -ge $script:NextReadAt) {
        Read-SharedUsage
        $script:NextReadAt = $now.AddMinutes($script:ReadIntervalMinutes)
        if ($window.IsVisible) { Update-Display }
    }
}

function Invoke-WidgetRefresh {
    # Manual refresh checks the other file immediately and publishes the next fresh local reading.
    Read-SharedUsage
    $script:PublishOnRefresh = $true
    Start-UsageRefresh
    Update-Display
}

function Set-AccountScheme {
    param([string] $Name, [switch] $Remote)
    # Apply whole palettes so the three usage colors remain coordinated.
    if (-not $script:ColorSchemes.Contains($Name)) { return }
    if ($Remote) { $script:RemoteScheme = $Name }
    else {
        $script:LocalScheme = $Name
        $colors = $script:ColorSchemes[$Name]
        $script:PrimaryColor = $colors[0]
        $script:SecondaryColor = $colors[1]
        $script:CreditColor = $colors[2]
    }
}

function Initialize-SharedWarnings {
    # Restore only shared notification history; never mix it with the local account's state file.
    if (-not $script:StateDirectory) { return }
    $script:SharedAlertStatePath = Join-Path $script:StateDirectory 'shared-warning-state.json'
    if (-not (Test-Path -LiteralPath $script:SharedAlertStatePath)) { return }
    try {
        $history = Get-Content -LiteralPath $script:SharedAlertStatePath -Raw | ConvertFrom-Json -AsHashtable
        if ($history.sourceId -notmatch '^[0-9a-f]{32}$' -or $history.states -isnot [Collections.IDictionary]) { return }
        foreach ($key in @('primary','secondary','primaryReset')) {
            # Ignore malformed saved flags and reset baselines instead of generating false alerts.
            $entry = $history.states[$key]
            if ($entry -isnot [Collections.IDictionary] -or $entry.Notified -isnot [bool]) { continue }
            if ($key -eq 'primaryReset' -and ($entry.ResetsAt -isnot [long] -and $entry.ResetsAt -isnot [int] -or
                $entry.ResetsAt -le 0 -or $null -eq $entry.UsedPercent -or $entry.UsedPercent -lt 0 -or $entry.UsedPercent -gt 100 -or [double]::IsNaN([double]$entry.UsedPercent))) { continue }
            $script:SharedAlertStates[$key] = $entry
        }
        $script:SharedWarningSourceId = $history.sourceId
    } catch { $script:SharedAlertStates = @{} }
}

function Save-SharedWarnings {
    # Persist source identity with sent flags so restarting or switching accounts cannot repeat old alerts.
    if (-not $script:SharedAlertStatePath) { return }
    $json = @{sourceId=$script:SharedWarningSourceId;states=$script:SharedAlertStates} | ConvertTo-Json -Compress -Depth 5
    if ($json -ne $script:LastSharedWarningState) {
        $json | Set-Content -LiteralPath $script:SharedAlertStatePath -Encoding utf8
        $script:LastSharedWarningState = $json
    }
}

function Show-SharedUsageWarnings {
    # Only valid, sufficiently recent imported readings can produce second-account notifications.
    if (-not $script:SharedEnabled -or -not $script:ReadUsageEnabled -or -not $script:RemoteUsage -or $script:ReadError) { return }
    $age = [DateTimeOffset]::Now.ToUnixTimeSeconds() - $script:RemoteUsage.fetchedAt
    if ($age -gt [Math]::Max(120,2 * $script:RemoteRefreshMinutes * 60)) { return }
    if ($script:SharedWarningSourceId -ne $script:RemoteSourceId) {
        $script:SharedAlertStates = @{}
        $script:SharedWarningSourceId = $script:RemoteSourceId
    }
    # Reuse the same threshold/reset rules in a synchronous, isolated notification context.
    $original = @{Usage=$script:Usage;PrimaryAlertThreshold=$script:PrimaryAlertThreshold;SecondaryAlertThreshold=$script:SecondaryAlertThreshold;
        NotifyPrimaryReset=$script:NotifyPrimaryReset;AlertStates=$script:AlertStates;AlertStatePath=$script:AlertStatePath;LastWarningState=$script:LastWarningState;ProcessingSharedWarnings=$script:ProcessingSharedWarnings}
    try {
        $script:Usage = $script:RemoteUsage
        $script:PrimaryAlertThreshold = $script:SharedPrimaryAlertThreshold
        $script:SecondaryAlertThreshold = $script:SharedSecondaryAlertThreshold
        $script:NotifyPrimaryReset = $script:SharedNotifyPrimaryReset
        $script:AlertStates = $script:SharedAlertStates
        $script:AlertStatePath = $null
        $script:ProcessingSharedWarnings = $true
        Show-UsageWarnings -AccountName $script:RemoteDisplayName
    } finally {
        # Restore the local account even if Windows refuses to display a notification.
        foreach ($key in $original.Keys) { Set-Variable -Scope Script -Name $key -Value $original[$key] }
    }
    Save-SharedWarnings
}

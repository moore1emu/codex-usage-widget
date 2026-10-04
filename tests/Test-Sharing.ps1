# Verify changes and check-ins using private scratch exports, without starting the widget.
$ErrorActionPreference='Stop'
$script:WidgetDirectory=(Split-Path -Parent $PSScriptRoot)
. (Join-Path $script:WidgetDirectory 'WidgetSharing.ps1')
$folder=Join-Path ([IO.Path]::GetTempPath()) ('CodexUsageWidget-sharing-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $folder)
$script:SharedEnabled=$true;$script:WriteUsageEnabled=$true;$script:RefreshIntervalMinutes=1
$script:UsageOutputPath=Join-Path $folder 'local.json'
$now=[DateTimeOffset]::Now.ToUnixTimeSeconds()
$script:Usage=@{fetchedAt=$now;planType='plus';ordinaryUsageAllowed=$true;primary=@{usedPercent=25;resetsAt=$now+5000;windowDurationMins=300};secondary=@{usedPercent=40;resetsAt=$now+50000};credits=@{balance='50.25';hasCredits=$true;unlimited=$false}}
Write-SharedUsage -Force
if ($script:WriteError) {throw $script:WriteError}
$first=[IO.File]::ReadAllText($script:UsageOutputPath)
$firstStamp=[IO.File]::GetLastWriteTimeUtc($script:UsageOutputPath)
# Fresh checks and Force do not touch an unchanged file or its timestamps.
$script:Usage.fetchedAt=$now+1
Write-SharedUsage -Force
if ([IO.File]::ReadAllText($script:UsageOutputPath) -ne $first -or [IO.File]::GetLastWriteTimeUtc($script:UsageOutputPath) -ne $firstStamp) {throw 'Unchanged refresh rewrote the export.'}
# Recover publication state after a restart without writing an unnecessary check-in.
$script:PublishedTarget='';$script:PublishedUsageKey=$null;$script:LastWrittenAt=$null
Write-SharedUsage -Force
if ([IO.File]::ReadAllText($script:UsageOutputPath) -ne $first) {throw 'Restart rewrote unchanged export.'}
# Real usage changes publish immediately and update only the meaningful change date.
$script:Usage.primary.usedPercent=26
Write-SharedUsage
$changed=Get-Content $script:UsageOutputPath -Raw | ConvertFrom-Json
if ($changed.usage.primary.usedPercent -ne 26 -or $changed.usageChangedAt -ne $now+1) {throw 'Usage change was not published.'}
$script:Usage.fetchedAt=$now+2;$script:LocalDisplayName='Renamed local'
Write-SharedUsage
$renamed=Get-Content $script:UsageOutputPath -Raw | ConvertFrom-Json
if ($renamed.displayName -ne 'Renamed local' -or $renamed.usageChangedAt -ne $changed.usageChangedAt) {throw 'Metadata change moved the usage-change date.'}
# Timer-based check-ins retain the actual snapshot age and last usage-change date.
$script:LastWrittenAt=[DateTimeOffset]::Now.AddMinutes(-31)
$script:WriteIntervalMinutes=-1
Invoke-SharingTick
$heartbeat=Get-Content $script:UsageOutputPath -Raw | ConvertFrom-Json
if ($heartbeat.checkInMinutes -ne 30 -or $heartbeat.usage.fetchedAt -ne $now+2 -or $heartbeat.usageChangedAt -ne $changed.usageChangedAt -or ([DateTimeOffset]::Now-$script:LastWrittenAt).TotalMinutes -gt 1) {throw '30-minute check-in changed age or missed publication.'}
$after=[IO.File]::ReadAllText($script:UsageOutputPath)
$script:LastWrittenAt=[DateTimeOffset]::Now.AddMinutes(-31);$script:WriteIntervalMinutes=0
Invoke-SharingTick
if ([IO.File]::ReadAllText($script:UsageOutputPath) -ne $after -or ([DateTimeOffset]::Now-$script:LastWrittenAt).TotalMinutes -lt 30) {throw 'Manual-only sharing generated an automatic check-in.'}
# Import unchanged files without reparsing, and retain a valid cached reading during sync errors.
$script:ReadUsageEnabled=$true;$script:UsageInputPath=Join-Path $folder 'remote.json'
$payload=$heartbeat;$payload.sourceId='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';$payload.usage.fetchedAt=$now-600;$payload.usageChangedAt=$now-600
$payload | ConvertTo-Json -Depth 7 | Set-Content $script:UsageInputPath
Read-SharedUsage
if ($script:ReadError -or (Get-SharingStatus Source) -match 'stale' -or (Get-SharingStatus Source) -notmatch 'last usage change.*last checked') {throw '30-minute peer status is wrong.'}
$cached=$script:RemoteUsage
Read-SharedUsage
if (-not [object]::ReferenceEquals($cached,$script:RemoteUsage)) {throw 'Unchanged file was reparsed.'}
# Stale status uses the check-in allowance, but old snapshots still cannot trigger alerts.
$script:RemoteUsage.fetchedAt=$now-2000
if ((Get-SharingStatus Source) -notmatch 'stale') {throw 'Offline peer is not marked stale.'}
$script:Notified=$false
function Show-UsageWarnings { $script:Notified=$true }
$script:RemoteUsage.fetchedAt=$now-600
Show-SharedUsageWarnings
if ($script:Notified) {throw 'Check-in made an old usage reading eligible for notifications.'}
[IO.File]::WriteAllText($script:UsageInputPath,'{partial')
Read-SharedUsage
if (-not $script:ReadError -or -not [object]::ReferenceEquals($cached,$script:RemoteUsage)) {throw 'Partial sync erased the cached reading.'}
Write-Output 'PASS: change-only publication, unchanged Force/restart, usage versus metadata timestamps, 30-minute matched check-ins, manual-only behavior, unchanged-file read cache, stale detection, notification freshness, and partial sync retention.'

# Full allowance must ignore drifting primary resets, including across publication restarts.
$script:Usage.primary.usedPercent=0
$script:Usage.primary.resetsAt=$now+10000
Write-SharedUsage
$idleExport=[IO.File]::ReadAllText($script:UsageOutputPath)
if (($idleExport | ConvertFrom-Json).usage.primary.resetsAt -ne 0) {throw 'Unused five-hour reset was exported.'}
$script:Usage.primary.resetsAt=$now+11000
Write-SharedUsage -Force
if ([IO.File]::ReadAllText($script:UsageOutputPath) -ne $idleExport) {throw 'Drifting unused reset rewrote the export.'}
$script:PublishedTarget='';$script:PublishedUsageKey=$null;$script:LastWrittenAt=$null
Write-SharedUsage
if ([IO.File]::ReadAllText($script:UsageOutputPath) -ne $idleExport) {throw 'Unused reset drift rewrote the export after restart.'}
# The first real usage restores the reported reset; weekly changes still publish while idle.
$script:Usage.primary.usedPercent=0.1
Write-SharedUsage
if ((Get-Content $script:UsageOutputPath -Raw | ConvertFrom-Json).usage.primary.resetsAt -ne $now+11000) {throw 'Active five-hour reset was not restored.'}
$script:Usage.primary.usedPercent=0;Write-SharedUsage
$script:Usage.secondary.resetsAt+=60;Write-SharedUsage
if ((Get-Content $script:UsageOutputPath -Raw | ConvertFrom-Json).usage.secondary.resetsAt -ne $script:Usage.secondary.resetsAt) {throw 'Weekly reset changes were ignored while primary was unused.'}
Write-Output 'PASS: unused five-hour reset normalization, drift suppression, restart recovery, active-window restoration and independent weekly changes.'

# Report temporary artifacts without adding account readings to the checkout.
Write-Output ('Temporary test files: ' + $folder)

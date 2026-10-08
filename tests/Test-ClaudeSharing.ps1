$ErrorActionPreference='Stop'
$script:WidgetDirectory=Split-Path -Parent $PSScriptRoot
. (Join-Path $script:WidgetDirectory 'WidgetSharing.ps1')
. (Join-Path $script:WidgetDirectory 'WidgetClaude.ps1')
. (Join-Path $script:WidgetDirectory 'WidgetClaudeSharing.ps1')
# Keep exports and independent alert history in a disposable private test directory.
$script:StateDirectory=Join-Path ([IO.Path]::GetTempPath()) ('CodexUsageWidget-claude-sharing-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $script:StateDirectory 'ClaudeSharing'))
function Update-Display {}
function Show-UsageWarnings {param($AccountName) $script:ObservedClaudeAlerts++}
$script:ObservedClaudeAlerts=0
$script:Usage=@{primary=@{usedPercent=19}}
$script:LocalEnabled=$false
$script:LocalDisplayName='Original Codex name'
$script:ClaudeOptions.Enabled=$true
$script:ClaudeOptions.Name='Example Claude'
$script:ClaudeStatus='Subscription · updated now'
$script:ClaudeUsage=ConvertTo-ClaudeUsage @{five_hour=@{utilization=40;resets_at=[DateTimeOffset]::Now.AddHours(2).ToString('o')};seven_day=@{utilization=70;resets_at=[DateTimeOffset]::Now.AddDays(4).ToString('o')}}
$script:SharedClaudeOptions.Enabled=$false;$script:SharedClaudeOptions.WriteEnabled=$true
$script:SharedClaudeOptions.OutputPath=Join-Path $script:StateDirectory 'local-claude.json'
# Publishing Claude must not borrow disabled local Codex preferences or identity.
Invoke-ClaudeSharing -Force
if ($script:ClaudeFileState.WriteError) {throw $script:ClaudeFileState.WriteError}
$published=Get-Content -LiteralPath $script:SharedClaudeOptions.OutputPath -Raw | ConvertFrom-Json
if ($published.provider -ne 'Claude' -or $published.displayName -ne 'Example Claude' -or $published.usage.primary.usedPercent -ne 40) {throw 'Claude export used incorrect account values.'}
if ($script:Usage.primary.usedPercent -ne 19 -or $script:LocalEnabled -ne $false -or $script:LocalDisplayName -ne 'Original Codex name') {throw 'Claude export leaked its render context into Codex.'}
$stamp=[IO.File]::GetLastWriteTimeUtc($script:SharedClaudeOptions.OutputPath)
$script:ClaudeUsage.fetchedAt++
Invoke-ClaudeSharing -Force
if ([IO.File]::GetLastWriteTimeUtc($script:SharedClaudeOptions.OutputPath) -ne $stamp) {throw 'An unchanged Claude poll rewrote shared JSON.'}
# Claude uses the same idle rules without changing Codex's independent publication state.
$script:ClaudeUsage.primary.usedPercent=0
Invoke-ClaudeSharing -Fresh
$idle=[IO.File]::ReadAllText($script:SharedClaudeOptions.OutputPath)
$script:ClaudeUsage.primary.resetsAt+=60;$script:ClaudeUsage.secondary.resetsAt--
$script:ClaudeUsage.fetchedAt++
Invoke-ClaudeSharing -Fresh
if ([IO.File]::ReadAllText($script:SharedClaudeOptions.OutputPath) -ne $idle) {throw 'Idle Claude reset drift rewrote the export.'}
# Restarts and scheduled check-ins must keep Claude's last published weekly reset.
$script:ClaudeFileState.PublishedTarget='';$script:ClaudeFileState.PublishedUsageKey=$null;$script:ClaudeFileState.LastWrittenAt=$null
Invoke-ClaudeSharing -Force
if ([IO.File]::ReadAllText($script:SharedClaudeOptions.OutputPath) -ne $idle) {throw 'Claude restart recorded idle reset drift.'}
$script:ClaudeFileState.LastWrittenAt=[DateTimeOffset]::Now.AddMinutes(-31)
Invoke-ClaudeSharing
$checked=Get-Content -LiteralPath $script:SharedClaudeOptions.OutputPath -Raw | ConvertFrom-Json
$prior=$idle | ConvertFrom-Json
if ($checked.usage.secondary.resetsAt -ne $prior.usage.secondary.resetsAt -or $checked.usageChangedAt -ne $prior.usageChangedAt) {throw 'Claude check-in recorded idle reset drift.'}
# The first activity restores current reset dates through the normal fresh-reading path.
$script:ClaudeUsage.primary.usedPercent=40
Invoke-ClaudeSharing -Fresh
$published=Get-Content -LiteralPath $script:SharedClaudeOptions.OutputPath -Raw | ConvertFrom-Json
if ($published.usage.secondary.resetsAt -ne $script:ClaudeUsage.secondary.resetsAt -or $script:Usage.primary.usedPercent -ne 19) {throw 'Claude active resets or Codex context isolation failed.'}
# Import a distinct computer's Claude file and use its display name.
$script:SharedClaudeOptions.Enabled=$true
$script:SharedClaudeOptions.ReadEnabled=$true
$script:SharedClaudeOptions.InputPath=Join-Path $script:StateDirectory 'shared-claude.json'
$published.sourceId=[guid]::NewGuid().ToString('N');$published.displayName='Example shared Claude'
$published | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $script:SharedClaudeOptions.InputPath
Invoke-ClaudeSharing -Force
if ($script:ClaudeFileState.ReadError) {throw $script:ClaudeFileState.ReadError}
if ($script:SharedClaudeOptions.Name -ne 'Example shared Claude' -or $script:SharedClaudeUsage.primary.usedPercent -ne 40) {throw 'Shared Claude identity or usage was lost.'}
# A Codex file cannot silently populate the shared Claude card.
$published.provider='Codex'
$published | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $script:SharedClaudeOptions.InputPath
Invoke-ClaudeSharing -Force
if ($script:ClaudeFileState.ReadError -notmatch 'Codex snapshot') {throw 'A Codex file was accepted as Claude.'}
# Matched imports continue while local Claude is disabled; stale readings never trigger alerts.
$script:ClaudeOptions.Enabled=$false
$published.provider='Claude';$published.usage.fetchedAt=[DateTimeOffset]::Now.AddHours(-2).ToUnixTimeSeconds()
$published.usageChangedAt=$published.usage.fetchedAt;$published.sourceId=[guid]::NewGuid().ToString('N')
$published | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $script:SharedClaudeOptions.InputPath
$before=$script:ObservedClaudeAlerts
$script:ClaudeFileState.NextReadAt=[DateTimeOffset]::MinValue
Invoke-ClaudeSharing
if ($script:ObservedClaudeAlerts -ne $before -or -not $script:ClaudeFileState.LastReadAt) {throw 'Remote-only matched reads or stale-alert filtering failed.'}
# The master lock stops file operations completely while preserving settings.
$script:SharedClaudeOptions.Enabled=$false
$lastRead=$script:ClaudeFileState.LastReadAt
Invoke-ClaudeSharing -Force
if ($script:ClaudeFileState.LastReadAt -ne $lastRead) {throw 'Disabled Claude sharing continued reading.'}
Write-Output 'PASS: separate Claude export/import, change-only writes, provider validation, source names, remote-only matched polling, stale alerts and context isolation.'
Write-Output ('Temporary test files: '+$script:StateDirectory)

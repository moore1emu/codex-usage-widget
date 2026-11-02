# Exercise the production reader's reporting block without starting Codex or reading credentials.
$ErrorActionPreference='Stop'
$project=Split-Path -Parent $PSScriptRoot
$source=[IO.File]::ReadAllText((Join-Path $project 'Get-CodexUsage.ps1'))
$start=$source.IndexOf('    # Prefer the Codex quota bucket')
$end=$source.IndexOf("`n}`r`ncatch {",$start)
if ($start -lt 0 -or $end -lt 0) { throw 'Reader reporting block was not found.' }
$report=[scriptblock]::Create('param($response)'+"`r`n"+$source.Substring($start,$end-$start))
# Use distinct synthetic percentages and reset times to detect swapped or invented windows.
$five=@{usedPercent=23;windowDurationMins=300;resetsAt=1900000000}
$week=@{usedPercent=41;windowDurationMins=10080;resetsAt=1900500000}
$weeklyOnly=$null
foreach ($case in @(
    @{Name='weekly-only primary';Primary=$week;Secondary=$null;Five=$false;Week=$true},
    @{Name='weekly-only secondary';Primary=$null;Secondary=$week;Five=$false;Week=$true},
    @{Name='both normal';Primary=$five;Secondary=$week;Five=$true;Week=$true},
    @{Name='both reversed';Primary=$week;Secondary=$five;Five=$true;Week=$true},
    @{Name='five-hour only';Primary=$five;Secondary=$null;Five=$true;Week=$false}
)) {
    # Check both current bucketed and legacy API responses through the same production code.
    foreach ($legacy in @($false,$true)) {
        $bucket=@{planType='prolite';primary=$case.Primary;secondary=$case.Secondary;credits=@{hasCredits=$false;balance=$null}}
        $result=if ($legacy) {@{rateLimits=$bucket}} else {@{rateLimitsByLimitId=@{codex=$bucket}}}
        $usage=(& $report @{result=$result} | ConvertFrom-Json)
        if (($null -ne $usage.primary) -ne $case.Five -or ($null -ne $usage.secondary) -ne $case.Week) { throw ($case.Name+': wrong window presence.') }
        if ($case.Five -and ($usage.primary.usedPercent -ne 23 -or $usage.primary.resetsAt -ne $five.resetsAt)) { throw 'Five-hour values changed.' }
        if ($case.Week -and ($usage.secondary.usedPercent -ne 41 -or $usage.secondary.resetsAt -ne $week.resetsAt)) { throw 'Weekly values changed.' }
        if ($case.Name -eq 'weekly-only primary') { $weeklyOnly=$usage }
    }
}
# Keep older slot-based snapshots working when the service omitted duration metadata.
$legacyUsage=& $report @{result=@{rateLimits=@{primary=@{usedPercent=$null};secondary=@{usedPercent=20}}}} | ConvertFrom-Json
if ($null -ne $legacyUsage.primary.usedPercent -or $legacyUsage.secondary.usedPercent -ne 20) { throw 'Legacy unknown usage changed.' }
# Verify missing 5-hour quota stays unavailable in full and compact UI and in shared exports.
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
try {
    $script:Usage=$weeklyOnly
    $window.Show()
    foreach ($size in @(@(400,400),@(100,110))) {
        $window.Width=$size[0];$window.Height=$size[1];Wait-TestDispatcher 20
        Update-Display;$window.UpdateLayout()
        if ($primaryPercent.Text -ne '—' -or $compactPrimaryPercent.Text -ne '—') { throw 'Missing five-hour quota displayed a percentage.' }
        if ($secondaryPercent.Text -notmatch '^59%' -or $compactSecondaryPercent.Text -ne '59%') { throw 'Weekly-only allowance disappeared from the UI.' }
    }
    $shared=ConvertTo-SharedUsage $weeklyOnly
    if ($null -ne $shared.primary -or $shared.secondary.usedPercent -ne 41) { throw 'Shared export lost the weekly-only mapping.' }
} finally { Close-TestWidget }
Write-Output 'PASS: Codex duration mapping, weekly-only Pro, legacy responses, full/compact UI and shared export.'

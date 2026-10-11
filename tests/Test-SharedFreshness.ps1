# Build isolated production controls with synthetic readings and no live account connections.
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
try {
    $now=[DateTimeOffset]::Now.ToUnixTimeSeconds()
    $script:SharedEnabled=$true;$script:ReadUsageEnabled=$true
    $script:SharedClaudeOptions.Enabled=$true;$script:SharedClaudeOptions.ReadEnabled=$true
    $script:SharedClaudeUsage=@{fetchedAt=$now;primary=@{usedPercent=20;resetsAt=$now+7200};secondary=@{usedPercent=30;resetsAt=$now+400000};credits=$null}
    $codex=$script:RemoteUsage;$claude=$script:SharedClaudeUsage
    $window.Show();$window.Width=620;$window.Height=340;$window.UpdateLayout()

    # Thresholds use publisher time, with a reading-time fallback for legacy exports.
    $fresh=Get-SharedReadingState -Snapshot $codex -WrittenAt ($now-1800)
    $stale=Get-SharedReadingState -Snapshot $codex -WrittenAt ($now-1861)
    $expired=Get-SharedReadingState -Snapshot $codex -WrittenAt ($now-3601)
    if ($fresh.Stale -or -not $stale.Stale -or $stale.Expired -or -not $expired.Expired) {throw 'Shared freshness thresholds are incorrect.'}
    $codex.fetchedAt=$now-7200
    if ((Get-SharedReadingState -Snapshot $codex -WrittenAt $now).Stale -or -not (Get-SharedReadingState -Snapshot $codex).Expired) {throw 'Publisher check-in or legacy timestamp fallback failed.'}

    # Verify every connected layout and each independently detached imported account.
    foreach ($layout in @('Side by side','Stacked','Account picker','Separate windows')) {
        $script:AccountLayout=$layout;$script:SelectedAccount='Remote'
        $script:SharedClaudeOptions.Placement=if ($layout -eq 'Separate windows') {'Separate window'} else {'Follow layout'}
        $script:RemoteWrittenAt=$now-1920;$script:ClaudeFileState.RemoteWrittenAt=$now-1920
        Update-Display;$window.UpdateLayout()
        if ($script:SeparateView) {$script:SeparateView.Window.Show()}
        if ($script:SharedClaudeView) {$script:SharedClaudeView.Window.Show()}
        Update-Display
        foreach ($key in @('Remote','SharedClaude')) {
            if ($layout -eq 'Account picker') {$script:SelectedAccount=$key;Update-Display}
            $card=$script:AccountCards[$key]
            if ($card.AgeNotice.Text -ne 'Stale' -or $card.AgeNotice.Visibility -ne 'Visible' -or $card.Visual.Visibility -ne 'Visible') {throw "Stale values or line missing in $layout/$key."}
        }
        # Expiry hides meters while retaining the last calculated amounts and timestamp on hover.
        $script:RemoteWrittenAt=$now-7200;$script:ClaudeFileState.RemoteWrittenAt=$now-7200
        foreach ($key in @('Remote','SharedClaude')) {
            $script:SelectedAccount=$key;Update-Display
            $card=$script:AccountCards[$key]
            if ($card.Visual.Visibility -ne 'Collapsed' -or $card.AgeNotice.Text -notmatch 'Last refresh.*hours ago' -or
                $card.Container.ToolTip -notmatch '5-hour:.*% left' -or $card.Container.ToolTip -notmatch 'Last calculated') {throw "Expired values or hover history incorrect in $layout/$key."}
        }
        if (-not [object]::ReferenceEquals($codex,$script:RemoteUsage) -or -not [object]::ReferenceEquals($claude,$script:SharedClaudeUsage)) {throw 'Expiry discarded the last valid reading.'}
        # A new publisher check-in restores both cards without replacing their cached quota values.
        $script:RemoteWrittenAt=$now;$script:ClaudeFileState.RemoteWrittenAt=$now
        foreach ($key in @('Remote','SharedClaude')) {
            $script:SelectedAccount=$key;Update-Display
            $card=$script:AccountCards[$key]
            if ($card.Visual.Visibility -ne 'Visible' -or $card.AgeNotice.Visibility -ne 'Collapsed') {throw "Fresh values did not recover in $layout/$key."}
        }
    }
    # Compact and menu-height cards must retain the expired age message rather than old numbers.
    $script:AccountLayout='Side by side';$script:SharedClaudeOptions.Placement='Follow layout'
    $script:RemoteWrittenAt=$now-7200;$script:ClaudeFileState.RemoteWrittenAt=$now-7200
    foreach ($size in @(@{Width=240;Height=120},@{Width=900;Height=32})) {
        $window.Width=$size.Width;$window.Height=$size.Height;$window.UpdateLayout();Update-Display
        foreach ($key in @('Remote','SharedClaude')) {
            if ($script:AccountCards[$key].AgeNotice.Visibility -ne 'Visible' -or $script:AccountCards[$key].Visual.Visibility -ne 'Collapsed') {throw 'Compact expiry displayed cached values.'}
        }
    }
    Write-Output 'PASS: publisher-based 31-minute stale and one-hour expiry, Codex/Claude layouts, retained hover history, compact views and fresh recovery.'
}
finally {
    # Close only this test's windows; the user's running widget and settings remain untouched.
    Close-TestWidget
}

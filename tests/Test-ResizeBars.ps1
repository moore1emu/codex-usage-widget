# Exercise real layout controls with synthetic readings and no live account requests.
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
try {
    # Keep full reset schedules and mixed credits to reproduce the reported corner-resize behavior.
    $script:SharedEnabled=$false;$script:SharedClaudeOptions.Enabled=$false
    $script:ClaudeOptions.Enabled=$true;$script:ClaudeOptions.Placement='Follow layout'
    $script:PrimaryResetHours=25;$script:ClaudeOptions.ResetHours=25
    $script:ClaudeUsage=$script:Usage;$script:AccountLayout='Stacked'
    $window.Show()
    foreach ($layout in @('Stacked','Side by side')) {
        $script:AccountLayout=$layout
        $widths=if ($layout -eq 'Stacked') {@(110,140,170,180,220,260)} else {@(235,295,355,375,455,535)}
        $heights=if ($layout -eq 'Stacked') {@(350,400,420,440,500,520,560,620,700)} else {@(180,200,220,240,260,280,300,350,400)}
        $visibleBySize=@{}
        foreach ($height in $heights) {
            $previous=$false
            foreach ($width in $widths) {
                $window.Width=$width;$window.Height=$height;Wait-TestDispatcher 5
                # Repeat renders at each size to detect state that depends on the previous frame.
                $states=@()
                foreach ($repeat in 1..3) {
                    Update-Display;$window.UpdateLayout()
                    $local=$script:AccountCards.Local.Bindings;$claude=$script:AccountCards.Claude.Bindings
                    $shown=$local.primaryArea.Visibility -eq 'Visible' -and $local.primaryBar.Visibility -eq 'Visible'
                    $peer=$claude.primaryArea.Visibility -eq 'Visible' -and $claude.primaryBar.Visibility -eq 'Visible'
                    if ($shown -ne $peer) {throw "Connected bar visibility differs at $layout/$width/$height."}
                    $states+=$shown
                }
                if (@($states | Sort-Object -Unique).Count -ne 1) {throw "Repeated render changed bars at $layout/$width/$height."}
                if ($previous -and -not $shown) {throw "Widening hid bars at $layout/$width/$height."}
                $previous=$shown;$visibleBySize["$width/$height"]=$shown
            }
        }
        # Taller windows must not lose bars when status text or a fuller reset schedule appears.
        foreach ($width in $widths) {
            $previous=$false
            foreach ($height in $heights) {
                $shown=$visibleBySize["$width/$height"]
                if ($previous -and -not $shown) {throw "Increasing height hid bars at $layout/$width/$height."}
                $previous=$shown
            }
        }
        if (-not ($visibleBySize.Values -contains $true) -or -not ($visibleBySize.Values -contains $false)) {throw 'Sweep did not cover both bar transitions.'}
    }
    # Full details remain above bar priority, and taller/narrower views still retain them below the values.
    $script:AccountLayout='Stacked';$window.Width=170;$window.Height=700;Wait-TestDispatcher 5;Update-Display;$window.UpdateLayout()
    if ($script:AccountCards.Local.Bindings.primaryReset.Text -notmatch ',' -or $script:AccountCards.Local.Bindings.primaryBar.Visibility -ne 'Visible') {throw 'Tall narrow view lost the full schedule or bars.'}
    Write-Output 'PASS: stable repeated rendering, aligned bars and monotonic width/height transitions with full reset details.'
} finally {Close-TestWidget}
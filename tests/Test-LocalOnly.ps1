# Build isolated widget controls without live services or user settings.
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
try {
    # Enable every connection to verify the pause does not overwrite these choices.
    $script:LocalEnabled=$true;$script:ClaudeOptions.Enabled=$true
    $script:SharedEnabled=$true;$script:ReadUsageEnabled=$true;$script:WriteUsageEnabled=$true
    $script:SharedClaudeOptions.Enabled=$true;$script:SharedClaudeOptions.ReadEnabled=$true;$script:SharedClaudeOptions.WriteEnabled=$true
    $script:AccountLayout='Separate windows';$script:SharedClaudeOptions.Placement='Separate window'
    $window.Show();Update-Display
    # Exercise the real tray click rather than only its helper.
    $localOnlyItem.PerformClick()
    if (-not $script:LocalOnly -or (@(Get-EnabledAccounts) -join ',') -ne 'Local,Claude') {throw 'Tray pause did not restrict accounts to local sources.'}
    if ($script:SeparateWindowsActive -or $script:SharedClaudeWindowActive) {throw 'Paused shared windows remained active.'}
    if (-not $script:SharedEnabled -or -not $script:WriteUsageEnabled -or -not $script:SharedClaudeOptions.WriteEnabled) {throw 'Pause lost saved choices.'}
    $saved=Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    if ($saved.localOnly -ne $true -or $saved.writeUsageEnabled -ne $true) {throw 'Pause persistence lost connection settings.'}
    # Restore the production file functions replaced by the fixture's live-service safeguards.
    $source=[IO.File]::ReadAllText((Join-Path $script:TestProject 'WidgetSharing.ps1'))
    $ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
    foreach ($name in @('Read-SharedUsage','Write-SharedUsage')) {
        $node=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
        Invoke-Expression $node.Extent.Text
    }
    # Invalid paths would produce errors or reads if forced refresh bypassed the pause.
    $script:UsageOutputPath='';$script:UsageInputPath='';$script:WriteError=$null;$script:ReadError=$null
    Read-SharedUsage;Write-SharedUsage -Force;Invoke-SharingTick;Invoke-ClaudeSharing -Force -Fresh
    if ($script:ReadError -or $script:WriteError) {throw 'Paused sharing attempted file operations.'}
    Update-SharingTimer
    if ($script:SharingTimer.IsEnabled) {throw 'Applying settings restarted the paused timer.'}
    # Stub imports only for restoration so the test cannot touch real external files.
    function Read-SharedUsage {}
    function Write-SharedUsage {}
    $localOnlyItem.PerformClick()
    if ($script:LocalOnly -or (@(Get-EnabledAccounts)).Count -ne 4) {throw 'Tray toggle did not restore configured accounts.'}
    if (-not $script:SeparateWindowsActive -or -not $script:SharedClaudeWindowActive) {throw 'Separate shared windows were not restored.'}
    Write-Output 'PASS: tray local-only toggle, saved choices, persistence, forced-refresh guards and separate-window recovery.'
} finally {Close-TestWidget}
# Bootstrap production controls with temporary state; dot-source this helper from a test.
$ErrorActionPreference = 'Stop'
$script:TestProject = Split-Path -Parent $PSScriptRoot
if (-not $script:TestState) {
    # Keep test files outside the checkout and away from the user's saved preferences.
    $script:TestState = Join-Path ([IO.Path]::GetTempPath()) ('CodexUsageWidget-test-' + [guid]::NewGuid().ToString('N'))
}
[void](New-Item -ItemType Directory -Path $script:TestState -Force)
if (-not $InitialTestState) { $InitialTestState = @{ refreshIntervalMinutes=0;sharedEnabled=$false;readUsageEnabled=$false;topmost=$false } }
$InitialTestState | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:TestState 'widget-state.json') -Encoding utf8
# Parse production source so only the popup trap and real startup integration are replaced.
$source = [IO.File]::ReadAllText((Join-Path $script:TestProject 'CodexUsageWidget.ps1'))
$ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
$trap = $ast.Find({param($node) $node -is [Management.Automation.Language.TrapStatementAst]},$true)
$source = $source.Replace($trap.Extent.Text,'')
$source = $source.Replace('$script:WidgetDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path','$script:WidgetDirectory = $script:TestProject')
$source = $source.Replace("`$script:StateDirectory = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'CodexUsageWidget'",'$script:StateDirectory = $script:TestState')
# Suppress startup registration queries, live tray icons, and the automatic window/message loop.
$startup = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-LaunchAtSignIn'},$true)
$source = $source.Replace($startup.Extent.Text,'function Get-LaunchAtSignIn { return $false }')
$source = $source.Replace('$trayIcon.Visible = $true','$trayIcon.Visible = $false')
$source = $source.Replace('$window.Show()','# The test controls window visibility.')
$source = $source.Replace('[Windows.Threading.Dispatcher]::Run()','# The test controls the message loop.')
Invoke-Expression $source
# Prevent account-service calls and file imports when a test renders the actual windows.
function Start-UsageRefresh { }
function Read-SharedUsage { }
function Write-SharedUsage { }
# Supply clearly artificial account readings so no login or credentials are needed.
$now = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$script:Usage = @{ fetchedAt=$now;planType='plus';primary=@{usedPercent=27;resetsAt=$now+7000};secondary=@{usedPercent=55;resetsAt=$now+400000};credits=@{balance='838';hasCredits=$true} }
$script:RemoteUsage = @{ fetchedAt=$now;planType='pro';primary=@{usedPercent=51;resetsAt=$now+10000};secondary=@{usedPercent=12;resetsAt=$now+500000};credits=@{balance='210';hasCredits=$true} }
$script:RemoteDisplayName = 'Example shared account'

function Wait-TestDispatcher {
    param([int]$Milliseconds)
    # Run pending WPF events for a bounded interval without entering the permanent application loop.
    $frame = [Windows.Threading.DispatcherFrame]::new()
    $stopTimer = [Windows.Threading.DispatcherTimer]::new()
    $stopTimer.Interval = [TimeSpan]::FromMilliseconds($Milliseconds)
    $stopTimer.Add_Tick({ $frame.Continue=$false })
    try { $stopTimer.Start(); [Windows.Threading.Dispatcher]::PushFrame($frame) }
    finally { $stopTimer.Stop() }
}

function Close-TestWidget {
    # Follow normal shutdown and preserve temporary logs for inspection if a check fails.
    $script:ExitRequested = $true
    if ($window) { $window.Close() }
    Write-Output ('Temporary test files: ' + $script:TestState)
}

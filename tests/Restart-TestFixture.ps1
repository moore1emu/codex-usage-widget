# Run one isolated production lifecycle for the launcher shutdown checks.
param([string]$Scenario,[string]$StateFolder)
$script:TestState=$StateFolder
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
$script:SharedEnabled=$Scenario -ne 'Single'; $script:ReadUsageEnabled=$script:SharedEnabled
$script:AccountLayout='Separate windows'
$window.Show(); $window.UpdateLayout(); Update-Display
# Use deterministic dimensions so the parent can verify final state persistence after exit.
$window.Left=100; $window.Top=100; $window.Width=190; $window.Height=210
if ($script:SeparateView) {
    $peer=$script:SeparateView.Window
    $peer.Width=140; $peer.Height=155; $peer.Left=350; $peer.Top=100
}
# Ordinary closes must retain tray behavior before a full restart is requested.
if ($Scenario -in @('LocalHidden','BothHidden')) { $window.Close() }
if ($Scenario -eq 'BothHidden') { $peer.Close() }
try {
    if ($Scenario -eq 'SettingsOpen') {
        # Signal readiness only once the modeless settings dispatcher is about to run.
        $settingsSource=[IO.File]::ReadAllText((Join-Path $script:TestProject 'WidgetSettings.ps1'))
        $settingsSource=$settingsSource.Replace('[Windows.Threading.Dispatcher]::PushFrame($settingsFrame)',"[IO.File]::WriteAllText((Join-Path `$script:TestState 'ready'),'ready'); [Windows.Threading.Dispatcher]::PushFrame(`$settingsFrame)")
        Invoke-Expression $settingsSource
        Show-WidgetSettings
    } else {
        # Let the parent send the real registered launcher message while this dispatcher runs.
        [IO.File]::WriteAllText((Join-Path $StateFolder 'ready'),'ready')
        [Windows.Threading.Dispatcher]::Run()
    }
    # Confirm complete application shutdown rather than just disappearing account windows.
    if ($window.IsVisible -or ($script:SeparateView -and $peer.IsVisible) -or $script:SettingsForm) { throw 'Restart left a window open.' }
    [IO.File]::WriteAllText((Join-Path $StateFolder 'shutdown'),'all windows closed')
} finally {
    if (-not $script:ExitRequested) { Close-TestWidget }
}

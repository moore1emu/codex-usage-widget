# Exercise the actual launcher shutdown function under built-in Windows PowerShell 5.1.
param([Parameter(Mandatory)][string]$PwshPath)
$ErrorActionPreference='Stop'
# Load only the launcher's shutdown function, without invoking the real launch or restart prompt.
$project=(Split-Path -Parent $PSScriptRoot)
$source=[IO.File]::ReadAllText((Join-Path $project 'Start-AIUsageWidget.ps1'))
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
$close=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Close-ExistingWidgets'},$true)
Invoke-Expression $close.Extent.Text
# Check both script filenames without querying or touching the user's running processes.
$detect=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ExistingWidgetProcesses'},$true)
Invoke-Expression $detect.Extent.Text
$script:DetectionPaths=@((Join-Path $project 'AIUsageWidget.ps1'),(Join-Path $project 'CodexUsageWidget.ps1'))
function Get-CimInstance {
    param($Filter)
    # Include unrelated script arguments and desktop sessions to verify the ownership boundary.
    $session=(Get-Process -Id $PID).SessionId
    [pscustomobject]@{ProcessId=11;SessionId=$session;CommandLine=('pwsh.exe -File "'+$script:DetectionPaths[0]+'"')}
    [pscustomobject]@{ProcessId=12;SessionId=$session;CommandLine=('pwsh.exe -File "'+$script:DetectionPaths[1]+'"')}
    [pscustomobject]@{ProcessId=13;SessionId=$session;CommandLine=('pwsh.exe -File "'+$script:DetectionPaths[0]+'.other"')}
    [pscustomobject]@{ProcessId=14;SessionId=($session+1);CommandLine=('pwsh.exe -File "'+$script:DetectionPaths[0]+'"')}
}
function Invoke-CimMethod {
    param($InputObject,$MethodName)
    # Supply the current test user identity rather than inspecting any other process owner.
    [pscustomobject]@{ReturnValue=0;Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
}
$detected=@(Get-ExistingWidgetProcesses -WidgetPath $script:DetectionPaths)
if (($detected.ProcessId -join ',') -ne '11,12') { throw 'Launcher did not isolate current and legacy widget paths.' }
Remove-Item Function:Get-CimInstance,Function:Invoke-CimMethod
Write-Output 'PASS: current/legacy filename detection excludes other scripts and sessions.'
foreach ($scenario in @('Visible','LocalHidden','BothHidden','SettingsOpen','Single','FourAccounts','LegacyTitle')) {
    # Target only this isolated child process; the user's running widget remains untouched.
    $state=Join-Path ([IO.Path]::GetTempPath()) ('CodexUsageWidget-restart-'+$scenario+'-'+[guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $state)
    $fixture=Join-Path $PSScriptRoot 'Restart-TestFixture.ps1'
    $arguments='-NoProfile -STA -ExecutionPolicy Bypass -File "{0}" -Scenario {1} -StateFolder "{2}"' -f $fixture,$scenario,$state
    $child=Start-Process -FilePath $PwshPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $state 'errors.txt')
    # Retain the Windows process handle so PowerShell 5.1 can read ExitCode after a graceful exit.
    [void]$child.Handle
    try {
        # Bound fixture startup so a failure produces diagnostics instead of an indefinite wait.
        $deadline=[DateTime]::UtcNow.AddSeconds(20)
        while (-not [IO.File]::Exists((Join-Path $state 'ready')) -and -not $child.HasExited -and [DateTime]::UtcNow -lt $deadline) {Start-Sleep -Milliseconds 100}
        if (-not [IO.File]::Exists((Join-Path $state 'ready'))) {throw ('Fixture failed: '+(Get-Content (Join-Path $state 'errors.txt') -Raw))}
        $instance=[pscustomobject]@{ProcessId=$child.Id;CreationDate=$child.StartTime}
        Close-ExistingWidgets @($instance)
        if (-not $child.WaitForExit(3000) -or $child.ExitCode -ne 0 -or -not [IO.File]::Exists((Join-Path $state 'shutdown'))) {throw ('Shutdown failed for '+$scenario+': '+(Get-Content (Join-Path $state 'errors.txt') -Raw))}
        # Verify shutdown persisted each account's final size before the child exited.
        $saved=Get-Content (Join-Path $state 'widget-state.json') -Raw | ConvertFrom-Json
        if ($scenario -ne 'Single' -and ($saved.separateLocalBounds.width -ne 190 -or $saved.separateRemoteBounds.width -ne 140)) {throw 'Restart lost separate window dimensions.'}
        Write-Output ('PASS: shortcut shutdown '+$scenario+'; clean exit and saved positions/sizes.')
    } finally {
        # Clean up only this test's child after a failure and retain its logs for inspection.
        if (-not $child.HasExited) { $child.Kill() }
        $child.Dispose()
        Write-Output ('Temporary test files: ' + $state)
    }
}

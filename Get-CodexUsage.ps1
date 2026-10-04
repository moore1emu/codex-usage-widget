# Return startup and service failures through the widget's JSON error response.
$ErrorActionPreference = 'Stop'

function Read-LineWithTimeout {
    param(
        [Parameter(Mandatory)] [System.IO.StreamReader] $Reader,
        [int] $TimeoutMilliseconds = 15000
    )

    # Wait for one service message without blocking indefinitely.
    $task = $Reader.ReadLineAsync()
    if (-not $task.Wait($TimeoutMilliseconds)) {
        throw 'Timed out waiting for the Codex usage service.'
    }
    return $task.Result
}

# Track the child process so it can be released on success or failure.
$process = $null
$processStarted = $false
try {
    # Prefer a native Codex executable already available on this computer's PATH.
    $codexCommand = Get-Command codex.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $codex = if ($codexCommand) { $codexCommand.Source } else { $null }
    # Explorer may not inherit Codex's PATH; inspect its local versioned installation.
    if (-not $codex) {
        $codexBin = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
        $candidates = @(
            # Include unversioned and versioned layouts without hard-coding a build ID.
            Get-Item -LiteralPath (Join-Path $codexBin 'codex.exe') -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $codexBin -Directory -ErrorAction SilentlyContinue |
                ForEach-Object { Get-Item -LiteralPath (Join-Path $_.FullName 'codex.exe') -ErrorAction SilentlyContinue }
        )
        # Use the most recently installed executable when older builds remain on disk.
        $codex = ($candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    }
    # Explain how to recover when neither discovery method finds Codex.
    if (-not $codex) {
        throw 'Codex could not be found. Install and open Codex on this computer, sign in, then restart the widget. If installed in a custom location, add the folder containing codex.exe to PATH.'
    }
    # Start the usage service with redirected pipes and no console window.
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $codex
    $startInfo.ArgumentList.Add('app-server')
    $startInfo.ArgumentList.Add('--stdio')
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.Environment['HOME'] = [Environment]::GetFolderPath('UserProfile')

    # Launch the locally discovered Codex executable.
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void] $process.Start()
    $processStarted = $true
    # Drain diagnostics while waiting for protocol messages to prevent a full stderr pipe.
    $stderrTask = $process.StandardError.ReadToEndAsync()

    # Identify the widget and enable the account API capabilities.
    $initialize = @{
        id = 1
        method = 'initialize'
        params = @{
            clientInfo = @{
                name = 'codex-usage-widget'
                title = 'AI Usage Widget'
                version = '2.4.1'
            }
            capabilities = @{
                experimentalApi = $true
                requestAttestation = $false
            }
        }
    } | ConvertTo-Json -Compress -Depth 8

    # Send initialization and wait for the service to respond.
    $process.StandardInput.WriteLine($initialize)
    $process.StandardInput.Flush()
    $initialized = $false
    # Match initialization by request ID, allowing unrelated service notifications first.
    for ($index = 0; $index -lt 30; $index++) {
        $initializeResponse = Read-LineWithTimeout -Reader $process.StandardOutput
        if (-not $initializeResponse) { break }
        $initialMessage = $initializeResponse | ConvertFrom-Json
        if ($initialMessage.id -ne 1) { continue }
        # Surface protocol errors before attempting the account request.
        if ($initialMessage.error) { throw ([string]$initialMessage.error.message) }
        $initialized = $true
        break
    }
    if (-not $initialized) { throw 'Codex usage service did not complete initialization.' }

    # Request current account limits without consuming a rate-limit reset.
    $process.StandardInput.WriteLine('{"method":"initialized"}')
    $process.StandardInput.WriteLine('{"id":2,"method":"account/rateLimits/read","params":{"excludeResetCreditDetails":true}}')
    $process.StandardInput.Flush()

    # Skip unrelated notifications until the requested response arrives.
    $response = $null
    for ($index = 0; $index -lt 30; $index++) {
        $line = Read-LineWithTimeout -Reader $process.StandardOutput
        if (-not $line) { break }
        # Match the reply to the usage request's ID.
        $message = $line | ConvertFrom-Json
        if ($message.id -eq 2) {
            $response = $message
            break
        }
    }

    # Surface missing responses and service errors to the widget.
    if (-not $response) {
        throw 'Codex did not return usage information.'
    }
    if ($response.error) {
        throw [string] $response.error.message
    }

    # Prefer the Codex quota bucket, falling back to the legacy response format.
    $snapshot = $response.result.rateLimitsByLimitId.codex
    if (-not $snapshot) {
        $snapshot = $response.result.rateLimits
    }
    if (-not $snapshot) {
        throw 'No Codex usage window is available for this account.'
    }

    # Preserve server usage values; the display converts them to percentages left.
    [ordered]@{
        fetchedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        planType = $snapshot.planType
        ordinaryUsageAllowed = [bool] $response.result.ordinaryUsageAllowed
        # Preserve credit availability and the reported balance, including null values.
        credits = $snapshot.credits
        primary = if ($snapshot.primary) {
            [ordered]@{
                # Preserve unknown percentages so the UI cannot mistake them for full quota.
                usedPercent = if ($null -ne $snapshot.primary.usedPercent) { [double] $snapshot.primary.usedPercent } else { $null }
                windowDurationMins = [int] $snapshot.primary.windowDurationMins
                resetsAt = [long] $snapshot.primary.resetsAt
            }
        } else { $null }
        secondary = if ($snapshot.secondary) {
            [ordered]@{
                # Preserve unknown percentages independently for the weekly window.
                usedPercent = if ($null -ne $snapshot.secondary.usedPercent) { [double] $snapshot.secondary.usedPercent } else { $null }
                windowDurationMins = [int] $snapshot.secondary.windowDurationMins
                resetsAt = [long] $snapshot.secondary.resetsAt
            }
        } else { $null }
    } | ConvertTo-Json -Compress -Depth 5
}
catch {
    # Emit structured errors so refresh failures can be displayed in the widget.
    [ordered]@{
        error = $_.Exception.Message
        fetchedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    } | ConvertTo-Json -Compress
    exit 1
}
finally {
    # Stop and dispose only the service process created by this reader.
    if ($process) {
        if ($processStarted -and -not $process.HasExited) {
            $process.Kill($true)
        }
        $process.Dispose()
    }
}







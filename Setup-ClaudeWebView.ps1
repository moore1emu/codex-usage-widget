param([Parameter(Mandatory)][string]$Destination)
$ErrorActionPreference = 'Stop'
# Download only Microsoft's pinned browser SDK; the installed Edge WebView2 runtime is shared.
$version = '1.0.3800.47'
$target = Join-Path $Destination $version
if (Test-Path -LiteralPath (Join-Path $target 'lib/net462/Microsoft.Web.WebView2.Wpf.dll')) { exit 0 }
# Extract into a unique staging folder so an interrupted download is never treated as installed.
$stage = Join-Path $Destination ([guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $stage -Force)
try {
    $archive = Join-Path $stage 'sdk.zip'
    Invoke-WebRequest -Uri "https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/$version/microsoft.web.webview2.$version.nupkg" -OutFile $archive -TimeoutSec 45
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $stage 'package')
    # Check the signed managed assemblies before loading downloaded executable code.
    foreach ($name in @('Core','Wpf')) {
        $assembly = Join-Path $stage "package/lib/net462/Microsoft.Web.WebView2.$name.dll"
        $signature = Get-AuthenticodeSignature -LiteralPath $assembly
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') { throw 'Microsoft WebView2 SDK signature validation failed.' }
    }
    # Verify the native loader too; it executes before the managed browser environment starts.
    foreach ($architecture in @('x86','x64','arm64')) {
        $loader=Join-Path $stage "package/runtimes/win-$architecture/native/WebView2Loader.dll"
        $signature=Get-AuthenticodeSignature -LiteralPath $loader
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {throw 'Microsoft WebView2 loader signature validation failed.'}
    }
    # Publish the complete package, including its Microsoft license, after validation succeeds.
    if (-not (Test-Path -LiteralPath $target)) { Move-Item -LiteralPath (Join-Path $stage 'package') -Destination $target }
} finally {
    # Remove only this setup attempt's staging directory inside the explicit destination.
    $root = [IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
    if ([IO.Path]::GetFullPath($stage).StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

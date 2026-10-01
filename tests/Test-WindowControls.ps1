# Exercise actual pointer targets and settings persistence without touching a running widget.
$InitialTestState = @{ left=100000;top=100000;width=190;height=210;refreshIntervalMinutes=0;sharedEnabled=$false;readUsageEnabled=$false;topmost=$false }
. (Join-Path $PSScriptRoot 'Initialize-TestWidget.ps1')
function Assert-PointerTarget {
    param($Target,$Control)
    # Hit-test the control's center and walk ancestors to detect overlays that intercept clicks.
    $point = $Control.TranslatePoint([Windows.Point]::new($Control.ActualWidth/2,$Control.ActualHeight/2),$Target)
    $hit = $Target.InputHitTest($point)
    while ($hit -is [Windows.Media.Visual]) {
        if ([object]::ReferenceEquals($hit,$Control)) { return }
        $hit = [Windows.Media.VisualTreeHelper]::GetParent($hit)
    }
    throw ('Pointer cannot reach ' + $Control.Name + ' in ' + $script:AccountLayout)
}
try {
    # Simulate a saved location beyond every current monitor and verify startup recovery.
    $screenRight = [Windows.SystemParameters]::VirtualScreenLeft + [Windows.SystemParameters]::VirtualScreenWidth
    $screenBottom = [Windows.SystemParameters]::VirtualScreenTop + [Windows.SystemParameters]::VirtualScreenHeight
    if ($window.Left -lt [Windows.SystemParameters]::VirtualScreenLeft -or $window.Top -lt [Windows.SystemParameters]::VirtualScreenTop -or $window.Left+$window.Width -gt $screenRight -or $window.Top+$window.Height -gt $screenBottom) { throw 'Startup left the widget outside the connected desktop.' }
    $window.Show(); $window.UpdateLayout()
    # Check full and compact controls in every layout, including both detached account shells.
    foreach ($mode in @('Single','Account picker','Side by side','Stacked','Separate windows')) {
        $script:SharedEnabled = $mode -ne 'Single'; $script:ReadUsageEnabled=$script:SharedEnabled
        $script:AccountLayout=$mode; Update-Display
        foreach ($size in @(@(280,290),@(150,90),@(72,72))) {
            $window.Width=$size[0]; $window.Height=$size[1]; $window.UpdateLayout(); Update-Display
            Update-HoverControls -IsPointerOver $true; $window.UpdateLayout()
            foreach ($control in @($refreshButton,$pinButton,$minimizeButton,$closeButton,$compactRefreshButton,$hoverRefreshButton,$hoverPinButton,$hoverMinimizeButton,$hoverCloseButton,$leftResizeGrip,$rightResizeGrip)) {
                if ($control.IsVisible) { Assert-PointerTarget $window $control }
            }
            if ($mode -eq 'Separate windows') {
                # The shared shell must expose its own controls above the imported account card.
                $peer=$script:SeparateView.Window; $peer.Width=$size[0]; $peer.Height=$size[1]
                $peer.UpdateLayout(); Update-SeparateWindow
                Invoke-SeparateWindowAction { Update-HoverControls -IsPointerOver $true }; $peer.UpdateLayout()
                foreach ($key in @('refreshButton','pinButton','minimizeButton','closeButton','compactRefreshButton','hoverRefreshButton','hoverPinButton','hoverMinimizeButton','hoverCloseButton','leftResizeGrip','rightResizeGrip')) {
                    $control=$script:SeparateView.Bindings[$key]
                    if ($control.IsVisible) { Assert-PointerTarget $peer $control }
                }
            }
        }
    }
    # Count real settings writes while retaining the production serializer and saved geometry.
    $script:ActualSaveFunction=${function:Save-WidgetState}
    $script:TestSaveCount=0
    function Save-WidgetState { $script:TestSaveCount++; & $script:ActualSaveFunction }
    $script:SeparateBoundsSaveTimer.Stop()
    $peer.Width=190; $peer.Height=210; $peer.UpdateLayout(); $script:SeparateBoundsSaveTimer.Stop()
    # Simulate hovering again after the size change has refreshed the shell's visibility.
    Invoke-SeparateWindowAction { Update-HoverControls -IsPointerOver $true }; $peer.UpdateLayout()
    $script:TestSaveCount=0
    $grip=$script:SeparateView.Bindings.leftResizeGrip
    # Each synthetic drag tick uses the actual reachable control and forces its layout update.
    Assert-PointerTarget $peer $grip
    for ($index=0;$index -lt 10;$index++) {
        $grip.RaiseEvent([Windows.Controls.Primitives.DragDeltaEventArgs]::new(-2,2))
        $peer.UpdateLayout()
    }
    if ($script:TestSaveCount -ne 0) { throw 'Resize ticks wrote intermediate settings.' }
    $grip.RaiseEvent([Windows.Controls.Primitives.DragCompletedEventArgs]::new(-20,20,$false))
    Wait-TestDispatcher 450
    if ($script:TestSaveCount -ne 1) { throw 'Resize release did not save exactly once.' }
    $saved=Get-Content -LiteralPath $script:StatePath -Raw | ConvertFrom-Json
    if ($saved.separateRemoteBounds.width -ne $peer.Width -or $saved.separateRemoteBounds.height -ne $peer.Height) { throw 'Resize release lost the final shared-window dimensions.' }
    # Native or programmatic geometry events also coalesce, and the idle timer stops after saving.
    $script:TestSaveCount=0
    for ($index=0;$index -lt 10;$index++) { $peer.Left+=1; $peer.Width+=1; $peer.UpdateLayout() }
    if ($script:TestSaveCount -ne 0) { throw 'Geometry changes saved before becoming idle.' }
    Wait-TestDispatcher 450
    if ($script:TestSaveCount -ne 1 -or $script:SeparateBoundsSaveTimer.IsEnabled) { throw 'Geometry changes did not coalesce into one save.' }
    Write-Output 'PASS: actual button/grip targets, offscreen startup recovery, one save on resize release, and debounced geometry persistence.'
} finally {
    # Restore the original writer before normal shutdown so test instrumentation cannot affect cleanup.
    if ($script:ActualSaveFunction) { Set-Item Function:Save-WidgetState $script:ActualSaveFunction }
    Close-TestWidget
}

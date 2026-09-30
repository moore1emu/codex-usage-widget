# Codex Usage Widget

**Current version: 1.7.2** · Released September 30, 2026.

Check the version at the top of the tray menu or by hovering over the widget title. The compact badge's tooltip and the Windows window title also include it. For future releases, update `WidgetVersion` in `CodexUsageWidget.ps1`, the reader's client version, this version line, and the changelog together.

A compact Windows desktop widget for the Codex 5-hour and weekly usage windows.

All percentages and bars show usage left: 100% means the full quota remains, and 0% means the quota is exhausted.

The window and desktop shortcut use a square blue/purple/muted-green icon. The notification-area icon has two live remaining-usage bars, a credit-color identity accent, and a thin light outline that remains visible when quota is empty. The green accent is not a credit-usage bar.

## Screenshots

These views were rendered from version 1.7.2 using live usage values captured on September 30, 2026. Values are a snapshot, not a live display. Images show the widget content without the surrounding desktop or Windows resize grip.

| Mini | Small | Medium | Large / Default |
| --- | --- | --- | --- |
| <img src="docs/screenshots/widget-mini.png" alt="Mini widget with numeric usage and credits" width="72"> | <img src="docs/screenshots/widget-small.png" alt="Small widget with labels and reset countdowns" width="140"> | <img src="docs/screenshots/widget-medium.png" alt="Medium widget with usage bars, plan, and credits" width="190"> | <img src="docs/screenshots/widget-large.png" alt="Large widget with full details" width="280"> |

The notification settings panel provides separate quota-warning thresholds and an optional 5-hour reset notification. The screenshot shows the preferences used at capture time; default thresholds are 0 (off) and the reset notification is off.

![Notification settings](docs/screenshots/notification-settings.png)

## Requirements

- **Windows with PowerShell 7 installed on each computer.** Built-in Windows PowerShell 5.1 alone is not sufficient; this version does not provide a 5.1 fallback.
- **Codex installed and signed in locally**, with its native `codex.exe` available to the usage reader.
- Keep all widget files together and let OneDrive finish syncing before launching on another computer. Syncing the widget folder does not install PowerShell 7 or Codex.

## Run it

Double-click `Start-CodexUsageWidget.cmd`.

If this folder's widget is already running in your Windows session, a manual launch offers **Restart widget** or **Cancel**. Restart closes the old instance normally so settings are saved before loading the current version. If it cannot close within 10 seconds, the launcher asks you to close it yourself; it never force-kills the widget. Simultaneous shortcut clicks are coordinated to avoid competing launches. Launch through the CMD file or desktop shortcut; directly running the main script bypasses this check.

Enable **Launch at Windows sign-in** in the tray menu to start the desktop widget when you sign in. The setting uses a per-user Startup shortcut and is independent on each computer. Turn it off in the same menu to remove that shortcut. Automatic startup quietly leaves an existing instance running. Keep the widget folder in place and available locally at sign-in. Closing the Codex desktop app does not stop the widget: the widget uses its own short-lived usage-reader process and the locally installed Codex executable and saved sign-in.

For a shortcut with the three-color icon, double-click **Create-DesktopShortcut.cmd** after placing the widget folder in its permanent location. It creates a local desktop shortcut using that computer's paths. Include both `Create-DesktopShortcut.cmd` and `Create-DesktopShortcut.ps1` when sharing the widget files. Each recipient runs the helper once; the generated `.lnk` is local and does not need to sync through OneDrive. Alternatively, `Start-CodexUsageWidget.cmd` already launches portably from the folder beside it. Creating a shortcut does not install PowerShell 7 or Codex, enable Windows startup, or launch the widget.

Keep `Start-CodexUsageWidget.ps1` beside the CMD launcher. The launcher uses built-in Windows PowerShell to find PowerShell 7 through PATH, common installation folders, or its Microsoft Store registration, then starts the widget hidden.

The usage reader finds `codex.exe` through PATH or the local `%LOCALAPPDATA%\OpenAI\Codex\bin` installation, including versioned subfolders. You do not need to launch the widget from inside Codex.

If startup reports a missing dependency, install and open Codex and install PowerShell 7 on that computer. For custom installation locations, add the directory containing the missing executable to PATH. A successful launch from inside Codex does not guarantee that Explorer has the same PATH. Wait for all widget files to finish syncing before launching on another computer.

The widget uses the local Codex installation and your existing Codex sign-in. It does not store or display credentials. Usage refreshes every five minutes by default, while reset countdowns update every second when the desktop window is visible. Hiding to the tray pauses countdown rendering, but usage refreshes and alerts continue.

## Controls

The widget stays visible on the desktop without an active taskbar button. Its system-tray icon near the clock provides its menu and restore controls. Windows may place that icon in the tray's overflow area.

- Drag the header or compact background to move the widget. Dragging to a screen edge preserves its size without invoking Windows Snap. Other applications' Snap settings are unchanged.
- Choose **Position → Top left / Top right / Bottom left / Bottom right** in the tray menu to move to a corner of the widget's current monitor, slightly inside the usable area and clear of the taskbar. This restores a hidden widget and saves its position immediately without resizing it. Oversized windows keep their top-left reachable.
- Drag any edge or corner to resize it. The compact badge shows the blue 5-hour percentage above the purple weekly percentage, with a reset countdown beneath each. Countdown labels are the last details to disappear as you shrink it; at the smallest 72×58 size only the percentages and enabled credit count remain. Hover over a percentage for its full reset information. Double-click that compact view to return to the normal size.
- Click `↻` to refresh immediately.
- Click `◉` / `○` to turn always-on-top on or off.
- Click `—` to minimize it to the notification area next to the clock. The tray icon has a blue 5-hour bar and a purple weekly bar; hover for the exact percentages and double-click to restore the widget.
- Click `×` to close it.
- If the normal controls are hidden, hover over the widget to reveal **Refresh**, **Always on top**, **Minimize to tray**, and **×** at the top right. The smallest sizes use two rows so all four buttons fit; they temporarily overlay the readouts. An already-visible compact refresh button moves into this group instead of creating a duplicate. Moving the pointer away restores the normal display. Closing this way saves settings just like the normal close button.
- Right-click the tray icon and choose **Refresh interval** to select 1, 5, 15, or 30 minutes, or manual-only refresh. Five minutes is the default.
- Right-click the tray icon and choose **Colors**, then **5-hour color...**, **Weekly color...**, or **Credits color...** to choose each readout's color independently. Quota colors also update their bars and app/tray icons. Credit labels remain white while the numeric balance uses its selected color. **Reset to default colors** restores blue, purple, and muted blue-green. Colors are saved when the widget exits and restored on the next launch. The desktop shortcut keeps its blue/purple/muted-green identity icon.

Its last screen position, size, and always-on-top choice are stored per computer in `%LOCALAPPDATA%\CodexUsageWidget\widget-state.json`.

## Credits and notifications

Reset countdowns sit directly beneath their usage bars. Percentages and credit totals share a value column and align by their first digit. The header title, status dot, and window buttons share one aligned row.

- **Credit display → When credits exist** is the default: positive or unlimited credits appear even when subscription quota remains. Choose **Always show** to keep the readout visible for zero or unavailable balances, or **Off** to hide it. Balances are rounded to whole credits for display; the account balance itself is unchanged. The Credits row uses the same white-label/colored-value alignment as the quota rows. The default credit color is muted blue-green. Unknown balances use a dash and unlimited balances use ∞ in the smallest view. These are usage credits, not free quota-reset grants.
- Resizing measures the readouts and available space. It removes header/footer details first, then bars, while retaining labeled values and reset countdowns. Only when labeled rows no longer fit does it switch to the numeric badge. With credits visible, that badge keeps three numeric readouts and removes captions and countdowns as necessary to fit. Numeric font sizes also adapt to the minimum window size. Drag the background to move the intermediate layout.
- **Notifications...** opens separate 5-hour and weekly percentage thresholds. Both default to **0 (off)**. A threshold of 20 warns when the remaining percentage is below 20, including zero. Checks run after successful usage refreshes, so the refresh interval controls warning latency. An already-low quota warns on the first successful check unless its saved notification state says that warning was already sent; relaunching does not repeat it.
- Enable **Notify when the 5-hour window resets** for a one-time notification after a successful refresh confirms quota has recovered following the observed reset time. This defaults to off and works even when low-usage thresholds are 0. The first observation establishes a baseline without notifying. Reset state is saved to avoid repeats after restarting; enabling the option starts fresh. Notifications follow your refresh interval (manual-only requires Refresh), continue while minimized to the tray, and may be suppressed by Windows notification settings. The notification includes the remaining percentage and only appears when the same refresh confirms weekly quota above 0%. Exhausted or unavailable weekly quota suppresses that reset notice.
- A warning is not repeated while quota stays below its threshold, even if the server changes its reset timestamp or the widget restarts. It rearms after quota recovers to the threshold or above. Disabling a threshold clears its warning state. Sent warnings are saved locally in `warning-state.json`. Windows notification settings and Do Not Disturb can suppress the popup. The widget must remain running to check usage.
- Notification preferences are saved immediately when you click Save. Colors and the credit-display preference are also saved with the existing settings when the widget exits normally.

## Window sizes and manual refresh

The tray/settings controls follow Windows' app light/dark preference using native Windows Forms theming when supported by the installed PowerShell runtime. Restart the widget after changing the Windows theme. Older runtimes retain their standard Windows control styling. The widget itself retains its dark background and custom readout colors.

Choose **Window size** in the tray menu for four distinct display sizes:

| Preset | Size | Display |
| --- | --- | --- |
| Mini | 72 × 72 | Numeric badge |
| Small | 140 × 155 | Labeled values and reset countdowns |
| Medium | 190 × 210 | Usage bars, compact header controls, and plan line, including with credits |
| Large / Default | 280 × 240 | Full details, plan line, and footer |

Dimensions are Windows logical pixels. Large and Default are now one preset. Presets save immediately and restore when reopening; manually resized dimensions still save on normal exit. Existing saved sizes remain unchanged until you choose a preset. Double-clicking the compact badge returns to the new Large / Default size. Width transitions measure the text and controls, using the center gap before shortening labels or hiding details.

When the full header no longer fits, a small refresh button remains at the top right until even the numeric readouts leave insufficient room. Tray-menu **Refresh** remains available at every size. Refresh interval changes save immediately; choosing one minute sets a 60-second usage timer.

## Using it on multiple computers

The same OneDrive folder can be used from multiple Windows computers at the same time. Each computer needs Codex and PowerShell 7 installed and must be signed in to Codex locally. Credentials and Codex caches remain local to each computer; only these widget scripts sync through OneDrive.

## Refresh and startup errors

A failed refresh retains the last known numbers and adds an amber border. Hover over the widget or its readouts for the error; the tray tooltip also marks readings as potentially stale. A request times out after 45 seconds. Retry with Refresh or wait for the selected interval. A successful response restores normal styling. Missing percentages display as unavailable, never as 100% remaining.

Hidden startup failures show a popup and, when writable, save diagnostic details to `%LOCALAPPDATA%\CodexUsageWidget\startup-error.log`. This log contains the most recent unhandled error rather than an ongoing usage history.

## Sharing and privacy

Publish only this `CodexUsageWidget` folder. The supplied scripts and icon contain no hardcoded personal names, computer paths, account identifiers, or credentials. Executable locations, Windows user identity, and local folders are resolved on the computer running the widget. The reader requests quota data through the local Codex installation and returns usage windows, plan information, and credits; it does not export sign-in credentials.

Settings, notification state, and startup-error diagnostics are stored in `%LOCALAPPDATA%\CodexUsageWidget`, outside this project. Generated desktop and Startup shortcuts contain local paths. The included `.gitignore` excludes shortcuts, logs, local state, credential files, and common scratch folders. Do not copy Codex authentication files, caches, raw usage responses, or diagnostics into a public repository. Review any additional files before sharing them; error logs can include local paths.

## Changelog

### 1.7.2 — September 30, 2026

- Replaced the organization-specific Windows app identity with a generic widget identity.
- Added images of all four window presets and the notification settings panel using actual usage values.
- Moved the complete changelog to the bottom of the README and removed machine-specific shortcut wording.
- Added sharing/privacy guidance and Git exclusions for generated shortcuts, logs, local state, credentials, and scratch files.

### 1.7.1 — September 29, 2026

- Suppressed 5-hour reset notifications when weekly quota is exhausted or unavailable. A fresh response must confirm weekly quota above 0%; a suppressed reset is not sent later as a stale notice.

### 1.7.0 — September 29, 2026

- Added an optional 5-hour reset notification under **Notifications...**, with persistent duplicate suppression and an independent checkbox.
- Require a successful quota-recovery observation after the reset deadline; changing reset timestamps alone cannot trigger a notification. Simultaneous low-quota and reset notices share one popup.
- Save notification preferences immediately when the settings dialog is saved.

### 1.6.2 — September 29, 2026

- Increased Medium from 190 × 200 to 190 × 210 so the plan line fits with the credits row present. Width and font sizes are unchanged. After restarting, select Window size → Medium to apply the new preset; saved custom sizes are preserved.

### 1.6.1 — September 29, 2026

- Added portable desktop-shortcut creation helpers. Each recipient can generate a three-color shortcut pointing to their own widget folder, without syncing machine-specific shortcuts.

### 1.6.0 — September 29, 2026

- Added Restart widget / Cancel when launching an already-running copy from the same folder. Restart uses a normal close, including when hidden in the tray, and preserves saved settings.
- Coordinated concurrent launcher clicks and added `-IfNotRunning` for automatic startup without restart prompts.
- Added **Launch at Windows sign-in**, managed through a per-user Startup shortcut with no background watcher or dependency on the Codex desktop window staying open.

### 1.5.1 — September 29, 2026

- Reduced corner placement from a 12- to a 2-logical-pixel inset for a near-edge position while respecting the taskbar and display scaling.

### 1.5.0 — September 29, 2026

- Prevented drag-to-edge Windows Snap by moving the widget directly while tracking the pointer.
- Added four saved corner positions using the current monitor's work area and a small display-scaled inset.
- Changed **When credits exist** to require a positive numeric balance or unlimited credits; missing/unavailable balances stay hidden. **Always show** still allows an unavailable placeholder.
- Removed the credit-count entry from the tray/settings menu; the credit-display and color choices remain available.

### 1.4.3 — September 29, 2026

- Added hover Minimize to tray and Always on top alongside Refresh and Close when the header controls are hidden.
- Arranged the hover controls in two rows at the smallest widths; kept the pin state synchronized and avoided duplicate refresh buttons.

### 1.4.2 — September 29, 2026

- Paused per-second countdown/layout updates while the desktop window is hidden, refreshing them immediately when restored. Scheduled usage refreshes, tray updates, and low-usage alerts continue normally.
- Limited the refresh-completion timer to active requests; it stops after success, errors, or timeout instead of waking four times per second while idle.

### 1.4.1 — September 29, 2026

- Fixed minimizing to the tray ending the widget process. The event loop now remains active while the desktop window is hidden, preserving the tray icon, refreshes, and alerts. Close and tray-menu Exit still quit completely.

### 1.4.0 — September 29, 2026

- Kept the desktop widget visible without an active taskbar button, including after restoring from the tray.
- Added a 45-second overall refresh timeout and asynchronous output draining so failed requests do not block future refreshes.
- Added an amber border and error tooltips at every size when displayed data may be stale; successful refreshes clear the indicator.
- Preserved unknown percentages and fixed unlimited credits in mini mode.
- Validated saved notification structures and service initialization replies.
- Added hidden-startup error popups and local `startup-error.log` diagnostics; the launcher checks both required scripts.
- Removed unused `CodexUsage.ico`, `CodexUsage-Color.ico`, and the legacy folder-level `widget-state.json`. Active settings remain in local AppData. If another computer's shortcut references an old icon filename, point it to `CodexUsage-Tricolor.ico`.

### 1.3.0 — September 29, 2026

- Updated the desktop and running-app icons to include blue, purple, and muted green.
- Added a light outline and credit-color accent to keep the tray icon visible at zero usage.
- Enabled native system light/dark styling for settings controls on supported runtimes.
- Added hover refresh alongside hover close whenever refresh is otherwise hidden.

### 1.2.2 — September 29, 2026

- Muted the default credit green from `#8BCBB8` to `#91B8B0`, retaining blue `#669CFF` and purple `#A97BFF`.
- Existing settings using the old default migrate automatically; other custom credit colors are preserved.
- Palette reference: [ColorHexa blue-green chart](https://www.colorhexa.com/91b8b0).

### 1.2.1 — September 29, 2026

- Matched the white 5-hour, Weekly, and Credits labels to their numeric values' font sizes, retaining regular-weight labels and bold values.
- Resizing measures the larger labels before choosing a layout. Credits remain numeric, without a bar.
- Confirmed the “Drag · resize” footer hint remains removed.

### 1.2.0 — September 29, 2026

- Replaced oversized presets with Mini, Small, Medium, and a combined narrower Large / Default.
- Removed fixed width cutoffs for title, plan, footer, and reset text; details remain while they fit.
- Reduced full-view padding and preserved the center gap as usable resizing space.
- Removed the redundant “Drag · resize” footer hint.

### 1.1.0 — September 29, 2026

- Added visible version information and this release history.
- Added a hover-to-close button for layouts without the normal header controls.
- Retains the existing size presets, persistent warning suppression, credit controls, and responsive layout from the previously unversioned build.

### Earlier builds — unversioned

- Introduced usage-left percentages, reset countdowns, credit display, custom colors, warning thresholds, desktop launcher, and responsive sizing.

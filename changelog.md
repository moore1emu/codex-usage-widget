# Changelog

[Back to README](README.md)

## Documentation update — September 30, 2026

- Simplified the README to quick setup, essential controls, and screenshots.
- Moved the complete release history to `changelog.md` and the detailed guide to `extradetails.md`.
- Added the full settings-menu screenshot alongside the notification panel and a review-before-use/non-endorsement disclaimer. Widget behavior and version remain unchanged.

## 1.7.2 — September 30, 2026

- Replaced the organization-specific Windows app identity with a generic widget identity.
- Added images of all four window presets and the notification settings panel using actual usage values.
- Moved the complete changelog to the bottom of the README and removed machine-specific shortcut wording.
- Added sharing/privacy guidance and Git exclusions for generated shortcuts, logs, local state, credentials, and scratch files.

## 1.7.1 — September 29, 2026

- Suppressed 5-hour reset notifications when weekly quota is exhausted or unavailable. A fresh response must confirm weekly quota above 0%; a suppressed reset is not sent later as a stale notice.

## 1.7.0 — September 29, 2026

- Added an optional 5-hour reset notification under **Notifications...**, with persistent duplicate suppression and an independent checkbox.
- Require a successful quota-recovery observation after the reset deadline; changing reset timestamps alone cannot trigger a notification. Simultaneous low-quota and reset notices share one popup.
- Save notification preferences immediately when the settings dialog is saved.

## 1.6.2 — September 29, 2026

- Increased Medium from 190 × 200 to 190 × 210 so the plan line fits with the credits row present. Width and font sizes are unchanged. After restarting, select Window size → Medium to apply the new preset; saved custom sizes are preserved.

## 1.6.1 — September 29, 2026

- Added portable desktop-shortcut creation helpers. Each recipient can generate a three-color shortcut pointing to their own widget folder, without syncing machine-specific shortcuts.

## 1.6.0 — September 29, 2026

- Added Restart widget / Cancel when launching an already-running copy from the same folder. Restart uses a normal close, including when hidden in the tray, and preserves saved settings.
- Coordinated concurrent launcher clicks and added `-IfNotRunning` for automatic startup without restart prompts.
- Added **Launch at Windows sign-in**, managed through a per-user Startup shortcut with no background watcher or dependency on the Codex desktop window staying open.

## 1.5.1 — September 29, 2026

- Reduced corner placement from a 12- to a 2-logical-pixel inset for a near-edge position while respecting the taskbar and display scaling.

## 1.5.0 — September 29, 2026

- Prevented drag-to-edge Windows Snap by moving the widget directly while tracking the pointer.
- Added four saved corner positions using the current monitor's work area and a small display-scaled inset.
- Changed **When credits exist** to require a positive numeric balance or unlimited credits; missing/unavailable balances stay hidden. **Always show** still allows an unavailable placeholder.
- Removed the credit-count entry from the tray/settings menu; the credit-display and color choices remain available.

## 1.4.3 — September 29, 2026

- Added hover Minimize to tray and Always on top alongside Refresh and Close when the header controls are hidden.
- Arranged the hover controls in two rows at the smallest widths; kept the pin state synchronized and avoided duplicate refresh buttons.

## 1.4.2 — September 29, 2026

- Paused per-second countdown/layout updates while the desktop window is hidden, refreshing them immediately when restored. Scheduled usage refreshes, tray updates, and low-usage alerts continue normally.
- Limited the refresh-completion timer to active requests; it stops after success, errors, or timeout instead of waking four times per second while idle.

## 1.4.1 — September 29, 2026

- Fixed minimizing to the tray ending the widget process. The event loop now remains active while the desktop window is hidden, preserving the tray icon, refreshes, and alerts. Close and tray-menu Exit still quit completely.

## 1.4.0 — September 29, 2026

- Kept the desktop widget visible without an active taskbar button, including after restoring from the tray.
- Added a 45-second overall refresh timeout and asynchronous output draining so failed requests do not block future refreshes.
- Added an amber border and error tooltips at every size when displayed data may be stale; successful refreshes clear the indicator.
- Preserved unknown percentages and fixed unlimited credits in mini mode.
- Validated saved notification structures and service initialization replies.
- Added hidden-startup error popups and local `startup-error.log` diagnostics; the launcher checks both required scripts.
- Removed unused `CodexUsage.ico`, `CodexUsage-Color.ico`, and the legacy folder-level `widget-state.json`. Active settings remain in local AppData. If another computer's shortcut references an old icon filename, point it to `CodexUsage-Tricolor.ico`.

## 1.3.0 — September 29, 2026

- Updated the desktop and running-app icons to include blue, purple, and muted green.
- Added a light outline and credit-color accent to keep the tray icon visible at zero usage.
- Enabled native system light/dark styling for settings controls on supported runtimes.
- Added hover refresh alongside hover close whenever refresh is otherwise hidden.

## 1.2.2 — September 29, 2026

- Muted the default credit green from `#8BCBB8` to `#91B8B0`, retaining blue `#669CFF` and purple `#A97BFF`.
- Existing settings using the old default migrate automatically; other custom credit colors are preserved.
- Palette reference: [ColorHexa blue-green chart](https://www.colorhexa.com/91b8b0).

## 1.2.1 — September 29, 2026

- Matched the white 5-hour, Weekly, and Credits labels to their numeric values' font sizes, retaining regular-weight labels and bold values.
- Resizing measures the larger labels before choosing a layout. Credits remain numeric, without a bar.
- Confirmed the “Drag · resize” footer hint remains removed.

## 1.2.0 — September 29, 2026

- Replaced oversized presets with Mini, Small, Medium, and a combined narrower Large / Default.
- Removed fixed width cutoffs for title, plan, footer, and reset text; details remain while they fit.
- Reduced full-view padding and preserved the center gap as usable resizing space.
- Removed the redundant “Drag · resize” footer hint.

## 1.1.0 — September 29, 2026

- Added visible version information and this release history.
- Added a hover-to-close button for layouts without the normal header controls.
- Retains the existing size presets, persistent warning suppression, credit controls, and responsive layout from the previously unversioned build.

## Earlier builds — unversioned

- Introduced usage-left percentages, reset countdowns, credit display, custom colors, warning thresholds, desktop launcher, and responsive sizing.

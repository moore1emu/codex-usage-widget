# Changelog

[Back to README](README.md)

## 2.1.5 — October 1, 2026

- Defer settings status/layout updates while a dropdown is open so General and Shared lists stay open and preserve draft selections. Resume nickname, connection status and lock updates after the list closes; usage refresh continues independently.
- Add a regression check for every settings dropdown across actual status timer ticks, deferred account-name updates, and Shared locking/unlocking.

## 2.1.4 — October 1, 2026

- Keep compact refresh and hover controls above account cards so they remain clickable in every shared layout and both separate windows.
- Save shared-window resize bounds on release and combine other size/location changes into one delayed settings write, reducing disk activity during movement.
- Recover saved main-window positions beyond the connected desktop at startup using the same bounds validation as separate windows.
- Include portable, isolated regression checks for pointer targets, geometry persistence, change-only sharing, and shortcut shutdown. Tests use temporary preferences and example readings without accessing live account data.

## 2.1.3 — October 1, 2026

- Keep both hover resize handles above dynamically added account cards so clicks reach the handles in combined and separate windows. Validate actual hit targets and resizing at full and compact sizes.

## 2.1.2 — October 1, 2026

- Give shortcut restart a dedicated full-application shutdown request. Save both account windows and close the shared window and Settings, including when either account is hidden to the tray.
- Preserve per-account close/minimize behavior and the startup leave-running option. Never force-kill an unresponsive or older widget; show one-time tray Exit instructions for older versions.

## 2.1.1 — October 1, 2026

- Skip unchanged JSON exports, including new fetch timestamps and restart; publish meaningful changes and automatic 30-minute check-ins. Preserve manual-only behavior, output ownership, and original reading age.
- Separate last usage change from last checked; cache unchanged imported files and allow the longer check-in cadence for stale display while keeping notification freshness strict.
- Show resize handles at both bottom corners only on hover for local and separate shared windows.
- Match every Settings dropdown to the panel's system dark/light colors.

## 2.1.0 — October 1, 2026

- Keep Settings open while interacting with either widget; preserve Apply, Save, and Cancel behavior.
- Use account display names in both pickers and match the inline dropdown to the widget's dark theme.
- Add Separate windows alongside existing layouts, with independent movement, resizing, saved geometry, always-on-top, hide/reopen actions, and shared-window tray size presets. Tray Exit closes both.
- Keep compact account headings visible longer with smaller text and ellipsis; full names remain available on hover.

## 2.0.3 — October 1, 2026

- Move settings explanations to hover tooltips on their related controls and labels in General and Shared, reducing visual clutter while retaining live sharing status.
- Rename default other-computer labels to Shared computer, preserving custom source names.
- Keep help on numeric editors and release the tooltip component when Settings closes. Refresh documentation and settings screenshots.

## 2.0.2 — October 1, 2026

- Use the full local hostname for OneDrive desktop shortcuts and retire owned shortcuts using the shortened Windows name.
- Hide permanent compact refresh before reset countdowns; keep refresh available on hover and in the tray menu.
- Add Apply to settings so changes can be saved and previewed without closing the dialog. Cancel preserves applied changes and discards later drafts.
- Consolidate settings into General and Shared, with independent colors, credit visibility, reset displays and notifications. Enable Shared locks/unlocks its settings; disabling preserves its preferences while stopping file operations, second-account display and alerts.
- Add fresh-only shared notifications with account labels, separate persisted duplicate suppression and the same weekly gating for reset alerts.
- Rename the palette to Fuchsia / mauve / mist and migrate saved selections of its previous label. Update documentation and settings screenshots.

## 2.0.1 — October 1, 2026

- Add the computer name to desktop shortcuts created inside OneDrive destinations, preventing different computers from overwriting the same synced shortcut. Local destinations retain the plain Codex Usage name.
- Detect registered OneDrive roots and custom locations, preserve unrelated shortcuts, and replace an owned generic shortcut with the new computer-specific name.

## 2.0.0 — October 1, 2026

- Reorganized settings into General, Display, Sharing, and Notifications tabs with native system light/dark styling.
- Added opt-in private JSON publishing and reading for another computer's Codex account. Each direction can match widget refresh, use an independent timer, or refresh manually. Separate file-operation status and source age make stale readings visible.
- Added Side by side, Stacked, and Account picker layouts with per-layout sizes. Side by side retains both numeric columns and its divider at Mini size; account data is never combined.
- Added six coordinated color palettes, with separate local and remote choices, replacing individual color pickers.
- Validate shared snapshots, preserve the last good reading during missing/partial/older sync copies, and refuse to overwrite another source's JSON. Shared files contain usage data and a random source identifier, never authentication credentials.
- Kept tray readings and notifications tied to the local account. Hide the tray credit accent when credit display is Off or the balance is zero/unavailable, and include available credits in the tray tooltip.
- Updated documentation and screenshots. Existing window bounds, refresh and notification preferences remain; older custom colors migrate to the blue/purple/sage preset.

## 1.8.0 — October 1, 2026

- Added **Reset display...** with independently saved 5-hour hours-ahead (default 25; 0 = off; maximum 168) and weekly date (default on) settings.
- Show a simple **at 1:22 PM, 6:22 PM...** list using the reported next reset and later estimated times, recalculated on each usage refresh. Keep estimation context in hover text and settings, and handle daylight-saving changes using elapsed time.
- Show the weekly day, date, and time without repeating “Resets on.”
- Place reset times/dates beside countdowns when they fit, below them when narrow. Preserve reset details before bars; shorten to the actual next reset and then the countdown when height runs out. Full schedules remain available on hover.
- Increased Large / Default to 280 × 290. Mini, Small, Medium, and previously saved custom sizes retain their dimensions.
- Refreshed the README screenshots and retained the existing refresh intervals and notification rules.

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

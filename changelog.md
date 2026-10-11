# Changelog

[Back to README](README.md)

## 2.7.5 — October 11, 2026

- Match compact quota readings to the enabled CPU/RAM/GPU column: colored 5-hour, Weekly and Credits labels beside their values, retaining countdowns underneath while space permits. Narrow cards drop labels together; full bars and menu-height lines retain their existing layout.
- Remove decorative bullets from hardware readings.

## 2.7.4 — October 11, 2026

- Match CPU, RAM and GPU to each local account's selected 5-hour, weekly and credits palette colors, including compact and detached views. Applying another palette updates the resource colors immediately.

## 2.7.3 — October 11, 2026

- Keep enabled CPU/RAM/GPU values visible at every widget size and in every account layout, replacing the disappearing footer with a persistent column. Labels follow the 5-hour label visibility; values scale together and keep memory units and hover help. Thin views use a single line.
- Preserve equal quota widths across connected accounts and extend synthetic checks to full, narrow, mini, picker and menu-height views.

## 2.7.2 — October 11, 2026

- Extend the vertical CPU/RAM/GPU column to wide, short top-and-bottom account panels. Keep their resource and quota columns aligned; taller stacked panels restore the existing footer.

## 2.7.1 — October 11, 2026

- Keep CPU, RAM and GPU together in an extra vertical column in side-by-side and wide, short account views. The column survives shorter windows, drops labels before values, and preserves equal quota widths across connected panels. Stacked views retain the existing footer.
- Register the AI Usage Widget notification display name instead of the legacy CodexUsageWidget identity. Existing local settings and shortcut restart compatibility remain intact.

## 2.7.0 — October 11, 2026

- Add optional local Codex and Claude CPU, private RAM, and GPU readings, collected in the background every 3 seconds while visible. Each local account has its own switch; readings are never exported to shared JSON.
- Group desktop child processes while excluding the widget, its helpers, unrelated apps and recycled parent IDs. GPU shows the busiest combined engine; unavailable readings show a dash.
- Switch RAM to GB above 1,000 MB. Tighten spacing and remove CPU/RAM/GPU labels before values, retaining GPU; hide the resource row before quota details need its space. Keep connected panels aligned.

## 2.6.6 — October 11, 2026

- Keep reset details first while making usage-bar visibility stable during corner resizing. Use full wrapped reset text and a consistent header allowance for bar fitting so optional header/status changes and expanding reset schedules cannot make bars disappear and return unexpectedly.
- Keep narrow labeled rows before the numeric badge, and let longer wrapped details hide bars earlier in narrow, short views. Cover stacked/side-by-side width and height sweeps and repeated renders with regression tests.

## 2.6.5 — October 11, 2026

- Stop reserving an unused toolbar strip inside account cards when deciding whether usage bars fit. Prevent bars from disappearing in a wider stacked view and returning only after narrowing hides optional header details.

## 2.6.4 — October 11, 2026

- Keep usage bars visible at narrower widths by adding a compact labeled view with 13px labels/values and percentages without the redundant left suffix. Restore normal text and type size when widened; keep connected accounts aligned.

## 2.6.3 — October 11, 2026

- Match live tray and window icons to the desktop icon's upright blue, purple and sage bars. Preserve dynamic quota heights, the visible outline at zero usage and credit visibility rules.
- Shorten widget labels to 5-hour and Weekly at every size.

## 2.6.2 — October 11, 2026

- Show the running and available versions in the launcher restart prompt when they differ. Use a plain restart message for matching or unidentified versions, including hidden tray widgets and legacy titles.

## 2.6.1 — October 11, 2026

- Add a persistent Local only tray switch to pause shared Codex/Claude accounts and all JSON reads and writes without losing configured connections. Restore sharing with the same switch.

## 2.6.0 — October 9, 2026

- Label Shared Codex and Shared Claude readings Stale after 31 minutes without a publisher check-in. After one hour, hide visible values and tray bars and show Last refresh X hours ago.
- Preserve cached readings for hover history, including last calculated percentages, known credits and calculation time. Restore values when a fresh check-in arrives. Use publisher writtenAt rather than local file-read time; retain a reading-time fallback for older exports.
- Cover connected, picker, separate, compact and menu-height views with isolated regression tests, and add portable contributor guidance.

## 2.5.1 — October 8, 2026

- Ignore both five-hour and weekly reset timestamp changes in shared JSON while five-hour usage remaining is 100%. Keep the last published weekly reset date through restarts and 30-minute check-ins; resume current reset dates when usage begins.
- Continue publishing actual percentage, credit and account-setting changes while idle. Apply the same rules to Codex and Claude exports, with regression checks for restart recovery, check-ins and independent source state.

## 2.5.0 — October 7, 2026

- Normalize JSON integer types before restoring refresh dropdowns, preventing saved intervals from silently selecting Manual only when Settings reopens. Verify untouched Apply and restart persistence.
- Replace repeated account inheritance checkboxes with one top-level Use General defaults switch per account. Preserve custom overrides and earlier mixed inheritance until the switch is changed; palettes and file connections remain independent.
- Move local JSON export controls to Codex and Claude. Keep imports on the shared tabs, and allow source-only exports and check-ins with imported accounts disabled. Preserve existing paths and source IDs.
- Refresh the settings screenshots and add source-only sharing and simplified defaults regression coverage.

## 2.4.2 — October 4, 2026

- Refresh the desktop shortcut icon with a dark dashboard tile and blue, purple and sage bars, including seven native Windows icon sizes. Add the artwork generator for future updates.
- Refresh README screenshots with current connected accounts, the stationary usage bar, single-account sizes and all five settings tabs. Use genuine usage readings with neutral account names and private paths replaced by placeholders.

## 2.4.1 — October 4, 2026

- Suppress five-hour countdowns and projected reset times while 100% remains; show “Reset starts after usage” (compact: “Not started”) until actual usage begins. Weekly resets remain independent.
- Export unused five-hour reset timestamps as zero, so drifting server timestamps no longer cause extra OneDrive writes or update the last usage-change time. Retain the 30-minute check-in.
- Verify idle reset drift, restart recovery, first-use restoration, and independent weekly resets.

## 2.4.0 — October 4, 2026

- Stop settings flicker by applying inherited and connection-specific locks directly, without briefly re-enabling controls on every status tick.
- Add a stationary menu-height line of account name, 5-hour percentage/countdown, weekly percentage/countdown and available credits. Hide countdowns before metric labels as width decreases.
- Keep connected detail levels and cell spacing aligned, retain full reset details on hover, preserve saved thin heights, and keep stacked/detached windows readable.
- Add regression checks for stable settings locks, progressive inline details, connected alignment and thin-height persistence.

## 2.3.0 — October 4, 2026

- Rename the app to AI Usage Widget, including the main script, launchers, icon, window titles, new desktop shortcuts and documentation. Keep the GitHub repository name unchanged.
- Add a General tab for shared window/startup controls and default refresh, reset-display, notification and Codex credit settings.
- Add separate inheritance switches by account and settings group. Preserve custom overrides while inheriting, restore them on uncheck, keep colors independent, and preserve existing choices during migration.
- Label account tabs Codex, Shared Codex, Claude and Shared Claude; retain provider names alongside account nicknames in the tray and card status.
- Keep forwarding launchers for existing shortcuts, preserve saved settings and Claude sign-in, and support graceful restart of widgets using the old script name.
- Refresh owned sign-in shortcuts to the renamed launcher and icon; retire owned old desktop shortcuts when recreating them.
- Synchronize side-by-side and stacked display transitions, numeric font sizes, value columns, reset-detail space and credit slots so mixed Codex/Claude panels stay aligned, including Mini. Separate windows retain independent sizing.
- Automatically show stationary 5-hour, weekly and credit values across one row when resized wide and short; restore vertical rows when narrowed or made taller. No scrolling or animation.

## 2.2.2 — October 4, 2026

- Restore Codex tray meters when choosing Open Codex Usage after opening Claude. Select shared Codex when local Codex is disabled.
- Add regression checks using the actual tray menu click handler.

## 2.2.1 — October 4, 2026

- Preserve Claude reset timestamp timezones after JSON parsing, fixing early weekly times and premature “Resetting now” countdowns.
- Align weekly rows across side-by-side accounts when Codex credits are displayed, without adding a Claude credit balance.
- Add timestamp normalization and account-row alignment regression checks.

## 2.2.0 — October 4, 2026

- Add optional Claude subscription usage through a dedicated signed-in WebView2 Usage window, independent refresh/reset settings, palettes and notifications. Keep unknown quotas unknown and handle expired sessions, timeouts and rate limits.
- Add independent Local Codex, Shared Codex, Local Claude and Shared Claude switches. Disabled accounts stop displaying and polling; local publishers also stop.
- Extend common layouts and the account picker to four sources; remember independent attached/separate Claude window geometry and reopen each from the tray.
- Add Claude JSON sharing with separate files and alert history, provider validation, change-only exports and 30-minute automatic check-ins. Shared imports remain independent of a disabled local Claude account.
- Add isolated regression checks for Claude conversion, four-account layouts, disabled responses and Claude file sharing.

## 2.1.6 — October 1, 2026

- Show unknown credit balances as “—” in labeled rows, with the full explanation on hover. Long unavailable-balance messages no longer force the shared account into numbers-only mode when its quota labels fit.
- Check side-by-side layouts with missing, unknown, and invalid shared balances alongside a known local balance.

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

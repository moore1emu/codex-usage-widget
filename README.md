# Codex Usage Widget

A small Windows desktop and tray widget for Codex **5-hour and weekly usage left**, reset countdowns, credits, and notifications.

**Version 1.7.2** · [Changelog](changelog.md) · [Detailed guide and troubleshooting](extradetails.md)

## Quick start

1. Install **PowerShell 7** and **Codex**, and sign in to Codex on this computer.
2. Download the repository and extract it. Keep the files together.
3. Double-click **Start-CodexUsageWidget.cmd**.

Optional: run **Create-DesktopShortcut.cmd** to add a desktop shortcut. Enable **Launch at Windows sign-in** from the tray menu for automatic startup.

## Widget sizes

Percentages show **quota remaining**: 100% is full and 0% is exhausted. Credits appear when available.

| Mini | Small | Medium | Large / Default |
| --- | --- | --- | --- |
| <img src="docs/screenshots/widget-mini.png" alt="Mini widget" width="72"> | <img src="docs/screenshots/widget-small.png" alt="Small widget" width="140"> | <img src="docs/screenshots/widget-medium.png" alt="Medium widget" width="190"> | <img src="docs/screenshots/widget-large.png" alt="Large widget" width="280"> |

Drag to move or resize. Use **↻** to refresh, **◉ / ○** for always on top, **—** to minimize to the tray, and **×** to exit. Hidden buttons appear on hover. Double-click the tray icon to restore the window.

Right-click the tray icon to choose sizes, colors, credit display, refresh interval, notifications, or a screen corner.

## Notification settings

Choose **Notifications...** from the tray menu. Set a low-quota threshold, or enable the 5-hour reset alert. **0 disables a threshold.** Reset alerts require weekly quota above 0%.

![Notification settings panel](docs/screenshots/notification-settings.png)

Screenshots show captured usage and settings, not live values. Settings are saved locally on each computer.

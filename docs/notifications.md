# DSH notifications and status: comparing the options

DSH keeps a session list, but when you are working in another window you need to
know when a session finishes, fails, or waits for your answer. Several
third-party plugins cover that need in different ways. This page compares the
options we know about, including the notification-only plugins, so you can pick
the smallest thing that solves your problem.

> DSH Status is our project. The other entries are included because users ask
> about them; check each project's README for its current behavior and
> compatibility. All of them are unofficial third-party tools.

| Option | Form | What it adds | Install |
| --- | --- | --- | --- |
| **DSH Status** | Native macOS app + DSH plugin | macOS notifications, a menu bar panel with live status and badges, click-to-jump, sounds, Do Not Disturb | DMG from [Releases](https://github.com/HAppy-2436/dsh-status/releases/latest), then `dsh plugin --profile web add dsh-status-bridge` |
| `dsh-niao-message` | DSH plugin | macOS Notification Center banners grouped into abnormal stop / needs you / completed, with settings and a click target | `dsh plugin --profile web add dsh-niao-message` |
| `dsh-completion-notifier` | DSH plugin | A toast/chime when a conversation turn finishes | `dsh plugin --profile web add dsh-completion-notifier` |
| `dsh-notch` | DSH plugin | A native notch surface for live sessions, approvals, and model questions | `dsh plugin --profile web add dsh-notch` |
| `dsh-notify-tray` | DSH plugin | Notifications plus a tray/status-bar icon, cross-platform, with progress and cost | `dsh plugin --profile web add dsh-notify-tray` |

## Which one should I choose?

- **I only want a banner when a turn finishes.** `dsh-niao-message` or
  `dsh-completion-notifier` are the lightest options.
- **I want a notch or a tray/status-bar icon, and maybe Windows/Linux.**
  `dsh-notch` or `dsh-notify-tray`.
- **I want a native macOS menu bar panel: live status, a badge for what needs
  me, click-to-jump, sounds, and Do Not Disturb.** DSH Status.
- **I do not want to install a separate app.** The DSH Status bridge plugin now
  works on its own for basic notifications; the app is an optional upgrade.
- **I use Windows or Linux.** DSH Status is macOS-only; use
  `dsh-notify-tray` or another cross-platform option.

## What "plugin only" means for DSH Status

The bridge plugin is the installable part. Without the app it sends one macOS
notification per meaningful transition:

- a session is waiting for input or approval;
- a turn completes;
- a turn stops with an error.

It uses `terminal-notifier` when available, otherwise `osascript`. Click-to-jump,
the menu bar panel, sounds, and Do Not Disturb require the app. Once the app
connects, the plugin stops sending fallback notifications so you do not get
duplicates.

## Install both in two commands

```bash
# 1) the plugin (required)
dsh plugin --profile web add dsh-status-bridge

# 2) the app (optional, recommended)
# download the DMG from https://github.com/HAppy-2436/dsh-status/releases/latest
```

The first launch of the app needs the Gatekeeper steps in the
[README](../README.md#install). The app is not notarized yet.

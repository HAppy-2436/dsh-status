# DSHStatusBar

The Swift menu bar app behind [DSH Status](../README.md). This directory contains
the app sources only; the product overview, screenshots, and installation
instructions live in the repository root.

## Build

Requires macOS 13+ and Swift 5.9+ (Xcode Command Line Tools).

```bash
# from the repository root
bash scripts/build-app.sh          # release build -> dist/DSHStatusBar.app (ad-hoc signed)
bash scripts/build-app.sh --debug  # debug build
```

The build script copies `app/Resources/dsh-chime.wav` into the app bundle and
runs the sound self-test (`--self-test-sound`) after assembling the bundle.

## Run

```bash
bash ../scripts/demo.sh   # mock bridge + app, no DSH required
```

By default the app reads `~/.dsh-status/bridge.json`. Debug entry points:

- `--bridge-file <path>` or `DSH_STATUS_BRIDGE_FILE=<path>`: use another bridge file
- `--open-panel`, `--open-settings`: open the panel / settings window on launch
- `--render-previews <dir>`: render the design preview images off-screen
- `--render-app-icon <path>`: render the 1024 pt app-icon source image
- `--self-test-sound`, `--test-sound[=<option>,<volume>[,<path>]]`: sound self-test / preview
- `DSH_STATUS_APPEARANCE=light|dark`: force the appearance (debugging and screenshots only)
- `DSH_STATUS_ANIM_SCALE=<n>`: slow down animations by a factor (debugging)

See the root [README](../README.md) for the product overview and
[`docs/`](../docs/) for design documentation.

## Source layout

- `MenuBarIconRenderer.swift` — menu-bar icon drawing (idle whale / status ring) and the app icon
- `WhaleLogo.swift` — DeepSeek whale vector path and SVG path parser
- `IconAnimator.swift`, `IconTransition.swift` — icon animation and state transitions
- `StatusItemController.swift` — status item, click/right-click behaviour, menus
- `StatusPanelView.swift` — SwiftUI panel content
- `StatusPanelController.swift` — custom `NSPanel`, glass/material background, positioning
- `SettingsWindow.swift`, `Settings.swift` — settings window chrome, settings model, settings UI
- `BridgeClient.swift` — bridge file discovery, SSE stream, command POST, reconnects
- `NotificationManager.swift`, `NotificationSound.swift` — system notifications and alert sounds
- `SleepPrevention.swift` — optional idle-sleep prevention while sessions are running
- `AppModel.swift`, `AppDelegate.swift`, `Models.swift`, `Theme.swift` — state model, app lifecycle, data types, design tokens
- `LaunchAtLogin.swift`, `SleepPrevention.swift` — launch-at-login (`SMAppService`) and idle-sleep prevention
- `AppIconController.swift` — app icon switching (brand double ring / DeepSeek blue whale), updates the bundle `.icns` and re-signs
- `PreviewRenderer.swift` — off-screen preview rendering

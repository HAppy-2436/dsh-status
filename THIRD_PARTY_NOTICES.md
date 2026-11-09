# Third-Party Notices

DSH Status is distributed under the [MIT License](LICENSE). It also contains
material derived from the two open-source projects below. The complete license
texts are included in the [`LICENSES/`](LICENSES/) directory.

| Component | License | Copyright | Used for |
| --- | --- | --- | --- |
| [Status Trio](https://github.com/lingyired/status-trio) | Apache License 2.0 | Copyright 2026 lingyired | Panel window and material implementation (adapted) |
| [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) | MIT | Copyright (c) 2026 DeepSeek | DeepSeek whale logo vector path |

---

## Status Trio — Apache License 2.0

- **Project:** lingyired/status-trio — <https://github.com/lingyired/status-trio>
- **License:** Apache License, Version 2.0 — full text in
  [`LICENSES/Apache-2.0.txt`](LICENSES/Apache-2.0.txt)
- **Copyright:** Copyright 2026 lingyired
- **Upstream revision used:** `d4598847040a5b2d167ec3825c162270eba3492b`
  (release v1.9.3), file
  `Sources/StatusTrioCore/UI/AnchoredStatusPanel.swift`
- **Integrated in this repository by commit:** `d69dca9`
  ("feat(panel): 直接采用 Status Trio 开源面板实现（Apache-2.0）") and
  modified further in later commits.

### Upstream NOTICE

The upstream repository contains a `NOTICE` file. Its text is reproduced here
in full, as required by section 4(d) of the Apache License 2.0:

```text
Status Trio
Copyright 2026 lingyired
```

### What was adapted

The menu-bar panel in `app/Sources/DSHStatusBar/StatusPanelController.swift`
is a modified, reduced adaptation of Status Trio's
`StatusTrioCore/UI/AnchoredStatusPanel.swift`. The following parts follow the
upstream implementation:

- `AnchoredStatusPanel` — the borderless, non-activating `NSPanel` recipe used
  as a replacement for an arrowed `NSPopover`: `level = .statusBar`, floating
  panel, transparent background, system window shadow, join-all-spaces
  collection behavior, `canBecomeKey`, and Escape/close handling.
- `StatusPanelContentViewController` — the clipped container with a 16 pt
  continuous corner radius, an `NSHostingController` child, and a background
  that can be swapped in place when the user changes the panel material.
- The panel background selection: `NSGlassEffectView(style: .regular)` with a
  16 pt corner radius and **no tint**, with the content hosted in an
  intermediate plain `NSView` inside `glass.contentView` (macOS 26+);
  `NSVisualEffectView(material: .popover, blendingMode: .behindWindow,
  state: .active)` as the classic frosted fallback; and an opaque fill when
  Reduce Transparency is enabled.

The adapted source file keeps the upstream copyright and attribution notice
(`Copyright 2026 lingyired`) in its header comment, as required by section 4(c)
of the Apache License 2.0.

`PanelBackgroundStyle` in `app/Sources/DSHStatusBar/Settings.swift`
(`liquidGlass` / `classicMaterial` / `solid`, plus the availability checks) is
adapted from Status Trio's `Models/PanelBackgroundStyle.swift`.

### Changes made to the upstream code

- Removed upstream app-specific infrastructure that this app does not use:
  `NSPopover`-style edge/anchor resolution with side flipping, Dock reveal
  inset, the shared height budget and scrolling policy, debug/test hooks,
  localization, self-update/appcast support, analytics, settings screens, and
  unrelated business logic.
- Replaced the upstream status content with this app's own SwiftUI session list
  (`StatusPanelView`), and replaced the upstream layout/measurement plumbing
  with direct anchoring below the menu-bar status item plus screen clamping.
- Added a top-aligned content host (`TopAlignedContentHost`) and a custom
  60 fps frame-by-frame window resize, so the panel grows and shrinks by moving
  only its bottom edge instead of stretching the rendered content.
- Re-timed window fades (0.06 s fade-in after the first layout pass, 0.12 s
  fade-out) and added Reduce Motion handling; added the system-native
  status-item highlight via an invisible 1×1 anchored `NSPopover`, outside-click
  event monitors, and Escape-to-close from the panel's local monitor.
- Adjusted dimensions and paddings to this app's design tokens (for example a
  330 pt fixed panel width) and added the app's own material settings UI.

The adapted code remains available under the Apache License 2.0; the MIT
license of this repository does not replace those terms for the adapted
portions.

---

## DeepSeek Harness — MIT License

- **Project:** deepseek-ai/deepseek-harness —
  <https://github.com/deepseek-ai/deepseek-harness>
- **License:** MIT — full text in
  [`LICENSES/MIT-deepseek-harness.txt`](LICENSES/MIT-deepseek-harness.txt)
- **Copyright:** Copyright (c) 2026 DeepSeek
- **Asset used:** the DeepSeek whale logo vector path published by the
  DeepSeek Harness frontend as `FISH_LOGO_PATH` (viewBox 23.16 × 17.04)

### What was used

`app/Sources/DSHStatusBar/WhaleLogo.swift` embeds the whale's SVG path data and
a small `M` / `C` / `L` / `Z` parser that renders it with AppKit. The path data
is taken verbatim from the upstream front-end asset; the parser, sizing,
template-image handling, colors, and animation are this project's own code. No
other DeepSeek Harness source code is included.

### Where the whale glyph appears

- The menu-bar idle state (`MenuBarIconRenderer.swift`);
- the panel header logo (`StatusPanelView.swift`);
- the optional DeepSeek-blue application icon (`AppIconRenderer.whaleImage`,
  selectable in Settings → General → App icon).

In earlier revisions (before the application icon was replaced with an original
design), the same glyph was also used for the application icon and the
quit-confirmation dialog icon (`AppIconRenderer.image`). The current application
icon is an original design and is not covered by this notice.

The MIT copyright and permission notice for this asset is included in
[`LICENSES/MIT-deepseek-harness.txt`](LICENSES/MIT-deepseek-harness.txt).

---

## License scope

- This repository's own code and assets are MIT-licensed (see
  [`LICENSE`](LICENSE)).
- The Status Trio–derived portions described above remain licensed under the
  Apache License 2.0.
- The whale vector path is used under the MIT License, Copyright (c) 2026
  DeepSeek.

If you redistribute this app or a modified version of it, keep [`LICENSE`](LICENSE),
[`NOTICE`](NOTICE), this file, and the [`LICENSES/`](LICENSES/) directory with
the source distribution, together with the attribution notices above.

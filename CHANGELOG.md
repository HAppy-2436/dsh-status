# Changelog / 更新日志

本项目所有值得注意的变更都记录在这里，中英双语。
All notable changes to this project are documented here, in Chinese and English.

格式遵循 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。
This project adheres to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/).

## [0.4.3] - 2026-11-19

### 中文

#### 新增
- **焦点会话跑完也会提醒**：DSH 的 `completionUnread` 只在「跑完时不在主视图」才置位，所以在看的
  那个会话跑完既没有「已完成」行、也不会触发状态跃迁通知。现在桥插件随快照上报焦点会话
  （`ClientSnapshot.focused`），Host 收到该会话 `turn/end` 时补一条 `BridgeState.notices`，
  App 照常弹横幅、响提示音：
  - 不产生面板行、不计入 counts / 角标（不会凭空出现一个「已完成」）；
  - 通知文案、点击跳转、勿扰模式、「已完成 / 已停止」开关与状态跃迁完全一致；
  - App 首帧只登记不通知（基线），之后按 notice `id` 去重，SSE 重连或重复推送不会重复提醒。
- 调试入口 `--test-notice`（走正式 notice 通知链路，发一条后自动退出）；
  `scripts/build-app.sh` 新增 `--self-test-notice` 自检：协议解码（含缺字段的旧桥）、
  文案兜底、`NoticeInbox` 基线/去重/上限、隐藏项目与状态显示过滤、AppModel 接线。

#### 兼容
- 协议 v1 纯增量：`BridgeState.notices`、`ClientSnapshot.focused`。旧 App 忽略新字段，旧桥不下发时
  App 按空列表处理，不需要同时升级；但要真正收到焦点提醒，桥插件需 **≥ 0.1.1** 并重启 DSH。

### English

#### Added
- **The session you are viewing now notifies when it finishes.** DSH sets
  `completionUnread` only when a turn ends outside the main view, so a session finishing while you
  watch it produced neither a "completed" row nor a status-transition notification. The bridge now
  reports focused sessions (`ClientSnapshot.focused`) and the host emits a `BridgeState.notices`
  entry on that session's `turn/end`; the app shows the usual banner and plays the sound:
  - no panel row, no counts / badge change (no phantom "completed");
  - identical wording, click-to-open, Do Not Disturb and completed/stopped switches as row
    notifications;
  - the first frame only registers (baseline); afterwards notices are de-duplicated by `id`, so SSE
    reconnects or repeated pushes never re-alert.
- Debug entry `--test-notice` (drives the real notice path, posts one and quits);
  `scripts/build-app.sh` gains a `--self-test-notice` check covering protocol decoding (including a
  bridge without the new fields), wording fallbacks, `NoticeInbox` baseline/de-duplication/capacity,
  hidden-project and status-visibility filters, and the AppModel wiring.

#### Compatibility
- Protocol v1, additive only: `BridgeState.notices` and `ClientSnapshot.focused`. Old apps ignore the
  new fields and old bridges omitting them decode as an empty list, so no lockstep upgrade is
  needed; the focus alert itself requires bridge **>= 0.1.1** and a DSH restart.

## [0.4.2] - 2026-11-10

### 中文

#### 修复
- **异常耗电 / 常驻 CPU 85%**：菜单栏外观 KVO 与状态项快照重绘形成自激循环 —— App 只要在运行
  就常驻约 85% 单核（整机功耗 4W → 12W、活动监视器能耗影响数千），与「播放运行动画 / 状态切换动效」
  等设置无关。修复：
  - **外观通知去重**：解析出的菜单栏深/浅色没有变化时不再重画（此前每次通知都 `forceSnapNext` +
    `refresh`），通知合并到主线程下一轮、同一轮最多刷新一次；
  - **静态图缓存**：状态 / 深浅色 / 动效开关都没变时复用同一张 `NSImage`，不重复渲染、不重复给
    `button.image` 赋值（macOS 27 上重复设图会触发状态项快照重绘）；
  - 提示文本（toolTip / accessibilityLabel）只在变化时写入；状态项尺寸未变时跳过图层布局；
    过渡用透明占位图改为复用缓存。
  - 实测：常驻 CPU **85.4% → 0.0%**（`top` 多轮采样均 0.0%，`sample` 无 `_updateReplicants` /
    `refresh` 热点）；深浅色切换、mock 每 8s 状态切换、51 步图标过渡回放、面板打开均正常。

### English

#### Fixed
- **Excessive power drain / constant 85% CPU**: a self-sustaining loop between the menu bar appearance
  KVO and status-item snapshot redraws — the app burned ~85% of one core whenever it was running
  (system power 4W → 12W, Activity Monitor energy impact in the thousands), independent of the
  "run animation" / "transition animation" settings. Fixed by:
  - **de-duplicating appearance notifications**: no redraw unless the resolved dark/light menu bar style
    actually changed (previously every notification forced `snapTo` + `refresh`), with notifications
    coalesced to at most one refresh per run loop turn;
  - **caching the static image**: same state / appearance / animation flag reuses the same `NSImage` —
    no re-render and no repeated `button.image` assignment (repeated assignments trigger status-item
    snapshot redraws on macOS 27);
  - writing toolTip / accessibilityLabel only when changed, skipping layer layout when the item size is
    unchanged, and reusing a cached transparent placeholder during transitions.
  - Measured: steady-state CPU **85.4% → 0.0%** (0.0% across repeated `top` samples; no
    `_updateReplicants` / `refresh` hotspots in `sample`); dark/light switching, the mock bridge's 8s
    state cycling, the 51-step icon transition replay and panel opening all still work.

---

## [0.4.1] - 2026-11-10

### 中文

#### 修正
- 「菜单栏 → 空闲时图标 → 虚线圆环」改为**直接复用「未连接」状态的单虚线环素材**（不带短横），
  不再是 0.4.0 的双层虚线环。默认仍为鲸鱼 Logo，不预选该选项。

### English

#### Fixed
- The idle-icon option "dashed ring" now reuses the **single dashed ring of the "not connected"
  state** (no minus sign) instead of the 0.4.0 double-dashed ring. The default stays the whale
  logo; the option is not preselected.

---

## [0.4.0] - 2026-11-09

### 中文

#### 新增
- **应用图标可切换**：设置页「通用」新增「应用图标」——品牌双层环（默认）或 DeepSeek 蓝色鲸鱼。
  应用图标决定 Dock、Finder 与**系统通知横幅**的图标，因此切换时会把所选 `.icns` 写回 App 包并
  重新 ad-hoc 签名；重启 App 后 Finder / 通知图标生效（设置页提供「重启 App」按钮）。
  鲸鱼矢量路径来自 DeepSeek Harness（MIT），出处见 THIRD_PARTY_NOTICES.md。
- 调试入口：`--render-app-icon-whale <path>`、`--test-app-icon=brand|whale`、`--dump-app-icon`。

### English

#### Added
- **Switchable app icon**: Settings → General → App icon — the original brand double ring
  (default) or the DeepSeek blue whale. The app icon drives the Dock, Finder and the
  **system notification banner** icon, so switching writes the chosen `.icns` into the app
  bundle and re-signs it ad-hoc; restart the app to apply (the settings row offers a
  "Restart App" button). The whale vector path comes from DeepSeek Harness (MIT); see
  THIRD_PARTY_NOTICES.md.
- Debug entries: `--render-app-icon-whale <path>`, `--test-app-icon=brand|whale`,
  `--dump-app-icon`.

---

## [0.3.0] - 2026-11-09

### 中文

#### 新增
- **品牌「双层环」**：App / 通知 / 退出确认弹窗图标改为原创双层环（外环品牌绿 + 内环冷白），
  对应菜单栏图标最有辨识度的「双层环」状态（外环 = 待办优先级、内层 = 运行中）。
- **空闲时图标设置**：菜单栏在完全空闲时默认仍显示 DeepSeek 鲸鱼；设置页「菜单栏图标」新增
  「空闲时图标」，可切换为品牌「虚线双环」（单色线稿，随菜单栏深浅色自适应）。

### English

#### Added
- **Brand mark — double ring**: the app, notification and quit-dialog icon is now an original
  double ring (green outer ring + cool-white inner ring), mirroring the app's signature
  "double-layer ring" menu bar state (outer = pending priority, inner = running).
- **Idle icon setting**: while idle, the menu bar still shows the DeepSeek whale by default;
  Settings → Menu bar icon → Idle icon can switch it to the brand's dashed double-ring mark
  (monochrome line art that follows the menu bar appearance).

---

## [0.2.3] - 2026-11-09

### 中文

#### 修复
- 「登录时自动启动」在首次注册前若系统返回 `SMAppService.Status.notFound`，不再显示错误文案，
  而是按「未启用」正常显示（该状态在 App 不在 /Applications、或尚未经 LaunchServices 登记时可能出现；
  此时 `register()` 仍可正常注册，真正失败会在切换开关时提示系统错误）。
- 开关副标题区分「已随登录自动启动」与「登录 macOS 后自动打开 DSH Status」；离屏设置页预览不再读取
  本机真实登录项状态（文档图可复现）。

### English

#### Fixed
- The login-item toggle no longer shows an error when macOS reports `SMAppService.Status.notFound`
  before the first registration (possible when the app is outside `/Applications` or not yet registered
  with LaunchServices). It is treated as "not enabled"; a real failure is still reported when toggling.
- The subtitle now distinguishes "Launch at login is on" from the disabled hint, and offscreen settings
  previews no longer read the machine's real login-item state (reproducible docs).

---


### 中文

#### 新增
- **登录时自动启动**：设置页「后台」分区新增开关（默认关，macOS 13+），通过
  `SMAppService.mainApp` 注册/注销系统登录项；需要系统确认时在设置页提示并可直接打开
  「系统设置 → 通用 → 登录项」。状态每次从系统读取，不写入 UserDefaults。
- 调试入口 `--test-launch-at-login[=on|off]`：查询/注册/注销登录项并打印状态。

### English

#### Added
- **Launch at login**: new switch in **Settings → Background** (off by default, macOS 13+),
  backed by `SMAppService.mainApp`. When macOS requires approval, the settings page says so and
  offers a button to open **System Settings → General → Login Items**. The state is always read
  from the system, never persisted separately.
- Debug entry `--test-launch-at-login[=on|off]` prints the login-item state after an optional
  register/unregister.

---

## [0.2.1] - 2026-11-09

### 中文

#### 修复
- **菜单栏图标深浅色识别错误**：图标改为跟随**菜单栏自身的实际外观**
  （`NSStatusBarButton.effectiveAppearance`）绘制，而不是 App 的 `NSApp.effectiveAppearance`。
  修复「系统浅色模式 + 深色壁纸 / 菜单栏实际为深色」时，系统图标显示为浅色而本 App 图标变深色的问题；
  与开源项目 Status Trio 的菜单栏外观识别方式一致（观察 status-item button 的 effective appearance）。
  新增调试入口 `--dump-appearance`，打印 App 外观与菜单栏实际外观，便于核对。

#### 新增
- 无。

### English

#### Fixed
- **Menu bar icon light/dark detection**: the icon now follows the **menu bar's actual appearance**
  (`NSStatusBarButton.effectiveAppearance`) instead of `NSApp.effectiveAppearance`. This fixes the icon
  turning dark while system/template icons stayed light when the menu bar itself is dark (for example a
  light system appearance with a dark wallpaper). Matches how Status Trio resolves menu bar appearance
  (observing the status-item button's effective appearance). New debug entry `--dump-appearance` prints
  both appearances for verification.

---

## [0.2.0] - 2026-11-09

### 中文

#### 新增
- 首个公开预览版本（macOS 菜单栏 App `DSH Status`）：
  - **菜单栏图标**：待回答 / 运行中 / 已完成 / 已停止四态，数字角标，状态切换动效
    （外环扫入/收回、数字里程表滚动、彗星弧变形），遵循「减弱动态效果」与低电量模式；
  - **面板**：会话列表、子智能体展开/收起、点击会话跳到 DSH 对应会话；
  - **通知**：待回答 / 已完成 / 已停止通知，支持勿扰模式；
  - **提示音**：App 内独立音量，内置 DSH 提示音 / 系统声音 / 自定义音频；
    可走「App 直接播放」或「系统通知音」（跟随系统专注模式）；
  - **后台**：「运行时阻止睡眠」开关（默认关，有会话运行且已连接时阻止闲置系统睡眠）；
  - **设置页**：应用/图标/通知/提示音/后台分区，显示版本与连接状态；
  - 调试与验收入口：`--render-previews`、`--self-test-sound`、`--test-sound` 等。
- DMG 发布产物：`DSH-Status-0.2.0.dmg` + `.sha256`，内含中英双语 `INSTALL.txt`。

#### 变更
- DSH 插件拆分到独立 npm 包 [`dsh-status-bridge`](https://github.com/HAppy-2436/dsh-status-bridge)；
  App 与插件通过 `~/.dsh-status/bridge.json` 通信。
- 许可证：MIT（Copyright © 2026 HAppy-2436）；第三方许可见 `LICENSES/`。

#### 说明
- 0.2.0 的 DMG 为 ad-hoc 签名、**未公证**：首次打开需右键 →「打开」，或到
  「系统设置 → 隐私与安全性」点「仍要打开」；详见 DMG 内 `INSTALL.txt` 与
  [`docs/RELEASE.md`](docs/RELEASE.md)。

### English

#### Added
- First public preview release (macOS menu bar app `DSH Status`):
  - **Menu bar icon**: pending / running / completed / stopped states, badge count and
    animated transitions (ring sweep, odometer-style number roll, comet-arc morphing)
    that respect Reduce Motion and Low Power Mode;
  - **Panel**: session list, sub-agent disclosure, click a session to open it in DSH;
  - **Notifications**: pending / completed / stopped, with a Do Not Disturb switch;
  - **Notification sounds**: independent in-app volume, built-in DSH chime / system sounds /
    custom audio; delivered either in-app or via the system notification sound
    (honours system Focus modes);
  - **Background**: "prevent idle system sleep while sessions are running" switch
    (off by default);
  - **Settings**: app/icon/notification/sound/background sections with version and
    connection state;
  - Debug and verification entry points: `--render-previews`, `--self-test-sound`,
    `--test-sound`, and more.
- DMG release artifacts: `DSH-Status-0.2.0.dmg` plus `.sha256`, with a bilingual
  `INSTALL.txt` inside.

#### Changed
- The DSH plugin was split into the standalone npm package
  [`dsh-status-bridge`](https://github.com/HAppy-2436/dsh-status-bridge); the app talks to
  it through `~/.dsh-status/bridge.json`.
- License: MIT (Copyright © 2026 HAppy-2436); third-party licenses are listed in `LICENSES/`.

#### Notes
- The 0.2.0 DMG is ad-hoc signed and **not notarized**: on first launch use
  right-click → Open, or click "Open Anyway" in System Settings → Privacy & Security.
  See `INSTALL.txt` inside the DMG and [`docs/RELEASE.md`](docs/RELEASE.md).

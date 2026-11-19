# Changelog / 更新日志

本项目所有值得注意的变更都记录在这里，中英双语。
All notable changes to this project are documented here, in Chinese and English.

格式遵循 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。
This project adheres to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/).

## [0.4.4] - 2026-11-19

### 中文

#### 改进
- **焦点会话跑完，菜单栏图标不再直接跳空闲**：0.4.3 只补了通知，但图标/面板只认状态行，
  所以看起来是「运行中 → 空闲」。现在桥会为焦点会话补一条 **transient「已完成」行**
  （`SessionRow.transient = true`）：
  - 图标走「运行中 → 已完成」，角标 +1，面板里出现这一行（点它照样打开会话）；
  - 行尾有 **×**：点一下即忽略（桥删掉该行，角标 -1，不影响会话）；
  - 在该会话里继续发消息（重新运行 / 待回答）或 DSH 自己报了未读时，临时行自动消失；
  - 临时行由 Host 维护：DSH 重启或桥重载后不再存在。
- **单实例保护**：同一 bundle id 已经有实例在跑时，新启动的第二个进程（比如又打开了一次仓库里的
  `dist/DSHStatusBar.app`）会直接退出并激活已有实例，不会再出现「菜单栏两个图标 / 通知发两遍」。
  调试入口（`--test-*` / `--dump-*` / `--render-*` / `--open-panel` / `--bridge-file` 等）不受限制。
- **行尾控件对齐**：右箭头 / 披露按钮 / 忽略 × 统一到同一条轨道（22pt 槽位、间距 4、右边距 8），
  图标中线一致，不再出现「三种控件各偏几 pt」。
- **点这一行或点通知横幅跳转 = 已读**：和普通未读行一样，跳转后临时行自动删掉（不用再点 ×）。
- **展开/收起子智能体不再抖**：修了两个会让面板在展开/收起时「闪一下」或「一卡一卡」的原因——
  ① 高度动画途中收到桥的状态推送时，目标高度没变就保持当前动画；以前每次推送都会把 0.22s 动画
  从 0 重启，运行中会话的快照一密集，展开会被拖长到 1s 以上且一顿一顿；
  ② 面板内容改放在一块固定高度的画布顶部（与窗口尺寸解耦），不再出现 `NSHostingView` 把「比宿主高」
  的内容垂直居中一帧、导致整块列表瞬间上下跳的情况。
- 右键菜单新增 **「全部忽略」**：只在存在这类临时行时出现，一次清掉全部（角标随之减少）。
- 通知仍由 `notices` 提供，与行通知共用 30s 去重，不会响两次。

#### 兼容
- 协议 v1 纯增量：`SessionRow.transient`（可选）与 `POST /command {type:"dismiss"}`。
  旧 App 忽略 `transient`，行照常显示、只是没有 ×；旧桥不下发时 App 行为不变（0.4.3 的纯通知）。

### English

#### Changed
- **A focused session no longer makes the menu-bar icon jump straight to idle.** 0.4.3 only added
  the notification, but the icon and panel are driven by status rows, so it looked like
  running → idle. The bridge now adds a **transient "completed" row** (`SessionRow.transient = true`):
  - the icon goes running → completed, the badge goes +1, and the row shows in the panel (clicking
    it still opens the session);
  - the row has an **×**: clicking it dismisses the row (the host drops it, badge −1, session
    untouched);
  - starting another turn in that session (running / waiting) or DSH reporting the session unread
    clears the transient row automatically;
  - transient rows live in the host only: a DSH restart or bridge reload drops them.
- **Single instance**: launching a second process with the same bundle id (for example opening the
  repository's `dist/DSHStatusBar.app` while the installed app runs) now exits immediately and
  activates the existing instance, so the menu bar never shows two icons or sends duplicate
  notifications. Debug entries (`--test-*`, `--dump-*`, `--render-*`, `--open-panel`,
  `--bridge-file`, …) are exempt.
- **Trailing controls share one rail**: the nav chevron, the disclosure toggle and the dismiss × use the
  same 22 pt slot, 4 pt spacing and 8 pt inset, so their icon centers line up.
- **Clicking the row (or the notification banner) opens the session and clears the row**, exactly
  like opening a normal unread row; the × remains for dismissing without jumping.
- **Expanding/collapsing subagents no longer jitters.** Two causes are fixed: (1) a bridge state push
  arriving mid-animation used to restart the 0.22 s height animation from zero, so frequent snapshots
  stretched the reveal past 1 s and made it stutter — a same-target push is now ignored while the
  animation runs; (2) the panel content now sits on a fixed-height canvas decoupled from the window, so
  `NSHostingView` no longer vertically centres an over-tall root for one frame and makes the whole list
  jump up/down at the start of the animation.
- The right-click menu gains **Dismiss All**, shown only while such rows exist; it clears every
  transient row at once (badge drops accordingly).
- Notifications still come from `notices` and share the 30 s de-duplication with row notifications,
  so there is no double alert.

#### Compatibility
- Protocol v1, additive: `SessionRow.transient` (optional) and `POST /command {type:"dismiss"}`.
  Old apps ignore `transient` and simply show the row without the ×; old bridges leave the app on the
  notification-only behavior of 0.4.3.

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
- **0.4.4 调整**：焦点会话完成时额外补一条临时「已完成」行（图标不再跳空闲），见下一节。

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

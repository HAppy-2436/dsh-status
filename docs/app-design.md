# App 设计规范（v3 · 鲸鱼 + 分段圆环）

> 实现进度（2026-11-03）：**P0 已实现**（`app/`），预览见 `docs/previews/`。
> v3 变更：空闲显示 DeepSeek 鲸鱼 Logo；非空闲用**分段圆环**——圆环按非空闲任务数等分，
> 每段一个任务、颜色为该任务状态；中心显示关注数（只有运行中时不显示数字）。
> Logo 资源取自 DSH 前端 `FISH_LOGO_PATH`（viewBox 23.16×17.04）。

面向 `app/` 的 Swift 菜单栏 App。图标设计是重点，需产出可评审的预览图。

## 1. 定位

- 纯菜单栏 App（`LSUIElement = true`），无 Dock 图标、无主窗口。
- 单击状态栏图标 → 打开/关闭 NSPopover 面板；再次单击关闭。
- 面板里点击会话行 → 跳转到 DSH 对应会话（发命令 + `open "dsh://open"`）。
- 不显示空闲会话；显示 待回答 / 运行中 / 已完成 / 已停止 四类。

## 2. 菜单栏图标（鲸鱼 + 分段圆环）

### 2.1 设计原则

- 固定 22×22 占位，不随状态改变宽度。
- 空闲 = 只显示 DeepSeek 鲸鱼 Logo（无环、无数字）。
- 非空闲 = 分段圆环：**段数 = 非空闲任务数**，每段颜色 = 该任务状态。
- 中心数字 = 待回答 + 已完成 + 已停止（需要关注的数量）；只有运行中时不显示数字。
- 深色优先：段环带柔和外发光，数字带阴影；浅色模式自动换更深的颜色。

### 2.2 几何（单位 pt，2x 渲染）

- 画布 22×22，圆心 (11, 11)。
- 圆环半径 8.05，线宽 2.4；段与段之间留 9° 缺口（N 很多时按 `min(9°, 0.22×360/N)` 收缩）。
- 单段时画完整圆环（无缺口）。
- 中心数字：SF Rounded Bold，1 位 10.6pt / 2 位 9.2pt / 3 位（`99+`）7.6pt。
- 空闲鲸鱼：宽 18.8pt，等比（高约 13.8pt），居中。

### 2.3 状态与颜色

| 情况 | 圆环 | 中心 |
| --- | --- | --- |
| 空闲（没有任何非空闲任务） | 无环，纯白鲸鱼（浅色模式近黑） | 无 |
| N 个任务（N≥1） | N 段等分；颜色按任务状态 | 关注数 > 0 时显示，只有运行中则不显示 |
| 未连接 | 灰色虚线环 | 短横 |

- 段色（v3 修订，低饱和、深色优先）：待回答 `#E97F76`、运行中 `#7AA9D7`、已完成 `#7EC09D`、
  已停止 `#DBB075`；浅色模式加深一档（`#D0655D / #5985BD / #5A9A79 / #B88C51`）。
  端点用圆头、段间留 13°–24° 缺口（任务多时自动收窄），避免锐利感。
- 段顺序：待回答 → 运行中 → 已完成 → 已停止（同色尽量相邻，整环可读）。
- 数字颜色：深色模式白色、浅色模式近黑；带 1.2pt 柔和阴影。

### 2.4 资源

- 鲸鱼矢量路径来自 DSH 前端 `FISH_LOGO_PATH`（`WhaleLogo.swift` 内置 path 与 M/C/L/Z 解析器），
  不依赖外部图片，任何分辨率都清晰。
- 面板 header 复用同一鲸鱼路径（模板图片，随主题着色）。

## 3. 面板（NSPopover）

- 宽 344pt；内容 SwiftUI（`NSHostingController`）。
- header（高 46）：26pt 圆形鱼标 + 「DSH 会话」13pt semibold +「DeepSeek Harness」10pt 三级；
  右侧状态胶囊（绿点+实时 / 橙点+未连接）。
- 分组（有内容才显示）：待回答（红）、运行中（蓝）、已完成（绿）、已停止（橙）。
  - 分组标题：11pt semibold secondary + 右侧计数小胶囊。
  - 行高 46：**行内不再重复状态色**（颜色只出现在分组标题的状态点上）；主标题 12.5pt medium
    （待回答行用 semibold 轻强调），副标题 10.5pt secondary
    （`项目名 · 待回答摘要` / `项目名 · 已运行 2:14` / `项目名 · 3 分钟前`）。
  - 行文字与分组标题对齐（29pt）；hover 背景圆角 10；点击整行生效。
- 空状态：44pt 圆形底 + sparkles 图标 +「全部空闲 / 没有需要关注的会话」。
- 未连接：橙点 +「DSH 未连接」+ 说明 +「打开 DSH」按钮。
- footer（高 44）：「打开 DSH」胶囊按钮；右侧三个 26pt 圆形图标按钮：
  待回答通知开关（绑定 `settings.notifyWaiting`，图标即时切换 bell / bell.slash）、设置、退出。

## 2.6 视觉规范（v3 修订）

- **深色适配**：面板背景改用原生 `NSVisualEffectView`（`.popover` 毛玻璃），跟随系统外观；
  文字层级用系统语义色（primary / secondary），不写死颜色；离屏预览时退回实色背景。
- **圆角**：卡片 14pt、行 10pt、图标容器 12pt、控件胶囊；避免直角与硬边。
- **配色**：统一走 `Theme.swift`（低饱和状态色 + 深浅两套）；强调色只保留在状态点/分段环上，
  其余 UI 用系统语义灰阶，整体更接近 macOS 原生风格。
- **分隔线**：统一 1px、约 7% 前景色；悬停底色 4.5%–5.5%，不再使用高饱和红/蓝填充。
- **图标**：分段圆环使用圆头端点、柔和外发光；未连接虚线改为圆头短划。

## 3.1 设置页（NSWindow + SwiftUI）

- 入口：面板 footer 齿轮按钮 / 右键菜单「设置…」（⌘,）。
- 窗口 470×760 固定大小，header + 可滚动内容 + 固定底栏（恢复默认 / 版本 / 连接状态）。
- 设置项（全部即时生效并持久化到 UserDefaults，键前缀 `dshStatus.`）：

| 分区 | 设置 | 说明 |
| --- | --- | --- |
| 显示状态 | 待回答 / 运行中 / 已完成 / 已停止 四个开关 | 关掉的状态不在面板出现，也不进圆环与数字 |
| 项目显示 | 按 workspace 列出当前有会话的项目开关 | 关掉即隐藏该项目（会话本身不受影响） |
| 菜单栏图标 | 中心数字：关注数 / 非空闲总数 / 不显示 | 关注数 = 待回答+已完成+已停止（默认） |
| 菜单栏图标 | 圆环段数上限：4 / 6 / 8 / 12 / 不限 | 超出上限按优先级只画前 N 段，数字仍完整 |
| 通知 | 待回答（默认开）/ 已完成 / 已停止 | 首帧基线不通知；同会话同状态 30s 去重 |

- 空项目列表显示「暂无已知项目（连接 DSH 后出现）」。
- 预览图：`docs/previews/settings-preview-dark.png`。

## 4. 通知（最小实现）

- `UNUserNotificationCenter`：首次需要通知时请求权限；被拒绝则静默。
- 默认**只对「进入待回答」发通知**（title = 会话标题，body = 待回答摘要，点击 → 打开主页面）。
- 已完成/已停止默认不发；待回答通知 30s 内同会话去重。
- 通知点击：`open "dsh://open"`。

## 5. App 结构（Swift Package，无第三方依赖）

```
app/
  Package.swift
  Sources/DSHStatusBar/
    main.swift                  // 入口；--render-previews 时离屏出图
    AppDelegate.swift
    StatusItemController.swift  // NSStatusItem / 右键菜单 / 变体切换
    MenuBarIconRenderer.swift   // §2 单圆形图标绘制（disc / ring）
    BridgeClient.swift          // bridge.json 轮询 + SSE + 命令 POST + 重连
    Models.swift                // BridgeState / SessionRow / Command（Codable）
    PopoverController.swift
    StatusPanelView.swift       // SwiftUI 面板
    NotificationManager.swift
    PreviewRenderer.swift       // 预览图：图标矩阵 / 面板三态 / 场景示意
```

- 入口参数/环境：
  - `--render-previews <outDir>`：生成 `icon-preview-light/dark.png`、`panel-preview-light/dark.png`、
    `scene-preview-dark.png`（模拟菜单栏 + 打开面板）。
  - `--bridge-file <path>` / `DSH_STATUS_BRIDGE_FILE=<path>`：覆盖 bridge.json 路径。
  - `--open-panel`：启动后自动打开面板（截图/调试）。
- `scripts/build-app.sh`：`swift build -c release` → `dist/DSHStatusBar.app`（Info.plist + ad-hoc 签名）。
- 异常宽容：bridge.json 缺失/损坏、SSE 断开、DSH 重启都不得崩溃。

## 6. 验收

1. `swift build -c release` 通过；`scripts/build-app.sh` 产出可启动 .app。
2. `--render-previews` 产出图标矩阵、面板三态、场景示意图。
3. 连 mock 桥时图标数字/颜色随状态变化，面板分组正确，点行会 POST 命令并打开 DSH。
4. 断开 mock 后 6s 内进入未连接态；mock 恢复后自动重连。

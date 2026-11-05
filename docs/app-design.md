# App 设计规范（v3 · 鲸鱼 + 分段圆环）

> 实现进度（2026-11-03）：**P0 已实现**（`app/`），预览见 `docs/previews/`。
> v3 变更：空闲显示 DeepSeek 鲸鱼 Logo；非空闲用**分段圆环**——圆环按非空闲任务数等分，
> 每段一个任务、颜色为该任务状态；中心显示关注数（只有运行中时不显示数字）。
> Logo 资源取自 DSH 前端 `FISH_LOGO_PATH`（viewBox 23.16×17.04）。

面向 `app/` 的 Swift 菜单栏 App。图标设计是重点，需产出可评审的预览图。

## 1. 定位

- 纯菜单栏 App（`LSUIElement = true`），无 Dock 图标、无主窗口。
- 单击状态栏图标 → 打开/关闭自定义 NSPanel 面板；再次单击关闭（无箭头）。
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

- 段色（参考 Status Trio 的系统强调色）：待回答 `#F2B900`（黄）、运行中 `#0A84FF`（蓝）、
  已完成 `#34C759`（绿）、已停止系统红 `#FF453A`；浅色模式加深一档。
  颜色只用于小面积（段环 / 行首 SF Symbol），文字与背景保持单色。
  端点用圆头，段间缺口按线宽/段数自适应（约 18°–30°，扣掉端点后约 4°–8° 可见缝隙），避免锐利感。
- 段顺序：待回答 → 运行中 → 已完成 → 已停止（同色尽量相邻，整环可读）。
- 数字颜色：深色模式白色、浅色模式近黑；带 1.2pt 柔和阴影。

### 2.4 资源

- 鲸鱼矢量路径来自 DSH 前端 `FISH_LOGO_PATH`（`WhaleLogo.swift` 内置 path 与 M/C/L/Z 解析器），
  不依赖外部图片，任何分辨率都清晰。
- 面板 header 复用同一鲸鱼路径（模板图片，随主题着色）。

## 3. 面板（自定义 NSPanel，参考 Status Trio）

- 不用 `NSPopover`：无边框 `NSPanel`（`.borderless + .nonactivatingPanel`），**没有 popover 箭头**，
  `.statusBar` 层级、跨 Space、不抢焦点；16→20pt continuous 圆角。
- 材质（设置页「面板背景」可切换，默认液态玻璃）：
  - macOS 26+ `NSGlassEffectView`（style `.regular`，`effectIsInteractive`）；
  - 旧系统 `NSVisualEffectView(.popover)` 经典磨砂；
  - 显式选「实色」或系统开启「降低透明度」时用不透明填充。
  - 跟随系统深浅色与壁纸；打开时 `makeKey()` 让内容按 active 渲染（状态色不被去饱和）。
- 定位：状态项下方 6pt，按屏幕可见区域夹取；0.08s 淡入（Reduce Motion 时直接显示）。
- 关闭：再次点击状态项、点击面板外（含 DSH 主窗口等本应用窗口）、Esc。
- 宽 330pt、14pt 边距；内容 SwiftUI（`NSHostingController`），背景透明由面板提供材质；
  离屏预览时退回实色。
- header：鲸鱼 +「DSH 会话」headline + 右侧连接小点/「实时 / 未连接」。
- 分组（有内容才显示）：待回答（黄）、运行中（蓝）、已完成（绿）、已停止（红）。
  - 分组标题：`待回答 · 1`，11.5pt semibold secondary，无彩色圆点。
  - 会话行：左侧 24pt SF Symbol（`questionmark.circle` / `play.circle` / `checkmark.circle` /
    `stop.circle`，对应状态色），标题 `.headline`、副标题 `.caption` secondary，右侧
    `chevron.right` tertiary；hover 8pt 圆角浅底；点击整行跳转。
  - 颜色收敛到行首小图标上（Status Trio 做法），不再有彩色圆点/红色底。
- 尾部「打开 DSH」行（`arrow.up.forward.app` + chevron）。
- 空状态：鲸鱼 +「全部空闲 / 没有需要关注的会话」。
- 未连接：exclamationmark.circle +「DSH 未连接」+ 说明 +「打开 DSH」按钮。
- footer（高 40）：左「⚙ 设置…」，右 bell（待回答通知）与 power（退出）；退出走二次确认。

## 2.6 视觉规范

- **材质**：面板用系统 Liquid Glass / 经典磨砂 / 实色（设置项），文字层级走系统语义色；
  颜色只用于小面积（分段环、行首 SF Symbol、连接点）。
- **圆角**：面板 20pt、设置卡片 10pt、行 8pt、图标容器 6.5pt（26pt 方块）。
- **配色**：`Theme.swift` 统一系统强调色——待回答 `#F2B900`、运行中 `#0A84FF`、
  已完成 `#34C759`、已停止系统红；未连接中性灰。
- **分隔线**：1px、约 7% 前景色；hover 仅 4–6% 前景色。
- **图标**：分段圆环圆头端点、自适应缺口；未连接虚线环。

## 3.1 设置页（NSWindow + SwiftUI）

- 入口：面板 footer 齿轮按钮 / 右键菜单「设置…」（⌘,）。
- 窗口 470×780 固定大小，可滚动分组内容 + 固定底栏（恢复默认 / 「退出前确认」checkbox / 版本与连接状态）。
- 视觉参考 macOS 系统设置 / Status Trio：分组标题 11.5pt semibold secondary；卡片 `controlBackgroundColor`、
  10pt continuous 圆角、7% 前景色描边；行内左侧 26pt 渐变圆角图标（白色 SF Symbol）+ 标题/副标题 + 控件；
  行间分隔线从图标列之后开始。
- 设置项（全部即时生效并持久化到 UserDefaults，键前缀 `dshStatus.`）：

| 分区 | 设置 | 说明 |
| --- | --- | --- |
| 显示状态 | 待回答 / 运行中 / 已完成 / 已停止 四个开关 | 关掉的状态不在面板出现，也不进圆环与数字 |
| 项目显示 | 按 workspace 列出当前有会话的项目开关 | 关掉即隐藏该项目（会话本身不受影响） |
| 菜单栏图标 | 中心数字：关注数 / 非空闲总数 / 不显示 | 关注数 = 待回答+已完成+已停止（默认） |
| 菜单栏图标 | 圆环段数上限：4 / 6 / 8 / 12 / 不限 | 超出上限按优先级只画前 N 段，数字仍完整 |
| 面板背景 | 液态玻璃（macOS 26+ 默认）/ 经典磨砂 / 实色 | 「降低透明度」开启时自动用实色 |
| 通知 | 待回答（默认开）/ 已完成 / 已停止 | 首帧基线不通知；同会话同状态 30s 去重 |


- 空项目列表显示「暂无已知项目（连接 DSH 后出现）」。
- 预览图：`docs/previews/settings-preview-dark.png`。

## 4. 通知

### 4.0 系统权限（关键）

- 通知权限**不能由 App 单方面决定**：被拒后 `requestAuthorization` 不会弹框，只会静默失败。
  因此启动/打开面板时查询 `UNUserNotificationCenter.getNotificationSettings`：
  - 未授权（notDetermined）：面板顶部提示「通知未开启，任务结束不会提醒 · 去开启」，点击后
    `NSApp.activate` + `requestAuthorization`（避免 App 在后台时系统框被静默拒绝）；
  - 已拒绝（denied）：提示变为「去开启」，点击打开系统设置「通知」面板；
  - 已授权：面板正常，铃铛可切换待回答通知。
- 设置页「通知」组顶部同样显示系统通知状态与操作按钮；发送通知不再依赖启动时的缓存
  `authorized` 标志（权限可能在运行中被用户打开）。
- Bundle ID 为 `com.liyitong.dshstatus`；旧域 `com.liyitong.dsh-status` 的 UserDefaults 在首次启动时自动迁移
  （通知图标的解析结果按 bundle id 缓存，换 id 是修复「通知横幅显示占位图标」的唯一非 TCC 手段）。
- App 图标使用与菜单栏空闲态同款的鲸鱼 glyph：**透明底、无圆角方块、主色 `#6485FC`**
  （构建时由 `WhaleLogo` 生成 `.icns`），与宿主 DeepSeek Harness 的官方图标区分开；退出确认弹窗也用同一 glyph。

### 4.1 行为

- `UNUserNotificationCenter`：由用户点「允许通知」时才请求权限（前台弹框）；被拒绝时在面板/设置页给出入口。
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

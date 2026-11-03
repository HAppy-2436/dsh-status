# App 设计规范（v1）

> 实现进度（2026-11-03）：**P0 已按本文档实现**（`app/`），预览图见 `docs/previews/`；
> 图标基础方案 A/B/C 已实现并出预览，**待用户选定**最终方案。

面向 `app/` 的 Swift 菜单栏 App。图标设计是重点，需产出可评审的预览图。

## 1. 定位

- 纯菜单栏 App（`LSUIElement = true`），无 Dock 图标、无主窗口。
- 单击状态栏图标 → 打开/关闭 NSPopover 面板；再次单击关闭。
- 面板里点击会话行 → 跳转到 DSH 对应会话（发命令 + `open "dsh://open"`）。
- 不显示空闲会话；显示 待回答 / 运行中 / 已完成 / 已停止 四类。

## 2. 菜单栏图标（重点）

### 2.1 信息层级

菜单栏空间有限，按优先级呈现：

1. **关注数**（最高）：待回答 + 已完成 + 已停止的会话总数 → 图标右侧胶囊数字。
2. **有问题的行动项**：存在待回答 → 胶囊红色；否则按完成/停止着色（绿/橙）。
3. **运行中**（不计数但必须可见）：蓝色「活动」指示（两根高低不一的竖条，或小圆点），仅在无数字时也显示。
4. **空闲**：仅基础图形（中性色），无数字无活动条。
5. **未连接**：基础图形 35% 不透明度，无数字、无活动条。

### 2.2 几何规格（单位 pt，2x/3x 渲染需清晰）

- 画布高度 18；内容高度 16，垂直居中。
- 基础图形宽 16，右侧距离 2。
- 胶囊：高 14、圆角 7、水平内边距 4.5，数字 SF Rounded Semibold 10.5。
  图形与胶囊间距 3；胶囊右缘到画布边缘 1。
- 活动指示：两根圆头竖条，宽 1.5，高 4 / 7，间距 2，垂直居中；位于图形与胶囊之间
  （无胶囊时位于图形右侧，间距 2）。颜色 `systemBlue`。
- 数字 > 99 时显示 `99+`（宽度自适应）。

### 2.3 三个候选基础图形（必须都有预览图）

- **A. fish**：SF Symbol `fish.fill`，15pt、`.semibold`，呼应 DSH 的鱼形品牌；
  现代、简洁、辨识度高。着色 `labelColor`（template 风格），旁边彩色胶囊提供状态。
- **B. sessions stack**：自绘三根圆头横条（宽 13/10/7，高 2.4，间距 2.2，左对齐），
  像会话列表；右侧叠一个 4pt 状态圆点（红/蓝/绿/橙/灰）。
- **C. harness nodes**：自绘「三节点连接」图形：三个 3.2pt 圆点（上中下品字形）用 1.2pt 细线相连，
  象征 agent harness；底部节点按状态着色。

默认实现 A，但渲染器用 `IconStyle` 枚举支持三套，预览图并排展示，供用户挑选。

### 2.4 状态组合预览矩阵

预览图需覆盖（每行一种状态，浅色/深色两条菜单栏背景）：

`空闲` / `运行中(2)` / `已完成(1)` / `已停止(1)` / `待回答(1)` / `混合(3，含待回答+运行中)` / `未连接`

浅色背景 `#EDEDED`，深色背景 `#1C1C1E`。同时渲染 1x/2x 清晰度说明。

### 2.5 其他

- Tooltip / accessibilityLabel：`DSH：1 待回答 · 2 运行中 · 1 已完成`。
- 不允许持续动画（省电、低调）；运行中使用静态活动条。
- 颜色使用系统语义色（`systemRed/systemOrange/systemGreen/systemBlue`），自动适配深浅色。

## 3. 面板（NSPopover）

- 宽 340pt；内容使用 SwiftUI（`NSHostingController`）。
- 顶部 header（高 40）：左侧 fish 小图标 + 「DSH 会话」13pt semibold；右侧连接状态圆点 +
  「实时 / 未连接」11pt。
- 分组（有内容才显示）：待回答（红）、运行中（蓝）、已完成（绿）、已停止（橙）。
  - 分组标题：11pt semibold，secondary 色，右侧数字。
  - 行高 46：左侧 8pt 状态圆点；主标题 13pt（会话标题，截断）；副标题 11pt secondary：
    `项目名 · 待回答摘要` / `项目名 · 已运行 2:14` / `项目名 · 3 分钟前`。
  - hover 背景圆角 8，点击整行生效；触控板/键盘可上下选择，Enter 打开，Esc 关闭。
- 空状态：居中「全部空闲」+ 次要说明「没有需要关注的会话」（高约 120）。
- 未连接：橙色圆点 + 「DSH 未连接」+ 说明 + 「打开 DSH」按钮。
- 底部 footer（高 40）：左「打开 DSH」，右两个图标按钮：通知开关（P2 可先占位）、退出。
- 面板出现时刷新一次 `GET /dsh-status/state` 兜底；关闭时不轮询。

## 4. 通知（P1 最小实现）

- `UNUserNotificationCenter`：首次需要通知时请求权限；被拒绝则静默。
- 默认**只对「进入待回答」发通知**（title = 会话标题，body = 待回答摘要，点击 → 打开主页面）。
- 已完成/已停止默认不发（设置项 P2）；待回答通知 30s 内同会话去重。
- 通知点击：`open "dsh://open"`；若实现方便可同时 `POST /dsh-status/command` 跳转会话。

## 5. App 结构（Swift Package，无第三方依赖）

```
app/
  Package.swift                 // executable target DSHStatusBar, macOS 13+
  Sources/DSHStatusBar/
    main.swift                  // 入口：无参数 → NSApp 菜单栏模式；有 --render-previews → 离屏渲染
    AppDelegate.swift           // NSStatusItem + 生命周期
    StatusItemController.swift  // 图标、点击、tooltip
    MenuBarIconRenderer.swift   // §2 全部绘制逻辑（支持 IconStyle）
    BridgeClient.swift          // bridge.json 轮询 + SSE + 命令 POST + 重连
    Models.swift                // BridgeState / SessionRow / Command（Codable）
    PopoverController.swift     // NSPopover + 面板生命周期
    StatusPanelView.swift       // SwiftUI 面板
    NotificationManager.swift
    PreviewRenderer.swift       // --render-previews 生成图标矩阵与面板预览 PNG
```

- 入口支持参数/环境：
  - `--render-previews <outDir>`：离屏渲染 `icon-preview-light.png`、`icon-preview-dark.png`、
    `panel-preview-light.png`、`panel-preview-dark.png`，不启动状态栏。
  - `DSH_STATUS_BRIDGE_FILE=<path>`：覆盖 bridge.json 路径（mock 联调用）。
- 构建脚本 `scripts/build-app.sh`：`swift build -c release` → 组装 `dist/DSHStatusBar.app`
  （拷贝二进制 + `Info.plist` + ad-hoc `codesign -s -`），输出路径。
- `Info.plist`：bundle id `com.liyitong.dsh-status`、`LSUIElement` true、`LSMinimumSystemVersion` 13.0、
  `CFBundleShortVersionString` 0.1.0、`NSHumanReadableCopyright`。
- 异常宽容：bridge.json 缺失/损坏、SSE 断开、DSH 重启都不得崩溃。

## 6. 验收

1. `swift build -c release` 通过；`scripts/build-app.sh` 产出可启动的 .app。
2. `--render-previews` 产出 4 张预览图（图标三方案 × 状态矩阵、面板浅/深色）。
3. 连 mock 桥（`DSH_STATUS_BRIDGE_FILE=~/.dsh-status/bridge.mock.json`）时：
   图标数字/颜色随状态变化，面板分组正确，点行会 POST 命令并打开 DSH。
4. 断开 mock 后 6s 内进入未连接态；mock 恢复后自动重连。

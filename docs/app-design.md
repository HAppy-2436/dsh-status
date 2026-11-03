# App 设计规范（v2 · 单圆形图标）

> 实现进度（2026-11-03）：**P0 已实现**（`app/`），预览见 `docs/previews/`。
> v2 变更：按用户反馈，所有信息收进**一个圆形**，不再横向拼接多个元素；深色模式优先调校。

面向 `app/` 的 Swift 菜单栏 App。图标设计是重点，需产出可评审的预览图。

## 1. 定位

- 纯菜单栏 App（`LSUIElement = true`），无 Dock 图标、无主窗口。
- 单击状态栏图标 → 打开/关闭 NSPopover 面板；再次单击关闭。
- 面板里点击会话行 → 跳转到 DSH 对应会话（发命令 + `open "dsh://open"`）。
- 不显示空闲会话；显示 待回答 / 运行中 / 已完成 / 已停止 四类。

## 2. 菜单栏图标（单圆形徽标）

### 2.1 设计原则

- **一个圆**：全部信息在一个 22×22 的圆形区域内表达，菜单栏占位紧凑（不横向拼接）。
- **三层信息**：数字（多少）→ 颜色（为什么）→ 外圈蓝弧（是否在跑）。
- **深色优先**：渐变填充 + 顶部柔光 + 细白描边，在深色菜单栏上有质感但不喧宾夺主。
- **零持续动画**：只用静态图形表达运行状态（省电、低调）。

### 2.2 几何（单位 pt，2x 渲染）

- 画布 22×22；圆盘直径 17.5（半径 8.75），居中。
- 外圈运行弧半径 9.7、线宽 1.7、圆头，弧段 −62°→28°（约 90°）。
- 数字：SF Rounded Bold；1 位 10.6pt / 2 位 9.4pt / 3 位（`99+`）7.9pt；居中略上移 0.3pt，
  带 1.2pt 柔和阴影。
- 不做 template image：颜色本身承载状态，按 `NSStatusItem.button.effectiveAppearance` 解析深浅色。

### 2.3 状态表达

| 情况 | 圆内 | 圆环 | 颜色 |
| --- | --- | --- | --- |
| 空闲 | 小鱼（outline，低对比） | 细灰环 | labelColor 30–34% |
| 运行中（无关注） | 三根等化器竖条 | 蓝底环 + 亮蓝弧 | 蓝 |
| 待回答（count>0） | 白字数字 | 彩色渐变圆盘 + 柔光 | **红**（最高优先） |
| 已停止（count>0） | 白字数字 | 彩色渐变圆盘 | 橙 |
| 已完成（count>0） | 白字数字 | 彩色渐变圆盘 | 绿 |
| 关注 + 运行 | 白字数字 | 彩色圆盘 + 外圈**蓝**弧 | 圆盘色 + 蓝弧 |
| 未连接 | 短横线 | 灰虚线环 | labelColor 26–30% |

- 数字 = 待回答 + 已完成 + 已停止；运行中**不计入**数字。
- 圆盘颜色优先级：待回答 > 已停止 > 已完成。
- 每秒级状态变化不影响图标尺寸（22×22 恒定），避免菜单栏抖动。
- Tooltip / accessibilityLabel：`DSH：1 待回答 · 2 运行中 · 1 已完成`。

### 2.4 两个变体（右键菜单可切换，默认 disc）

- **disc（推荐）**：有数字时填充渐变圆盘，视觉重量最足、数字最清楚。
- **ring**：不填充，用 2.1pt 彩色圆环 + labelColor 数字，更轻盈，适合浅色菜单栏。

### 2.5 深色调色板（浅色模式自动换深一档）

| 状态 | 渐变（上→下） | 环/弧 |
| --- | --- | --- |
| 待回答 | `#FF6A5E → #C81A12` | `#FF7B72` |
| 已停止 | `#FFBE52 → #C25C00` | `#FFC46B` |
| 已完成 | `#45E07A → #12813D` | `#5CEB8C` |
| 运行中 | `#6FB8FF → #0A5AC2` | `#4DA3FF` |
| 空闲/未连接 | — | labelColor 26–34% |

- 圆盘顶部加白色 11% 高光；描边白色 20%（深色）/ 深色同色系（浅色）。
- 运行时外圈弧**永远用蓝色**，与关注色互不干扰（混合状态一眼看出「有未读 + 还在跑」）。

## 3. 面板（NSPopover）

- 宽 344pt；内容 SwiftUI（`NSHostingController`）。
- header（高 46）：26pt 圆形鱼标 + 「DSH 会话」13pt semibold +「DeepSeek Harness」10pt 三级；
  右侧状态胶囊（绿点+实时 / 橙点+未连接）。
- 分组（有内容才显示）：待回答（红）、运行中（蓝）、已完成（绿）、已停止（橙）。
  - 分组标题：11pt semibold secondary + 右侧计数小胶囊。
  - 行高 46：左侧状态点（15pt 半透明底 + 6.5pt 实心点）；主标题 12.5pt medium；
    副标题 10.5pt secondary（`项目名 · 待回答摘要` / `项目名 · 已运行 2:14` / `项目名 · 3 分钟前`）。
  - 待回答行带红色 6% 背景强调；hover 背景圆角 8；点击整行生效。
- 空状态：44pt 圆形底 + sparkles 图标 +「全部空闲 / 没有需要关注的会话」。
- 未连接：橙点 +「DSH 未连接」+ 说明 +「打开 DSH」按钮。
- footer（高 44）：「打开 DSH」胶囊按钮；右侧两个 26pt 圆形图标按钮（通知开关、退出）。

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

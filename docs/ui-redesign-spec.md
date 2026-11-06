# 面板 / 设置窗口重设计规范（v1 · 2026-11-05）

> 目标：弹出面板与设置窗口做到与 **macOS 26/27（Liquid Glass）原生 UI 极致一致**。
> 依据：Apple HIG（macOS、Menu bar extras、Menus、Popovers、Panels、Settings、Materials/Liquid Glass、
> Color、Typography、Motion、Icons）+ WWDC25（Meet Liquid Glass / Build a macOS app / Adopting Liquid Glass）
> + 本机原生 UI 实测（见 `docs/research/macos-ui-conventions.md`，研究中，数值以其为最终仲裁）。
> 本文是唯一设计契约：实现与评审都以这里为准。

## 0. 总原则

1. **系统提供的东西不自己画**：能交给 SwiftUI/AppKit 原生控件与语义色（`labelColor` / `secondaryLabelColor` /
   `separatorColor` / system 状态色）的，不自造颜色和控件。
2. **颜色只表达状态**：界面文字一律语义色；彩色只出现在状态 glyph、设置页图标块、连接点。
3. **排版用系统字号**：13pt 正文行标题 / 11pt 次级说明；不出现 10pt 以下文字。
4. **间距走 2pt 网格**：面板外边距 14、行内边距 6、行高 44；设置页交给原生 grouped Form。
5. **动效克制**：只有出现/消失（≤0.12s 淡入）与 hover（≤0.1s）；尊重「减弱动态效果」。
6. **一致性优先于个性**：宁可少一点装饰，也不要出现系统里不存在的视觉语汇。

## 1. 设计 token（Theme.swift）

| 用途 | 值 |
| --- | --- |
| 面板宽度 | **330pt**（同 Status Trio） |
| 面板圆角 | **16pt** continuous（实测原生天气模块 ≈15–16pt） |
| 面板边距 | 水平 10pt（滚动容器）+ 行内 6pt = 文字距面板边 16pt（对齐原生天气模块） |
| 行高 | 会话行 **44pt**；子智能体行 **24pt**；footer **38pt** |
| 字号 | 行标题 13pt semibold；行副标题 11pt regular；footer 按钮 13pt 图标 |
| 图标 | 行首状态圆点 8pt（实心）；子智能体圆点 4pt；footer 按钮 13pt（24×24 命中区）；chevron 9pt semibold |
| 分隔线 | `separatorColor`（动态）；仅通知提示下方与 footer 上方各一条全宽 1px；设置卡片内分隔线从文字列开始 |
| hover 底色 | 主文字色 8%（深色）/ 6%（浅色），圆角 6pt，0.08s |
| 状态色 | `systemYellow`（待回答）/ `systemBlue`（运行中）/ `systemGreen`（已完成）/ `systemRed`（已停止）；
| | 未连接 = `secondaryLabelColor`（footer 连接点、空状态）；不使用自造 RGB（菜单栏图标除外，图标调色板保持现状） |
| 圆角 | 面板 16；行 hover 6；设置卡片/控件交给系统（约 10/6） |
| 阴影 | 面板用**系统窗口阴影**（`hasShadow`），不自绘阴影/内描边（会破坏 Liquid Glass 折射与高光） |

## 2. 弹出面板（StatusPanelView + StatusPanelController）

### 2.1 结构（自上而下）

```
┌ 内容（滚动，最大高度 480，随屏幕收缩）──┤  无 header，打开面板直接是会话列表
│  ● 会话行（44）                          │  行首 8pt 状态圆点 + 13 semibold 标题 + 11 secondary 副标题 + 10 chevron
│    ▸ 子智能体行（24，默认折叠）            │  leading 38，4pt 状态圆点 + 11pt secondary（点行首披露三角展开）
├ footer 38px ─────────────────────────────┤  左：7pt 连接状态圆点（无文字，hover 有 tooltip）
└──────────────────────────────────────────┘  右：设置 / 勿扰（月亮）/ 退出（电源）13pt 图标按钮（24×24 命中区）
```

- 会话不分组：按 `since`（进入当前状态时刻）倒序，最近一次状态变化在最上；圆点颜色 = 状态。
- 空状态：高 164；鲸鱼 24pt tertiary + 「全部空闲」13 semibold + 「没有需要关注的会话」11 secondary + 「打开 DSH」按钮。
- 未连接：高 168；`exclamationmark.circle` 16pt secondary + 「DSH 未连接」13 semibold + 11 secondary 说明 +
  原生 bordered 小按钮「打开 DSH」。
- 通知提示整行可点，点击行为保持：未决定 → 请求授权；已拒绝 → 打开系统设置通知面板。

### 2.2 视觉与交互

- 会话行：行首 8pt 实心状态圆点（`systemYellow`/`systemBlue`/`systemGreen`/`systemRed`），
  标题 13 semibold `labelColor`，副标题 11 regular `secondaryLabelColor`；
  trailing `chevron.right` 9pt semibold `tertiaryLabelColor`（提示「点击打开会话」）。
- 行 hover 仅底色（圆角 6，0.08s）+ 指针；整行可点，命中区覆盖行宽；hover 时不改变文字颜色。
- 子智能体行：**默认折叠**；父行最左侧 18pt Finder 风格披露三角（独立命中区）负责展开/收起，
  点行其余区域仍然打开会话；展开后子行缩进 38pt、4pt 状态圆点、11pt secondary；点击打开父会话；
  不计入统计/角标。展开/收起后由 `AppModel.onPanelLayoutChange` 请求面板重新适配高度。
- 「打开 DSH」：有会话时**不显示**；连接正常但无会话 / 未连接时，在空状态居中给原生 bordered 按钮。
- footer：左连接状态点（7pt，绿=已连接 / 灰=未连接，无文字，hover 显示 tooltip）；
  右侧 设置（gearshape）、勿扰（`moon` / `moon.fill`，开启时用系统强调色）、退出（power，二次确认）三个图标按钮；
  图标按钮 24×24 命中区、hover 底色圆角 5；除勿扰开启态外不用彩色。
- 面板出现/关闭：**0.06s ease-out 淡入 / 0.12s ease-in 淡出**（Reduce Motion 时瞬时）；
  关闭时先淡出再关窗，内容高度变化不打断交互。
- 面板打开期间状态项显示**系统原生高亮**：不再自绘；用一个 1×1、alpha=0 的 `NSPopover`
  （`.applicationDefined`）锚定状态项按钮来触发系统高亮，面板关闭时关闭该 popover。
- 玻璃与内容同处一个 key 窗口（原生液态玻璃渲染），阴影用系统窗口阴影（`hasShadow`）。
- 键盘：Esc 关闭；点击外部关闭（含本 App 其它窗口）；再次点状态项关闭。逻辑保持现有实现，
  仅把 footer 按钮改为整块可点区域（避免点不中）。

### 2.3 面板窗口（StatusPanelController）

- 保持自定义 `NSPanel`（无箭头、`.statusBar` 层级、跨 Space、非激活面板但 `makeKey` 保证 active 渲染），
  圆角 16pt；材质三档保持：Liquid Glass（`NSGlassEffectView`，macOS 26+）/ 经典磨砂（`.popover`）/ 实色；
  「降低透明度」→ 实色。
- 面板材质直接采用开源 **Status Trio**（Apache-2.0）的实现：`NSGlassEffectView(style: .regular)` **不设 tint**、
  系统窗口阴影、16pt 圆角；内容宿主放在 `glass.contentView` 内（避免玻璃直接接管 SwiftUI 的 intrinsic size）。
  **不要再给玻璃加 tint / 自绘阴影 / 内描边**：那会破坏液态玻璃的折射与高光，且容易出现"实色卡片/粗描边"。
- 定位：顶边贴住菜单栏下沿（0 间隙）；左缘对齐状态项高亮左缘（按钮左缘 - 2pt）；
  屏幕可见区域夹取（左右 8pt、底部 8pt）；高度随内容。
- 阴影用系统窗口阴影，不额外自绘。

## 3. 设置窗口（SettingsView + SettingsWindowController）

### 3.1 窗口 chrome（与系统设置窗口一致）

- 标准 `NSWindow`：`[.titled, .closable, .miniaturizable, .resizable]`，标题 **「DSH Status 设置」**；
  不用自定义 footer 栏、不加自定义标题栏按钮。
- 默认内容尺寸 **540 × 640**，`minSize 500 × 480`，可缩放；`setFrameAutosaveName("DSHStatusSettings")`
  记住大小/位置；首次打开居中；关闭不退出 App，再次打开复用同一窗口。
- 打开时 `NSApp.activate` + `makeKeyAndOrderFront`；内容背景 `windowBackgroundColor`。

### 3.2 内容（macOS System Settings 风格）

- 用 SwiftUI **`Form` + `.formStyle(.grouped)`**（原生分组卡片、行高、分隔线缩进、分区标题），
  不自绘卡片背景/描边/分隔线。必要时通过 `.scrollContentBackground` 与内边距微调。
- 行：左侧 **24×24** continuous 圆角色块（系统状态色/中性色，白色 SF Symbol 12pt semibold）+ 标题 13pt +
  可选副标题 11pt secondary；右侧原生控件（`Toggle .switch` / `Picker .menu` / bordered 小按钮）。
- 分区（顺序即优先级）：

| 分区 | 行 | 控件 |
| --- | --- | --- |
| 菜单栏图标 | 中心数字 | Picker：全部任务 / 需要介入 / 与环色一致 / 不显示 |
| | 状态切换动效 | Switch |
| | 播放运行动画 | Switch（说明：关闭可省电，低电量/减弱动态效果自动关闭） |
| 显示 | 待回答 / 运行中 / 已完成 / 已停止 | Switch（副标题显示当前数量） |
| | 项目显示（逐项目） | Switch（无项目时显示「暂无已知项目（连接 DSH 后出现）」） |
| 通知 | 系统通知状态 | 状态文字 / 「允许通知」/「打开系统设置」按钮 |
| | 勿扰模式 | Switch（总开关：静音全部通知；下面三项保留） |
| | 待回答（推荐）/ 已完成 / 已停止 | Switch |
| 面板 | 材质 | Picker（液态玻璃 / 经典磨砂 / 实色；低版本自动隐藏液态玻璃） |
| 通用 | 退出前确认 | Switch |
| | （分区内）恢复所有设置… | bordered 小按钮 + NSAlert 二次确认 |
| 关于（脚注） | 版本 + 连接状态 | 11pt tertiary 居中脚注（不占独立分区卡片） |

- 删除旧底部固定栏（「恢复默认」按钮 + checkbox + 版本）与重复副标题
  （picker 行不再同时用副标题和控件显示同一个值，说明文字放分区脚注）。
- 所有设置项保持即时生效 + UserDefaults 持久化；`AppSettings` 公开 API 不变。
- **设置窗口底色必须显式**：内容 `#1F2024`（深）/`#F2F2F6`（浅）、卡片 `#26272B`/白、分隔线 `#303135`/`#E3E3E8`，
  不透明度 100%。不要依赖 `windowBackgroundColor`/系统材质（会被 Liquid Glass 环境按桌面/窗口激活态染色，
  导致「聚焦偏蓝、失焦中性」两种观感）；窗口 `isOpaque = true`、`backgroundColor` 同内容底色。

## 4. 不做（本轮范围外）

- 不重做菜单栏图标绘制（用户对图标满意；图标建议见 `docs/icon-suggestions.md`）。
- 不引入第三方 UI 依赖；不改桥协议；不改通知逻辑。
- 不新增「关于」独立窗口 / 不引入侧边栏多面板结构（单页 grouped Form 已足够，符合小型工具 App 的 HIG 模式）。

## 5. 与原生实测的对齐（2026-11-05 复核）

原生实测数据见 `docs/research/macos-ui-conventions.md`，本规范采纳/保留的差异：

| 项 | 原生实测 | 本 App | 说明 |
| --- | --- | --- | --- |
| 弹出面板内边距 | 12pt | 12pt | 已对齐（滚动容器 6 + 行内 6） |
| 面板行高 | 菜单项 24 / 设置行 38–48 | 会话行 44 / 子行 24 | 双行列表用 44pt 更接近原生「Now Playing」类列表；不套用菜单项 24 |
| 面板行首状态点 | 8pt 实心圆 | 8pt 实心圆 | 与菜单栏/控制中心的状态点尺寸一致 |
| 设置窗口结构 | 工具栏 52 + 侧边栏 pane | 标准 titlebar + 单页 grouped Form | 单页设置内容量不足以拆分 pane；保留原生 Form（系统自带行高 48/图标 24/开关尺寸） |
| 设置行图标 | 24×24 | 24×24 | 已对齐 |
| 窗口标题 | 「设置」 | 「DSH Status 设置」 | 保留 App 名，避免与系统设置混淆（原生 App 亦常用「<App> Settings」） |
| 面板材质设置 | HIG 不建议 app 专属外观设置 | 保留（液态玻璃/磨砂/实色） | 属兼容/可读性选项，且系统「降低透明度」优先；在 app-design.md 标注取舍 |

## 6. 验收

1. `cd app && swift build -c release` 0 error/warning（新增 warning 需说明）。
2. `--render-previews` 正常出图：面板四态（默认折叠 / 展开子智能体 / 全部空闲 / 未连接，深/浅）、设置页（深/浅），
   无排版溢出/截断。
3. 真机截图：面板在彩色壁纸上深色模式观感与 Control Center 同代；设置窗口为标准 titlebar + 原生分组样式，
   不出现自定义底栏/自绘描边。
4. 交互回归：点击会话行跳转、Esc/外部点击关闭、通知提示、子智能体默认折叠/展开且面板高度自适应、
   footer 状态点/设置/勿扰/退出、
   设置项即时生效、重置确认、窗口大小记忆。

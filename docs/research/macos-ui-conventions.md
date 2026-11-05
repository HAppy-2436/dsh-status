# macOS（Liquid Glass 时代）原生 UI 规范调研与实测

> 目的：为 dsh-status 的「菜单栏弹出面板」与「设置窗口」重设计提供**可直接落地**的数值与规则。
> 实测环境：macOS 27.2（Build 26B123）、Apple M5、内置 Liquid Retina（逻辑 1280×832，2x）。
> 实测时间：2026-11-05。截图证据全部在 `docs/research/shots/`。
> 说明：**HIG 文档值** 与 **本机实测值** 可能不同（Liquid Glass 改版后部分文档滞后），下文两者并列，冲突时以实测为准并标注。

---

## 0. 结论速览（10 条最可直接使用的数值）

| # | 结论 | 数值 |
|---|------|------|
| 1 | 菜单栏高度 | **29 pt**（实测；HIG 文字仍写 24 pt）。菜单栏右侧状态项点击区高 **24 pt**，垂直居中（y=2.5） |
| 2 | 菜单栏标题字号/内边距 | **13 pt**；每个菜单项左右内边距 **10 pt**、高 29 pt（Apple 项 34 pt 宽、两字中文项 46 pt） |
| 3 | 原生下拉菜单 | 菜单项高 **24 pt**、圆角 **≈13.5 pt**、上下内边距 **5 pt**、分组分隔线占 **11 pt**、字号 13 pt、宽度随内容（实测 181.5 pt） |
| 4 | 菜单栏弹出面板（Control Center） | 内边距 **12 pt**、模块间距 **12 pt**、小模块 **64×64**、宽模块 **140×64**、跨列 **292×64**、底部按钮 **68×24** |
| 5 | 设置窗口骨架 | 工具栏高 **52 pt**、侧边栏宽 **232 pt**、内容区左右内边距 **20 pt**、内容卡片宽 = 内容区 −40 pt（实测 468 pt）、卡片间距 **10 pt** |
| 6 | 设置卡片/行 | 卡片圆角 **≈12 pt**、卡片背景 elevated、行高：**图标行 48 pt / 纯文字行 38 pt**、行内左右内边距 **10–12 pt**、分隔线左右内缩 **10 pt**、行尾 chevron 5×9 pt、右内缩 11 pt |
| 7 | 控件尺寸 | 开关 **36×16 pt**、弹出按钮高 **24 pt**、窗口红绿灯 **16×16 pt**（距窗口左上各 18 pt）、侧边栏图标 **20×20**、设置行图标 **24×24**、工具栏分段按钮 **36×36** |
| 8 | 字号层级 | 设置页标题 **26 pt**、副标题/描述 **12 pt**、行标题 **13 pt**、次要说明 **11 pt**、侧边栏 13 pt、工具栏标题 13 pt semibold、面板标题 13 pt semibold |
| 9 | 深色模式色板（实测） | 内容底 `#1F2024`、卡片/工具栏 `#26272B`、侧边栏 `#242631`、侧边栏选中 `#32343F`、分隔线 `#303135`、强调蓝（开关）`#397AF5` |
| 10 | 圆角/材质 | 窗口圆角 ≈17 pt、菜单 13.5 pt、卡片 12 pt；弹出面板用 **Liquid Glass（regular）**、半透明、无箭头；菜单为玻璃半透明（捕获 α≈71%） |

---

## 1. 调研来源与方法

### 1.1 一手资料（Apple HIG，2025-09-09 更新 Liquid Glass 版）

| 主题 | URL |
|---|---|
| Designing for macOS | https://developer.apple.com/design/human-interface-guidelines/designing-for-macos |
| The menu bar（含 Menu bar extras 章节） | https://developer.apple.com/design/human-interface-guidelines/the-menu-bar |
| Menus | https://developer.apple.com/design/human-interface-guidelines/menus |
| Popovers | https://developer.apple.com/design/human-interface-guidelines/popovers |
| Panels | https://developer.apple.com/design/human-interface-guidelines/panels |
| Settings | https://developer.apple.com/design/human-interface-guidelines/settings |
| Materials（含 Liquid Glass 章节） | https://developer.apple.com/design/human-interface-guidelines/materials |
| Color | https://developer.apple.com/design/human-interface-guidelines/color |
| Typography | https://developer.apple.com/design/human-interface-guidelines/typography |
| Motion | https://developer.apple.com/design/human-interface-guidelines/motion |
| App icons | https://developer.apple.com/design/human-interface-guidelines/app-icons |
| SF Symbols | https://developer.apple.com/design/human-interface-guidelines/sf-symbols |
| Icons | https://developer.apple.com/design/human-interface-guidelines/icons |
| Windows | https://developer.apple.com/design/human-interface-guidelines/windows |
| Toolbars | https://developer.apple.com/design/human-interface-guidelines/toolbars |
| Dark Mode | https://developer.apple.com/design/human-interface-guidelines/dark-mode |
| Toggles | https://developer.apple.com/design/human-interface-guidelines/toggles |

### 1.2 WWDC session（标题/摘要已核对，均为 Apple 官方索引页）

- **WWDC25-219 Meet Liquid Glass** — https://developer.apple.com/videos/play/wwdc2025/219/
- **WWDC25-356 Get to know the new design system** — https://developer.apple.com/videos/play/wwdc2025/356/
  （官方摘要：*"Dive deeper into the new design system to explore key changes to visual design, information architecture, and core system components… dynamic, harmonious, and consistent across devices, screen sizes, and input modes."*）
- **WWDC25-310 Build an AppKit app with the new design** — https://developer.apple.com/videos/play/wwdc2025/310/
- **WWDC25-361 Create icons with Icon Composer** — https://developer.apple.com/videos/play/wwdc2025/361/
- **WWDC25-220 Say hello to the new look of app icons** — https://developer.apple.com/videos/play/wwdc2025/220/
- **WWDC26-250 Principles of great design** — https://developer.apple.com/videos/play/wwdc2026/250/
- **WWDC26-289 Modernize your AppKit app** — https://developer.apple.com/videos/play/wwdc2026/289/
- **WWDC26-269 What's new in SwiftUI** — https://developer.apple.com/videos/play/wwdc2026/269/

> 限制：本次只抓到了 session 索引、标题、摘要与章节（字幕正文未抓取，且没有逐帧录像），
> 因此「动效时长」类结论主要来自 HIG 原则 + 本机观感估算，已在文中标注。

### 1.3 本机实测方法

- 截图：`screencapture -x`（全屏 2560×1664 px = 1280×832 pt @2x）、`screencapture -l <windowid> -o`（按窗口，含 alpha 通道）。
- 窗口 ID/层级：自写 `CGWindowListCopyWindowInfo` 工具。
- 控件精确几何：自写 Accessibility（AXUIElement）工具，读取 AX 元素的 position/size（**单位即 pt**）。
- 像素测量：Pillow 读取截图，`pt = px / 2`；圆角用 alpha/颜色边界做圆拟合；颜色取区域中位数。
- 菜单/面板测量均使用**网格标注放大图**（`shots/*-annotated.png`），可复核。
- 浅色模式未测（按任务约束不切换系统外观）；所有颜色均为**深色模式**实测值。

---

## 2. 本机实测数值表

### 2.1 菜单栏（Menu bar）

| 项目 | 实测值 | 依据/备注 |
|---|---|---|
| 菜单栏总高 | **29 pt**（全宽 1280） | WindowServer "Menubar" 窗口 `(0,0,1280,29)`；`AXMenuBar` frame 1280×29 |
| HIG 文档值 | 24 pt（the-menu-bar："The menu bar's height is 24 pt."） | 文档滞后于 macOS 26/27 Liquid Glass 改版；实现以 29 pt 为准 |
| 菜单标题项高 | 29 pt | AX：Apple `(10,0,34×29)`、系统设置 `(43,0,73×29)`、编辑 `(115,0,46×29)`、显示/窗口/帮助 47×29 |
| 菜单项水平内边距 | 10 pt/侧 | 两字中文菜单项 46 pt 宽 = 2×13 + 20；Apple 34 pt |
| 菜单标题字号 | 13 pt | 菜单栏文字 ink 高 11.5 pt（CJK），时钟数字 ink 高 11 pt |
| 状态项（menu bar extra）点击区 | **24 pt 高**，y=2.5；宽随内容 34–68.5 pt | AX：哔哩哔哩 34、DSH Status 40、微信 40、天气 68.5、Status Trio 39 |
| 状态项图标视觉尺寸 | 16–20 pt | 像素 bbox：哔哩哔哩 16×15、微信 20×16、Control Center 13×13、DSH 数字环 12×13 |
| 状态项间距 | 相邻点击区间距约 12–16 pt（视觉） | 项 pitch 32–40 pt（如 852→884→922→960） |
| 右侧顺序 | …app 状态项 → 控制中心（26 pt 点击区）→ 时钟区（145 pt） | AX MenuBarAgent 分组 `(1073,0,26×29)`、`(1112,0,145×29)` |
| 菜单栏文字颜色 | 白色（模板渲染，系统自动适配深浅/选中） | HIG：状态项用 black+clear 模板图，系统重着色 |

### 2.2 原生下拉菜单（System Settings「编辑」菜单，深色）

| 项目 | 实测值 | 备注 |
|---|---|---|
| 菜单视觉尺寸 | **181.5 × 271.5 pt** | 窗口含阴影 331×422 pt；内容由 alpha 拟合 |
| 圆角 | **≈13.5 pt**（alpha 圆拟合 27 px @2x，±1） | `shots/native-edit-menu-window.png` |
| 菜单项行高 | **24 pt** | 10 项文本行中心：47/71、106/130/154/178/202、237/261/285（pt） |
| 分组分隔线占用 | **11 pt**（行中心间距 35 = 24 + 11） | 分隔线左右内缩约 12 pt |
| 上下内边距 | 上 **5 pt**、下 **4.5 pt** | 内容顶 30 pt，首行中心 47（24 高 → 行顶 35） |
| 字号 | **13 pt**（CJK ink 11 pt） | 快捷键同 13 pt，次要色 |
| 文本左内边距 | 约 **18 pt**（含图标/勾选列） | 估算（文本 ink 从 x=128 起，菜单左缘 109.5） |
| 快捷键右内边距 | 约 **12 pt** | 估算 |
| 出现位置 | 紧贴菜单栏下沿（y=30，菜单栏 29 → 1 pt 间隙）；左缘与菜单标题左缘基本对齐 | 实测菜单左缘 109.5 vs 「编辑」项 115（差值为玻璃边缘/AA） |
| 材质 | Liquid Glass 半透明（捕获 alpha ≈ 181/255 ≈ 71%） | 深色模式捕获底色 RGB(32,32,32)；实际显示会透出桌面 |

### 2.3 菜单栏弹出面板：Control Center（macOS 27 原生）

| 项目 | 实测值 | 备注 |
|---|---|---|
| 面板位置/尺寸 | 右上角；上沿 y≈29（菜单栏下），右缘距屏幕右边≈2 pt；内容区约 **316×584 pt** | AX 模块网格 974..1266 × 41..601，四边内边距 12 pt 推算 |
| 面板内边距 | **12 pt** | 模块起点 974 = 面板左 962 + 12 |
| 模块间距 | **12 pt**（行/列同） | 列 x：974/1050/1126/1202；行 y：41/117/193/269/345/421/497 |
| 模块尺寸 | 小 **64×64**；宽 **140×64**；跨两列 **292×64**；方形大模块 **140×140** | AX 精确 frame |
| 模块圆角 | 高 64 的模块为胶囊（r=32）；140×140 模块 r≈28–32（估算） | 像素观察 |
| 模块内图标 | 圆形图标直径 **48 pt**（Wi-Fi 白圆 48×42 bbox） | 像素 bbox abs(992,48) |
| 滑块 | 轨高 14 pt；长度 80.5 / 204 / 217.5 pt | AX |
| 底部按钮「编辑控制」 | **68×24 pt**，距最后模块 16 pt | AX `(1086,577 68×24)` |
| 面板外圆角 | **未精确测得**（玻璃透明、窗口 alpha 为矩形）；视觉估算 **≈26–30 pt** | 见 `shots/control-center-*.png`；标注「估算/未完成」 |
| 材质 | Liquid Glass，无箭头（非 NSPopover 箭头样式），背景实时模糊 | 深/浅背景均保持可读 |

### 2.4 菜单栏弹出面板：天气（WeatherMenu，原生）

| 项目 | 实测值 | 备注 |
|---|---|---|
| 面板视觉尺寸 | **301 × 396 pt** | 窗口含阴影 332×804 pt；内容 alpha 矩形 958.5..1259.5 × 28..424 |
| 位置 | 紧贴菜单栏下（y≈28），距屏幕右缘 ≈20 pt | 与触发图标水平居中 |
| 圆角 | **估算 ≈12–14 pt**（放大截图目测，无法 alpha 拟合） | `shots/weather-popover-window.png` |
| 内边距 | 估算 ≈16 pt | 内容距面板边 |
| 材质 | Liquid Glass、无箭头 | 天气内容为深色半透明 |

### 2.5 System Settings 窗口（深色，740×803）

| 项目 | 实测值 | 依据 |
|---|---|---|
| 窗口尺寸 | **740 × 803 pt**（屏幕可见高 803） | CGWindowList + AX |
| 窗口圆角 | **≈17 pt**（alpha 拟合 34.5 px @2x，±1） | `shots/system-settings-general-window.png` |
| 工具栏高 | **52 pt** | AXToolbar `(270,29 740×52)` |
| 红绿灯 | 每个 **16×16 pt**；位置 (288,47)/(311,47)/(334,47) → 距窗口左/上各 18 pt | AX |
| 工具栏分段按钮（后退/前进） | **73×36 pt**（每段 36×36），距内容左缘 8 pt、距工具栏顶 8 pt | AX |
| 窗口标题 | 居中，**13 pt semibold**（ink 高 14 pt，6 字宽 83 pt） | 像素测量 |
| 侧边栏宽 | **232 pt**（内容区 508 pt；分隔线 x=501.5，0.5 pt 发丝线） | AX |
| 侧边栏搜索框 | **212×28 pt**，距侧边栏左/右各 10 pt，y=90 | AX |
| 侧边栏行 | 行高 **32 pt**；cell 左右内缩 **10 pt**（212 宽）；图标 **20×20 pt**；文字 13 pt | AX + 像素 |
| 侧边栏选中行 | 背景 `#32343F`，圆角 ≈10–15 pt（连续圆角拟合 15，估算取 10–12） | 像素拟合 |
| 侧边栏背景 | `#242631`（带壁纸色调的深蓝灰） | 区域中位数 |
| 内容区左右内边距 | **20 pt**（内容区 502..1010；卡片 522..990） | AX |
| 内容卡片宽 | **468 pt** | AX |
| 卡片间距 | **10 pt** | AX 卡片 y：119/198/359/564/663.5… |
| 卡片圆角 | **≈12 pt**（像素边界拟合 11.5–12） | `shots/system-settings-card-annotated.png` |
| 卡片背景 | `#26272B`；内容区底 `#1F2024`；无描边（靠 elevated 层级区分） | 像素中位数 |
| 行高（带图标行） | **48 pt**；图标 **24×24**，图标左内缩 12.5 pt，图标→文字间距 13 pt | AX + 像素 |
| 行高（纯文字行） | **38 pt**；文字左内缩 **10 pt** | AX 行文本 y 间距 38.2 |
| 行分隔线 | 1 px，`≈#303135`，**左右各内缩 10 pt** | 像素扫描（divider 532..979.5，卡片 522..990） |
| 行尾 chevron | **≈5×9 pt**，距卡片右缘 11 pt | 像素 ink bbox |
| 开关 | **36×16 pt**（AX 与像素一致）；开启色 `#397AF5`（≈系统强调蓝） | AXCheckBox/AXSwitch |
| 弹出按钮 | 高 **24 pt**，透明背景（仅文字+上下箭头），右内缩 10 pt | AXPopUpButton |
| 字号 | 标题 **26 pt**（"通用" ink 50.5×25）；描述 **12 pt**；行标题 **13 pt**（行高 16）；次要说明 **11 pt**（行高 14） | AX 行高 + 像素 ink |
| 头部卡片 | 468×147 pt，内容居中：图标 50×50（估算 48–50）、标题 26、描述 12 secondary | AX + 像素 |
| 深色分层 | base `#1F2024` < elevated（卡片/工具栏 `#26272B`）< 侧边栏 `#242631` | HIG dark-mode：base/elevated 两套背景 |

### 2.6 颜色 token（深色模式实测）

| Token | 实测 RGB | Hex | 用途 |
|---|---|---|---|
| 内容背景 | 31,32,36 | `#1F2024` | 设置窗口内容区底 |
| 卡片/工具栏 | 38,39,43 | `#26272B` | 分组卡片、工具栏 |
| 侧边栏 | 36,38,49 | `#242631` | 侧边栏（受壁纸色调影响） |
| 侧边栏选中 | 50,52,63 | `#32343F` | 选中行 |
| 分隔线 | 48,49,53 | `#303135` | 行分隔线 |
| 强调蓝（开关开） | 57,122,245 | `#397AF5` | 系统强调色（深色） |
| 菜单玻璃（捕获） | 32,32,32 α≈71% | — | 原生菜单材质 |

> 文字颜色一律用**语义色**（`labelColor` / `secondaryLabelColor` / `tertiaryLabelColor`），HIG 明确要求；
> 上表仅为背景 token，不要用硬编码文字色。

---

## 3. 可直接落地的 HIG / WWDC 规则（带来源）

### 3.1 菜单栏与菜单栏图标（Menu bar extras）

来源：https://developer.apple.com/design/human-interface-guidelines/the-menu-bar （Menu bar extras 章节）

1. **用模板图（black + clear）**：图标只用黑色与透明定义形状，系统自动重着色，适配深/浅色菜单栏与选中态。
2. **菜单栏高 24 pt（文档）**；状态项点击区高 24 pt（本机实测：菜单栏 29 pt、状态项 24 pt）。
3. **点击菜单栏 extra 默认应显示 menu，而不是 popover**；"Unless the app functionality you want to expose is too complex for a menu, avoid presenting it in a popover."
   → dsh-status 的面板承载「会话列表 + 行内操作 + 状态说明」，属于"too complex for a menu"的例外；**必须同时保留右键菜单**（现状已有）作为兜底，并在文档中说明该例外。
4. **不要依赖状态项一定可见**（系统会因空间不足隐藏 extras）；提供 Dock 菜单/设置页等替代入口。
5. 菜单栏标题用**短词**（1 个词最佳）；中文两字项实测 46 pt 宽、左右内边距各 10 pt。
6. 菜单栏图标要**光学居中**（见 Icons 页：非对称图标用 padding 做光学对齐），图标与相邻文字/符号权重一致。

### 3.2 菜单（Menus）

来源：https://developer.apple.com/design/human-interface-guidelines/menus

- 菜单是**临时的、无箭头的玻璃浮层**；系统菜单项高 24 pt、字号 13 pt、上下内边距 5 pt（实测）。
- 菜单项用**熟悉的 SF Symbol** 表示动作（HIG the-menu-bar："Represent menu item actions with familiar icons"）。
- 分隔线用于分组，实测占 11 pt 高度、左右内缩约 12 pt。
- 菜单出现/消失无动画（系统即时呈现）——自定义弹出面板不要模仿菜单做动画，面板才有过渡。

### 3.3 弹出面板 / Popover / Panel

来源：https://developer.apple.com/design/human-interface-guidelines/popovers、`/panels`、`/materials`

1. Popover 只放**少量相关内容**；"Avoid making a popover too big. Make a popover only big enough to display its contents"。
2. 尺寸变化要**平滑动画**："Provide a smooth transition when changing the size of a popover"。
3. 不要在 popover 上再叠视图（alert 除外）。
4. macOS 的 popover 可以 detachable（拖出成 panel）；panel 需要**短标题**、比窗口更弱的视觉权重。
5. **Liquid Glass**：只用于**功能层**（controls/navigation），不要用在内容层；用系统组件自动获得材质；自定义控件要**克制**使用。
6. Liquid Glass 有两种变体：`regular`（默认）与 `clear`（用于媒体/视频等视觉丰富背景之上，需自行加 dimming 保证对比度）。
7. macOS 标准材质（`NSVisualEffectView`）用于内容层结构；用 **vibrant 语义色**保证材质上的可读性。

### 3.4 设置窗口（Settings）

来源：https://developer.apple.com/design/human-interface-guidelines/settings

1. 设置项从**App 菜单的「设置…」**进入；不要在窗口工具栏里放设置按钮。
2. macOS 自定义设置窗口**典型结构 = 工具栏 + 多个 pane**：工具栏是**不可自定义**的，且**始终指示当前 pane**。
3. 只放**不常改**的通用设置；任务级选项放回任务界面，不要塞进设置。
4. 不要重复系统全局设置（外观、滚动行为等）。
5. 本机实测（System Settings，可直接抄的结构）：
   - 工具栏 52 pt、窗口圆角 ≈17 pt、红绿灯 16×16（内边距 18）；
   - 侧边栏 232 pt、行高 32、搜索框 212×28；
   - 内容区左右边距 20 pt、卡片宽 = 内容宽 −40、卡片圆角 12、卡片间距 10；
   - 行高 48（带图标）/38（纯文字）、分隔线内缩 10、开关 36×16、弹出按钮 24 高；
   - 字号：标题 26 / 描述 12 / 行标题 13 / 次要 11。

### 3.5 材质、颜色、字体、动效

来源：`/materials`、`/color`、`/typography`、`/motion`、`/dark-mode`

- **材质**：功能层用 Liquid Glass；内容层用标准材质/不透明背景。深色模式用 **base/elevated** 两套背景表达层级（实测：`#1F2024` / `#26272B`）。
- **颜色**：用语义色（label/separator/control），必须同时适配浅色、深色、增强对比度；**不要提供 app 专属外观设置**（dark-mode 页明确："Avoid offering an app-specific appearance setting"）。
- **字体**：macOS 默认字号 **13 pt**，最小可读 **10 pt**；系统字体自动光学缩放；避免 Light/Thin 字重；文字层级用系统 text style。
- **动效**：短暂、精确、可关闭；必须尊重「减弱动态效果」；系统组件的动效会自动适配输入方式。
- **图标**：SF Symbols 与文字同权重；toolbar 用 outline 变体、tab/选中用 fill；用系统色自动适配。
- **工具栏**：不要自绘工具栏背景/着色；标准控件圆角要与工具栏圆角**同心（concentric）**。

### 3.6 应用图标（App icon）

来源：https://developer.apple.com/design/human-interface-guidelines/app-icons

- macOS 图标是**正方形分层图**，系统统一 mask 成圆角（与系统其他圆角同心）；**不要自己预切圆角**。
- 用 **Icon Composer** 分层（背景层 + 前景层），支持 Liquid Glass 高光/折射与 default/dark/mono 变体。
- 保持主体居中，避免细线/锐角（小尺寸会糊）。

---

## 4. 与 dsh-status 现状的差距清单

现状代码：`app/Sources/DSHStatusBar/{Theme,StatusPanelView,StatusPanelController,Settings}.swift`；
现状截图：`shots/dsh-panel-baseline.png`、`shots/dsh-settings-baseline.png`。

### P0 — 必须改（明显不像原生 / 结构错误）

| # | 现状 | 原生/依据 | 建议值 |
|---|---|---|---|
| P0-1 | 设置窗口是固定 470×780 的普通 titled 窗口，无工具栏、无侧边栏，页面自绘底栏 | HIG settings：设置窗口 = 工具栏 + pane；实测：工具栏 52 pt、窗口可缩放、标题居中 | 改为 `Settings` 窗口：`[.titled,.closable,.miniaturizable,.resizable]`，title「设置」，**工具栏 52 pt**（标题居中 + 可选 pane 切换），默认约 620×600、最小 560×480 |
| P0-2 | 设置页内容边距 14、分组间距 12、卡片圆角 10、无 elevated 卡片背景（`controlBackgroundColor` 近似） | 实测：内容边距 **20**、卡片间距 **10**、卡片圆角 **12**、卡片背景 = elevated | 边距 20 / 组间距 10 / 卡片圆角 12 / 卡片 `NSColor.controlBackgroundColor`→改用 elevated 语义背景（深色 `#26272B` 级） |
| P0-3 | 设置行：V padding 6 + 图标 26 → 行高约 38；分隔线内缩 52；图标 26×26 渐变 | 实测：图标行 **48**（图标 24×24、左右内边距 12/10）、分隔线内缩 **10**、图标用系统色（非渐变） | 行高 48（图标行）/38（纯文字行）；图标 24×24、圆角 6、系统图标色；分隔线左右内缩 10 |
| P0-4 | 开关 `.controlSize(.small)`（约 30×14） | 实测原生 **36×16** | 用 `.controlSize(.regular)`（或自定义 36×16），并确保右侧内边距 10 |
| P0-5 | 面板：宽 330、左右内边距 14、header/footer 40、行高 44、分隔线**通栏** | 实测：菜单栏弹出面板内边距 **12**、分隔线内缩 12、行高 32–38 | 面板宽 **320**、内边距 **12**、header/footer 36–40、会话行高 **38**（双行）/子行 32、分隔线左右缩进 12 |
| P0-6 | 分组标题 11.5 pt semibold secondary | 实测设置分组标题 **13 pt semibold**；面板 section header 11 pt semibold secondary | 设置分组标题 13 semibold；面板分组标题 11 semibold secondary |
| P0-7 | 设置窗口标题「DSH Status 设置」 | 原生设置窗口标题通常就是「设置」 | 改为「设置」（App 名由窗口所属 app 体现） |

### P1 — 建议改（观感不一致 / 违反 HIG 建议）

| # | 现状 | 原生/依据 | 建议值 |
|---|---|---|---|
| P1-1 | 面板分隔线通栏（`Divider().opacity(0.6)` 全宽） | 原生列表分隔线左右内缩 | 左右各内缩 12 pt（`padding(.horizontal, 12)`） |
| P1-2 | 行 hover 填充 5.5% 白、圆角 8 | 原生列表 hover ≈ 8–10% 白、圆角 6–8（估算） | 8% 白、圆角 8，保持 `.continuous` |
| P1-3 | 面板行标题用 `.headline`（13 semibold） | 原生列表主标题 13 regular，层级靠颜色/字号 | 行标题 13 regular，副标题 11 secondary；面板大标题 13 semibold |
| P1-4 | 卡片 1px 描边（白 7%） | 实测卡片无描边，靠 elevated 背景区分 | 去掉描边（或降到 4% 以下） |
| P1-5 | 提供「面板背景：液态玻璃/经典磨砂/实色」设置 | HIG dark-mode：避免 app 专属外观设置 | 移除该设置；保留「降低透明度」时自动退回实色（系统行为） |
| P1-6 | 底栏图标按钮 22×22 点击区、字号 13 | 原生工具栏按钮 36×36；macOS 最小点击目标建议 ≥24 | 点击区 24×24（视觉图标 13–15），间距 8 |
| P1-7 | 菜单栏图标自绘动画视图（22pt 级） | HIG：状态项用模板图、光学居中、点击区 24 高 | 保证绘制在 18×18 设计网格内、透明边距均匀、模板渲染；动画仅改图层不改变命中区域 |
| P1-8 | 设置页底栏自绘 44 pt（恢复默认/版本/连接状态） | 原生无自定义底栏；版本/状态应弱化 | 版本+连接状态放工具栏 trailing 或页脚 11 pt tertiary；「恢复默认」放页脚右侧 `.controlSize(.small)` |
| P1-9 | 面板空态/未连接态固定 132/148 高、字体 headline | 原生空态用 13 pt + 11 pt secondary，居中留白约 24 | 高度 120–132、标题 13 semibold、副标题 11 secondary |

### P2 — 可选（打磨）

| # | 现状 | 建议 |
|---|---|---|
| P2-1 | 面板圆角 20 pt | 保持 20（原生窗口 ≈17、菜单 13.5；大面板 20 合理，且与内容控件同心即可） |
| P2-2 | 面板出现 0.08 s 纯 alpha 淡入 | 改为 **0.18–0.22 s** 淡入 + 0.96→1.0 轻微缩放（ease-out）；关闭 0.12–0.15 s；Reduce Motion 时瞬时（现状已处理 Reduce Motion） |
| P2-3 | 面板阴影 `hasShadow` | 用系统默认即可；不要自绘大阴影 |
| P2-4 | 面板 header 里「实时/未连接」用 5 pt 圆点 | 原生状态点多用 6 pt；次要文字 11 pt secondary |
| P2-5 | 设置图标自定义渐变底 | 改用 SF Symbol + 系统多色（如 `folder.fill` 用系统蓝），与原生一致 |
| P2-6 | SF Symbols 用法 | toolbar/列表用 outline，选中/强调用 fill；权重与相邻文字一致 |
| P2-7 | 面板内容高度公式 44/22/30/52 硬编码 | 按新行高（38/32）重算，并给最大高度 520（保持） |
| P2-8 | 菜单栏弹出面板 vs HIG「优先 menu」 | 在 README/设计文档中说明面板例外理由，并保留右键菜单兜底（现状已有） |

---

## 5. 未完成 / 不确定点

1. **Control Center 面板外圆角**：Liquid Glass 透明窗口的 `screencapture -l` alpha 为矩形，无法圆拟合；视觉估算 ≈26–30 pt。证据：`shots/control-center-*.png`。标注「估算」。
2. **天气面板圆角/内边距**：只能从放大截图目测（≈12–14 pt / ≈16 pt），未做 alpha 拟合。证据：`shots/weather-popover-window.png`。
3. **面板出现/关闭动效时长**：无逐帧录制，只能给系统观感估算（0.18–0.22 s）；HIG 只给原则不给时长。
4. **浅色模式**：按约束未切换系统外观，颜色表仅深色模式；浅色模式需用语义色自动适配（实现上无风险）。
5. **菜单项文本左内边距（≈18 pt）** 为像素估算（含图标列），未用 AX 精确值。
6. **WWDC 字幕正文**未抓取（只拿到 session 标题/摘要/章节），规则引用以 HIG 一手页面为主。
7. **hover / pressed 态**无法静态截图测量，按系统观感估算。
8. System Settings 窗口尺寸 740×803 是「上次使用尺寸」记忆值，不代表新装默认值。

---

## 6. 截图证据清单（docs/research/shots/）

| 文件 | 内容 | 用途 |
|---|---|---|
| `menubar-right-8x.png` | 菜单栏右侧（哔哩哔哩/DSH/微信/天气/控制中心/时钟）放大 8x | 图标尺寸/间距/字号测量 |
| `menubar-system-settings-2x.png` | System Settings 菜单栏（Apple/系统设置/编辑/显示/窗口/帮助） | 菜单标题项尺寸测量 |
| `native-edit-menu-window.png` | 「编辑」菜单窗口（含 alpha） | 菜单圆角/行高/内边距/材质 |
| `native-edit-menu-annotated.png` | 同一菜单 10 pt 网格标注 | 可复核测量 |
| `control-center-window.png` | Control Center 窗口快照（含 alpha） | 模块/内边距测量 |
| `control-center-annotated.png` | Control Center 20 pt 网格标注 | 模块网格可复核 |
| `control-center-corner-zoom.png` | 面板左上角 12x | 圆角估算 |
| `weather-popover-window.png` | 天气弹出面板（窗口快照） | 面板尺寸/圆角/位置 |
| `system-settings-general-window.png` | System Settings「通用」窗口（740×803 @2x） | 窗口/工具栏/侧边栏/卡片/行/颜色 |

| `system-settings-card-annotated.png` | 内容卡片 10 pt 网格标注 | 卡片圆角/行高/图标可复核 |
| `dsh-panel-baseline.png` / `dsh-settings-baseline.png` | 现状面板/设置窗口 | 差距对照 |

---

## 7. 实现清单（给 Lead 的最小改动路径）

1. `Theme.swift`：新增 token（`contentBackground=#1F2024`、`elevated=#26272B`、`sidebar=#242631`、`selection=#32343F`、`separator=#303135`、`accent=#397AF5`）；圆角 `card=12`、`row=8`、`panel=20`；行高 `iconRow=48`、`textRow=38`、`panelRow=38`、`panelSubRow=32`；内边距 `settingsPage=20`、`panel=12`。
2. `Settings.swift`：窗口改为可缩放 + 工具栏 52；内容边距 20；卡片圆角 12、间距 10、无描边；行高 48/38、图标 24、分隔线内缩 10；开关 regular；移除「面板背景」设置（P1-5）。
3. `StatusPanelView.swift`：面板宽 320、内边距 12、行高 38/32、分隔线内缩 12、行标题 13 regular、副标题 11、分组标题 11 semibold、底栏按钮 24×24、出现动效 0.2 s。
4. `StatusPanelController.swift`：`AnchoredStatusPanel.cornerRadius` 保持 20；玻璃 `NSGlassEffectView` 保持；动效改为 alpha + scale（0.96→1.0，0.2 s ease-out），Reduce Motion 时瞬时。
5. `MenuBarIconRenderer.swift` / `StatusItemController.swift`：确认模板渲染 + 18×18 设计网格 + 光学居中 + 命中区 ≥24 pt。

---

*本文档由 hig-research（teammate）产出；所有实测值均可在 `shots/` 截图上复核，估算值已标注「估算」。*

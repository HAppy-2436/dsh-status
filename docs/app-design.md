# App 设计规范（v6 · 原生 macOS 26/27 视觉）

> 实现进度（2026-11-05）：**P0 可用，P1 插件已接通**（`app/`），预览见 `docs/previews/`。
> v6 变更：按 macOS 26/27（Liquid Glass）原生规范重做**弹出面板**与**设置窗口**；
> 图标系统保持 v5（鲸鱼 + 单色优先级环 + 运行中彗星弧）。
> 依据：本机原生 UI 实测 [docs/research/macos-ui-conventions.md](research/macos-ui-conventions.md)、
> 设计契约 [docs/ui-redesign-spec.md](ui-redesign-spec.md)；图标建议见 [docs/icon-suggestions.md](icon-suggestions.md)。
> Logo 资源取自 DSH 前端 `FISH_LOGO_PATH`（viewBox 23.16×17.04）。

面向 `app/` 的 Swift 菜单栏 App。图标设计是重点，需产出可评审的预览图。

## 1. 定位

- 纯菜单栏 App（`LSUIElement = true`），无 Dock 图标、无主窗口。
- 单击状态栏图标 → 打开/关闭自定义 NSPanel 面板；再次单击关闭（无箭头）。
- 面板里点击会话行 → 跳转到 DSH 对应会话（发命令 + `open "dsh://open"`）。
- 不显示空闲会话；显示 待回答 / 运行中 / 已完成 / 已停止 四类。
- **子智能体会话不计入统计**（`origin === 'subagent'` 或带父会话），也不发通知。
- **HIG 例外说明**：HIG 建议菜单栏 extra 默认弹出 menu 而非 popover；本 App 面板承载
  「会话列表 + 行内操作 + 连接状态」，属于 "too complex for a menu" 的例外，因此保留自定义面板，
  同时**保留右键原生菜单**（打开 DSH / 设置… / 退出）作为兜底入口。

## 2. 菜单栏图标（鲸鱼 + 单色优先级环，v5 不变）

### 2.1 设计原则

- **颜色只表达一件事**：当前有没有、以及最需要你介入的是什么。
- 同一时刻只有一种颜色，避免多色相邻产生的冲突（红绿互补、黄绿混浊）与视觉噪声。
- 形状保持稳定：外环永远是同一半径的整圈，只换颜色；运行时多一层内弧。

### 2.2 状态映射

| 情况 | 外环 | 内层 | 中心数字 |
| --- | --- | --- | --- |
| 完全空闲 | 无（显示鲸鱼 Logo） | — | — |
| 只有运行中 | 无 | 外环大小的动态弧 | 运行数 |
| 有已停止 | **红**（最高优先级） | 有运行时为内层动态弧 | 见设置 |
| 有待回答 | **黄**（高于绿） | 同上 | 见设置 |
| 只有已完成 | **绿** | 同上 | 见设置 |
| 未连接 | 灰色虚线环 + 短横 | — | — |

- 优先级**红(已停止) > 黄(待回答) > 绿(已完成)**，始终取当前最高的一项决定颜色。
- 数字语义（设置项「中心数字」）：
  - **全部任务数（默认）**：所有非空闲任务（含运行中）；
  - 需要介入的数量：待回答 + 已停止 + 已完成；
  - 与环颜色一致的数量：只数当前环色对应状态；
  - 不显示。
- 内外环同时存在时不显示数字（22pt 放不下第三层）。

### 2.3 动画（Core Animation，GPU）

- **运行中彗星弧**：常驻 `CAShapeLayer` + `CAKeyframeAnimation`，顺时针；
  6s 一个节奏周期转 3 圈（平均 2s/圈），速度按正弦 ±32% 平滑起伏（48 个采样关键帧，首尾整数圈无缝）；
  弧长 `strokeEnd` 0.26 ⇄ 0.58、1.7s 单程呼吸。状态推送不会重启旋转（签名只看影响视觉的字段）。
- **全状态切换动效**（2026-11-08，可关）：一次切换 = 内容交叉淡化（0.24s）+ 外环扫入/收回/换色（0.45s）
  + 数字里程表滚动（0.18s、≤2.4pt、不横移）+ 彗星淡入淡出/半径变形（0.18 / 0.45s）；同轨交接（外环 ↔ 彗星同半径）
  让退场方先走 0.18–0.30s；单次总时长 ≤0.60s，结束立刻落回完整静态帧。
  完整参数与 18 类迁移矩阵见 [icon-transitions.md](icon-transitions.md)，真机逐帧对照见
  [previews/icon-transition-dark.png](previews/icon-transition-dark.png)。
  调试：`--test-icon-transitions[=<起始步>,<步数>]` 脚本化回放全部迁移，`DSH_STATUS_ANIM_SCALE` 放慢倍数，
  `scripts/capture-icon-transitions.sh` 逐帧捕获。
- **v3 验收修复（2026-11-08）**：内容通道改为「不变原子公共静态层 + 变化原子交叉淡化」（相同像素不再被双图淡化压暗）；
  `>99` 同文本推送不再播过渡（100→101）；屏幕参数变化 / 状态项按钮重建强制落静态帧；`99+` 改 6.4pt + ink bbox 居中
  （旧实现压外环 1.9pt）。详见 [icon-audit.md](icon-audit.md)。
- 静态兜底：稳态 `button.image` 始终是完整静态帧（切换桌面/菜单栏重建不会闪黑块）；过渡期间用透明占位图保持状态项宽度，
  画面由临时图层合成，结束即恢复。动画只加在图层上，由 GPU 驱动，实测常驻 CPU 0.0%。
- 尊重「减弱动态效果」与低电量模式（自动降级静态）；设置页「状态切换动效 / 播放运行动画」可分别关闭。

### 2.4 资源

- 鲸鱼矢量路径来自 DSH 前端 `FISH_LOGO_PATH`（`WhaleLogo.swift` 内置 path 与 M/C/L/Z 解析器），
  不依赖外部图片，任何分辨率都清晰；面板 header / 空态复用同一路径（模板图片，随主题着色）。

## 3. 弹出面板（自定义 NSPanel，原生 popover 观感）

### 3.1 窗口与材质

- 不用 `NSPopover`：无边框 `NSPanel`（`.borderless + .nonactivatingPanel`），**没有 popover 箭头**，
  `.statusBar` 层级、跨 Space、不抢焦点；**16pt continuous 圆角**、系统窗口阴影。
- 材质（设置页「面板背景」可切，默认液态玻璃）：
  - macOS 26+：`NSGlassEffectView(style: .regular)`，**不设 tint**（保留原生折射/高光），
    内容宿主放在 `glass.contentView` 内的一层普通容器里；
  - 旧系统：`NSVisualEffectView(.popover)` 经典磨砂；
  - 显式选「实色」或系统开启「降低透明度」时用不透明填充。
- **几何**：圆角 16pt、内容左右内边距 14pt、面板宽度 330pt（同 Status Trio）；阴影用系统窗口阴影。
- **状态项高亮直接使用系统自带的绘制**（不再自绘）：系统只在两种情况下画原生高亮——
  鼠标按住状态项、或有 `NSPopover` 锚定在该状态项上。做法：打开面板时展示一个 **1×1、窗口 alpha=0 的
  `NSPopover`（`behavior = .applicationDefined`）**锚定到状态项按钮，系统就会按原生逻辑绘制高亮
  （尺寸/材质/圆角/深浅色全由系统决定）；面板关闭时 `performClose` 掉它。视觉上 popover 本体不可见。
- 定位：面板**顶边完全贴住菜单栏下沿**（无间隙），**左缘与状态项按下态高亮的左缘对齐**
  （= 按钮左缘 - 2pt，高亮 = item 宽 + 4）；按屏幕可见区域夹取（左右/底部 8pt）；宽度固定 **330pt**。
- 出现/关闭：**0.06s ease-out 淡入 / 0.12s ease-in 淡出**（Reduce Motion 时瞬时）；关闭时先淡出再真正关窗。
- 面板展示期间状态项图标显示**高亮胶囊**（与原生菜单栏项一致）。
- 关闭：再次点击状态项、点击面板外（含本 App 其它窗口）、**点击菜单栏其它图标/菜单**、Esc；
  关闭时面板淡出 0.12s 后真正关窗。

### 3.2 结构（自上而下）

```
┌ 内容（滚动，最大 480，随屏幕收缩）──────────┐  无 header：打开面板直接是会话列表
│  ● 会话行（44）                    ⌄ 2    │  行首 8pt 状态圆点 + 13pt semibold 标题
│    ▸ 子智能体行（24，默认折叠）            │  + 11pt secondary 副标题 + 行尾「数量 + 箭头」（无子会话为 ›）
│  ● 会话行（44）                           │  ← 不分组，按「最近一次状态变化（since）」倒序
├ footer 38 ────────────────────────────────┤  左：7pt 连接状态圆点（绿=已连接，灰=未连接）
└───────────────────────────────────────────┘  右：设置 / 勿扰 / 退出 13pt 图标按钮（24×24 命中区）
```

- 行首圆点：待回答 `systemYellow`、运行中 `systemBlue`、已完成 `systemGreen`、已停止 `systemRed`；
  8pt 实心圆，所有行（含无子会话的行）保持同一列。
- **圆角阶梯**：面板 16 → 行/整块 hover 高亮 **12** → 子行 8 → 行尾披露胶囊 5，全部 continuous 超椭圆曲线。
  严格「内层 = 外层 − 内边距」算出的是 8，但 8 在 44/52pt 高的行上偏硬、像「方中带圆」，
  按视觉偏好放大到 12（四角与外壳的缝隙比正中间略宽，观感更柔和）；上下内距与左右统一为 8。
- **动效**（`Theme.Motion`，全部尊重「减弱动态效果」）：行 hover 0.12s 底色渐显、按住再深一档且轻微下沉 1.5%；
  行尾按钮 hover 出现独立胶囊底色、按下更深；披露箭头 0.22s easeInOut 旋转 180°；
  子行 0.18s 淡入 + 4pt 上浮，逐条错开 0.035s；
  **面板高度动画只有窗口在动**：顶边钉住菜单栏，底边 0.22s easeInOut 向下/向上移动；
  SwiftUI 内容固定顶部对齐（`TopAlignedContentHost`）、按目标高度摆放，多出来的部分由窗口裁切逐步揭幕。
  早先「窗口一次变高 + 内容自己在 0.24s 里长高」是两套时间线，内容会被 SwiftUI 在窗口里垂直居中，
  展开时先被顶上再滑下来（观感就是「一会下一会上」），现已去掉内容侧高度动画。
  **高度动画由 60fps 的 `Timer` 逐帧 `setFrame(display: true)` 驱动**（`startHeightAnimation` /
  `stepHeightAnimation`，easeInOutQuad）：不用 `animator().setFrame` 是因为 AppKit 的窗口 frame 动画走
  「快照缩放」快路径，动画期间窗口内容与阴影是拉伸的位图，Liquid Glass 与圆角在这种非等比拉伸下会在左右两侧
  投出重影（观感＝左右抖动闪烁）；逐帧真实 resize 每帧都重新渲染，边缘干净。动画期间不移动窗口、不刷阴影，
  结束后统一 `positionPanel` + `invalidateShadow` 一次。
- 子智能体：默认折叠；**行尾**是导航/披露区：
  - 没有子会话 → `chevron.right`（9pt semibold tertiary），只作导航提示，点卡片任意位置打开会话；
  - 有子会话 → 「子智能体数量（11pt medium，等宽数字，secondary）+ `chevron.down`」按钮，独立命中区：
    点它展开/收起，点行其它区域仍打开会话；**展开时下箭头旋转 180° 成上箭头**（0.16s ease-out）；
  - 展开后子行缩进 18pt、11pt secondary、4pt 状态色圆点、行高 24，点击打开父会话；不计入统计。
  展开/收起后面板高度自动重新适配。
- hover / 按下：仅整行或整块底色（主文字色 8%/6%，12pt continuous 圆角，0.12s），不改变文字颜色。
- **空闲 / 未连接 = 一整块大按钮**（高 68 = 内距 8 + 内容 52 + 内距 8）：
  居中鲸鱼 22pt + 16pt semibold「全部空闲」（未连接时同位置显示灰色「未连接」），
  **点面板任意位置**都打开 DSH；hover / 按下底色铺满整块内容区。
  不再有副标题、「没有需要关注的会话」说明或额外的「打开 DSH」按钮——空闲时没有信息要读，面板越短越好。
- 通知未授权时，内容上方仍有一行 32pt 可点提示（未决定 → 请求授权；已拒绝 → 打开系统设置）。


## 4. 设置窗口（NSWindow + 原生 grouped Form）

### 4.1 窗口 chrome

- 标准 `NSWindow`：`[.titled, .closable, .miniaturizable, .resizable]`，标题「DSH Status 设置」。
- 默认内容尺寸 **540 × 640**，最小 **500 × 480**，可缩放；`setFrameAutosaveName("DSHStatusSettings")`
  记住大小/位置；首次打开居中；关闭不退出 App，再次打开复用同一窗口。
- 打开时 `NSApp.activate` + `makeKeyAndOrderFront`。
- **背景色为显式中性色板**（不透明度 100%）：深色内容 `#1F2024` / 卡片 `#26272B`、浅色内容 `#F2F2F6` / 卡片白，
  分隔线 `#303135` / `#E3E3E8`（取自 System Settings 实测值）。原因：直接用 `windowBackgroundColor` + SwiftUI grouped Form 的玻璃底会被
  Liquid Glass 环境（桌面壁纸/窗口激活态）染色——聚焦时卡片偏蓝、失焦时变中性，同一窗口两副面孔；
  固定为原生实测中性色后，**常态与失焦态一致**，与系统设置观感对齐。

### 4.2 内容

- SwiftUI **`Form` + `.formStyle(.grouped)`**：卡片背景、圆角、分隔线、分区标题、行高全部交给系统；
  不自绘卡片/描边/底栏。
- 行：左侧 **24×24** continuous 圆角色块（系统状态色 + 轻微渐变，白色 SF Symbol 12pt semibold）
  + 标题 13pt + 可选副标题 11pt secondary + Spacer + 原生控件（`Toggle .switch` / `Picker .menu` / bordered 小按钮）。
- 分区顺序：**菜单栏图标 → 显示 → 项目显示 → 通知 → 提示音 → 面板 → 后台 → 通用**；页脚为 11pt tertiary 版本/连接脚注。
- 分区说明文字为 11pt secondary、左对齐，位于卡片下方。

| 分区 | 设置 | 说明 |
| --- | --- | --- |
| 菜单栏图标 | 中心数字 | 全部任务数（默认）/ 需要介入 / 与环颜色一致 / 不显示 |
| | 状态切换动效 | 外环扫一圈 + 颜色渐变（默认开） |
| | 播放运行动画 | 关闭可省电；低电量 / 减弱动态效果自动关闭 |
| 显示 | 待回答 / 运行中 / 已完成 / 已停止 | 关掉的状态不在面板出现，也不进圆环与数字 |
| 项目显示 | 按 workspace 逐个开关 | 关掉即隐藏该项目（会话本身不受影响） |
| 通知 | 系统通知状态 | 已开启 / 允许通知 / 打开系统设置 |
| | 勿扰模式 | 总开关：静音全部系统通知**与提示音**（保留下面三项）；面板底部月亮同步 |
| | 待回答（推荐）/ 已完成 / 已停止 | 默认只开待回答；三个开关同时决定「弹横幅」与「播提示音」 |
| 提示音 | 播放提示音 | 总开关（默认开）；关掉只发横幅、不发声 |
| | 播放方式 | App 直接播放（默认，独立音量）/ 系统通知音（跟随系统专注模式与通知音量）；副标题随选择说明 |
| | 声音 | 默认「DSH 提示音」；另有系统默认通知音（仅系统方式）/ 8 个 macOS 系统声音 / 自定义音频文件 / 静音；右侧「试听」 |
| | 音量 | App 方式：0–100% **独立音量**（默认 90%）；系统方式：禁用并显示「系统」（由系统通知音量控制） |
| | 自定义音频 | 仅在选择「自定义音频文件…」时出现；选择后立即试听，路径持久化；系统方式下会复制到 `~/Library/Sounds` |
| 面板 | 材质 | 液态玻璃（macOS 26+ 默认）/ 经典磨砂 / 实色 |
| 后台 | 运行时阻止睡眠 | 默认关；有会话运行中时阻止 Mac 闲置睡眠（等价 `caffeinate -i`） |
| 通用 | 退出前确认 | 点面板电源键或右键「退出」时先弹确认框 |
| | 恢复所有设置… | NSAlert 二次确认后恢复推荐默认值 |

- 所有设置项即时生效并持久化到 UserDefaults（键前缀 `dshStatus.`，含旧域迁移）。
- **「运行时阻止睡眠」的实现与边界**：用 `ProcessInfo.beginActivity(.idleSystemSleepDisabled)` 申请
  `PreventUserIdleSystemSleep` 断言（`SleepPrevention.swift`）。条件 = 设置开关 && 已连接 && 顶层运行中会话数 > 0；
  断线、会话全部结束、关闭开关或 App 退出时释放（断言随进程销毁由系统兜底回收）。只阻止**闲置系统睡眠**：
  屏幕仍可关闭，合盖 / 手动睡眠 / 低电量强制睡眠不受影响；App 未运行时没有保护。
  断言名在 `pmset -g assertions` 中显示为 `DSH Status: sessions running, preventing idle sleep`
  （用 ASCII——中文会被系统过滤成空串，影响排查）。
- HIG 说明：HIG 建议设置窗口采用「工具栏 + 多 pane」结构、不提供 app 专属外观设置；
  本 App 为单页设置（内容量不足以拆分 pane），保持标准 titlebar + grouped Form；
  「面板材质」保留为兼容/可读性选项（系统「降低透明度」优先），在文档中标注该取舍。

## 5. 视觉规范（token）

- **颜色**：文字一律系统语义色（label / secondaryLabel / tertiaryLabel）；界面状态色用系统调色板
  （systemYellow/Blue/Green/Red），彩色只出现在状态 glyph、设置图标块、连接点。
  菜单栏图标另有 22pt 专用调色板（需要更大对比度），见 `Theme.statusNSColor`。
- **字号**：面板行标题 13 semibold、副标题 11；设置行标题 13、副标题 11、
  分区 footnote 11；页脚 12/11。最小可读 10pt。
- **圆角**：面板 16、hover 行 6、设置图标块 6（卡片/控件圆角由系统 Form 决定，约 10–12）。
- **间距**：面板：行 44 / 子行 24 / footer 38 / 内容内边距 6（视觉 14）；无 header、无分组标题行；
  设置：系统 Form 默认（约 20pt 外边距、48pt 图标行）。
- **分隔线**：`separatorColor`；面板仅在通知提示下方与 footer 上方各一条全宽分隔线；工具栏/卡片分层用系统 elevated 背景。
- **动效**：出现 0.06s ease-out / 关闭 0.12s ease-in；hover 0.08s；状态切换 0.45s；全部可关闭/尊重 Reduce Motion。

## 6. 通知

### 6.0 系统权限（关键）

- 通知权限**不能由 App 单方面决定**：被拒后 `requestAuthorization` 不会弹框，只会静默失败。
  因此启动/打开面板时查询 `UNUserNotificationCenter.getNotificationSettings`：
  - 未授权（notDetermined）：面板顶部提示「通知未开启，任务结束不会提醒 · 去开启」，点击后
    `NSApp.activate` + `requestAuthorization`（避免 App 在后台时系统框被静默拒绝）；
  - 已拒绝（denied）：提示变为「去开启」，点击打开系统设置「通知」面板；
  - 已授权：面板正常；面板底部月亮按钮是「勿扰」总开关，单项通知开关在设置页。
- **提示音不依赖通知权限**：声音由 App 用 `NSSound` 直接播放（见 §6.2），
  即使系统通知被关闭/拒绝，只要「提示音」开启且对应状态开关打开、勿扰关闭，仍会发声。
- **通知图标缓存（重要）**：macOS 按「App 身份（bundle id + .app 路径）」缓存通知横幅里的图标，
  改了图标/颜色但身份不变时会一直显示旧图标。需要刷新时：换新 bundle id **并且**换 .app 路径。
- App 图标使用与菜单栏空闲态同款的鲸鱼 glyph：**透明底、无圆角方块、主色 `#416EFB`**
  （构建时由 `WhaleLogo` 生成 `.icns`），与宿主 DeepSeek Harness 的官方图标区分开；退出确认弹窗同源。
  图标改进建议（分层 squircle / Icon Composer）见 [docs/icon-suggestions.md](icon-suggestions.md)。

### 6.1 行为

- 默认**只对「进入待回答」发通知**（title = 会话标题，body = 待回答摘要，点击 → 打开对应会话）。
- 已完成/已停止默认不发；待回答通知 30s 内同会话去重。
- **勿扰模式**（面板月亮 / 设置页开关，持久化）：开启时不弹任何系统通知、也不播提示音，单项开关配置原样保留，
  关闭后按原配置恢复。菜单栏图标与面板列表不受勿扰影响。

### 6.2 提示音（2026-11-08；2026-11-09 增加「系统通知音」送达方式）

- **背景**：用户先反馈「系统默认提示音太不明显」，需要独立音量与更明显的默认音色；随后又希望
  「可以走系统声音、受系统勿扰模式管理，同时也能用自定义声音」。两者是不同通道，故做成**二选一**。
- **送达方式**（`SoundDeliveryMode`，设置页「提示音 → 播放方式」，默认 `app`）：
  - **`app`（App 直接播放，默认）**：`content.sound = nil`，由 `NotificationSoundPlayer`（`NotificationSound.swift`）
    用 `NSSound` 直接播放；音量由 `NSSound.volume` 独立控制（`dshStatus.soundVolume`，默认 0.9）。
    与系统通知音量无关、不受专注模式静音；系统通知被关闭时仍会响；横幅被系统权限拦掉也照样响。
    受系统总输出音量上限约束（系统级物理上限，App 无法越过）。
  - **`system`（系统通知音）**：`content.sound = UNNotificationSound`，声音随系统通知播放，
    **受系统「专注模式/勿扰」与通知音量控制**（`~/Library/Sounds` 复制方案见下）；App 内音量滑杆禁用
    （显示「系统」），设置页「试听」在系统方式下发一条真实测试通知（横幅+声音，与正式提醒一致）。
- **音色选项**（两种方式共用，`NotificationSoundOption`）：
  - 内置默认音 **DSH 提示音**：`app/Resources/dsh-chime.wav`，A5–C#6–E6 三音上行琶音、峰值 0.92
    （≈系统 Glass 的 4.6 倍），由 `scripts/generate-dsh-chime.py` 生成；`scripts/build-app.sh` 打进
    `Contents/Resources`，并用 `--self-test-sound` 校验打包结果。
  - 8 个 `/System/Library/Sounds/*.aiff` 系统声音；**系统默认通知音**（仅系统方式可选，`UNNotificationSound.default`）；
    自定义文件走 `NSOpenPanel`（`UTType.audio`，路径存 UserDefaults，App 未沙盒化）；
    「静音」选项完全不发声。
- **系统方式的音频落地**：`UNNotificationSound(named:)` 只查 App bundle 与 `~/Library/Sounds`，
  因此内置音 / 系统声音 / 自定义文件都会复制成
  `~/Library/Sounds/dsh-status-<option>-<size>-<mtime>.<ext>` 后用文件名引用；源文件变化会自动重新落地，
  同时清理旧的 `dsh-status-*` 文件（`SystemNotificationSound.stage`）。
- **触发时机**：与通知完全相同——`onStatusTransition` 里对应状态开关打开、勿扰关闭时提醒；
  App 播放方式下不做 30s 去重（每次真实状态跃迁都提醒），但 0.4s 内的多次跃迁合并成一次；
  系统方式下声音随横幅一起由系统处理（通知 30s 去重同样作用于声音）。
- **取舍**：App 方式「更明显」但绕过系统专注模式（需要安静时用本 App 勿扰）；系统方式统一交给系统管理，
  但音量不可控、通知权限关闭时不响。不做 Focus 状态检测（私有接口），用送达方式让用户选择。
- **验收入口**：`DSHStatusBar --self-test-sound`（资源/选项解析/音量夹取/两种送达方式/落地幂等/设置持久化，
  48 项，构建时自动跑）；`DSHStatusBar --test-sound[=<option>,<volume>[,<customPath>]]` +
  `DSH_STATUS_SOUND_DELIVERY=app|system`（单独试听并打印实际通道/落地路径，播完自动退出）。

## 7. App 结构（Swift Package，无第三方依赖）

```
app/
  Package.swift
  Sources/DSHStatusBar/
    main.swift                  // 入口；--render-previews / --render-app-icon 离屏出图
    AppDelegate.swift           // 装配：模型 / 桥 / 状态项 / 面板 / 设置 / 通知
    StatusItemController.swift  // NSStatusItem / 右键菜单 / 图标刷新 / 过渡调度（含调试回放）
    IconTransition.swift        // 图标视觉状态 / 迁移计划 / 动效参数（IconMotion）
    IconAnimator.swift          // 图标动效（CA 图层：彗星弧 + 状态切换过渡）
    MenuBarIconRenderer.swift   // 图标绘制（鲸鱼 / 单色优先级环 / 数字）
    WhaleLogo.swift             // 鲸鱼矢量路径 + SVG path 解析器
    BridgeClient.swift          // bridge.json 轮询 + SSE + 命令 POST + 重连
    Models.swift                // BridgeState / SessionRow / Command（Codable）
    AppModel.swift              // UI 状态模型（过滤 / 分组 / 状态跃迁）
    StatusPanelController.swift // 自定义 NSPanel + Liquid Glass 材质 + 定位/关闭 + 高度动画（TopAlignedContentHost）
    StatusPanelView.swift       // 面板 SwiftUI 内容
    Settings.swift              // AppSettings（UserDefaults）+ 设置页 SwiftUI（grouped Form）
    SettingsWindow.swift        // 设置窗口 chrome（标准 NSWindow / frame autosave）
    NotificationManager.swift   // 通知权限与横幅发送（通知音交给 NotificationSound）
    NotificationSound.swift     // 提示音：送达方式 / 音色选项 / NSSound 播放器 / 系统通知音落地 / 自检
    Theme.swift                 // 设计 token（系统语义色 / 尺寸 / hover）
    PreviewRenderer.swift       // 离屏预览图（图标矩阵 / 面板 / 场景 / 设置页）
```

- 入口参数/环境：
  - `--render-previews <outDir>`：生成图标矩阵、面板三态、场景示意、设置页（深/浅）。
  - `--bridge-file <path>` / `DSH_STATUS_BRIDGE_FILE=<path>`：覆盖 bridge.json 路径。
  - `--open-panel` / `--open-settings`：启动后自动打开面板/设置（截图/调试）。
  - `--animate-subagents`：打开面板 → 展开 → 收起第一个有子智能体的会话，用于逐帧核对高度动画。
  - `--test-icon-transitions[=<起始步>,<步数>]`：脚本化回放全部图标状态迁移（每步打印时间线并自动退出）。
  - `--test-sound[=<option>,<volume>[,<customPath>]]`：按指定选项/音量试听提示音后退出（默认用当前设置）。
  - `DSH_STATUS_SOUND_DELIVERY=app|system`：`--test-sound` 时强制送达方式（验收两种通道用）。
  - `DSH_STATUS_SETTINGS_SOUND_DELIVERY=app|system` / `_SOUND_OPTION=<option>`：离屏设置页预览时覆盖提示音状态。
  - `--self-test-sound`：提示音自检（资源打包 / 选项解析 / 音量映射 / 设置持久化），无音频硬件依赖。
  - `DSH_STATUS_SETTINGS_PREVIEW_HEIGHT=<pt>`：设置页离屏预览的高度覆盖（默认 640；调试出完整长页用）。
  - `DSH_STATUS_ANIM_SCALE=<倍数>`：面板高度动画与图标状态过渡放慢 N 倍（默认 1），配合截屏逐帧核对。
  - `DSH_STATUS_DISABLE_TRANSITIONS=1` / `DSH_STATUS_DISABLE_RUN_ANIMATION=1`：强制降级路径（验收用）。
  - `DSH_STATUS_APPEARANCE=light|dark`：强制界面外观（仅调试/出图，不改系统设置）。
  - `--render-app-icon <path>`：生成 App 图标 PNG。
- `scripts/build-app.sh`：`swift build -c release` → `dist/DSHStatusBar.app`（Info.plist + ad-hoc 签名）。
- 异常宽容：bridge.json 缺失/损坏、SSE 断开、DSH 重启都不得崩溃。

## 8. 验收

1. `swift build -c release` 通过；`scripts/build-app.sh` 产出可启动 .app。
2. `--render-previews` 产出图标矩阵、面板三态（深/浅）、场景示意图、设置页（深/浅）。
3. 连 mock 桥时图标数字/颜色随状态变化，面板分组正确，点行会 POST 命令并打开 DSH。
4. 断开 mock 后 6s 内进入未连接态；mock 恢复后自动重连。
4.1 提示音：`--self-test-sound` 全 PASS（构建脚本自动跑）；设置页「试听」可听、音量滑块 0/50/100% 有明显差别；
   关闭「播放提示音」后不发声；系统通知权限关闭时 App 方式仍响、系统方式不响（勿扰开启时两者都静音）；
   同一帧多个会话跃迁只响一次（App 方式）；系统专注模式不影响 App 方式提示音（文档已说明取舍）。
4.2 提示音送达方式：切到「系统通知音」后，音量行禁用并显示「系统」；选择各音色/自定义文件后
   `~/Library/Sounds/dsh-status-*` 出现落地文件，`log stream` 可见 usernoted `hasSound:true` 与
   NotificationCenter「Playing notification sound { nam: dsh-status-... }」；系统「专注模式」下声音被系统静音。
5. 图标状态切换：`--test-icon-transitions` 逐条回放，默认速度 60fps 无跳变；`DSH_STATUS_ANIM_SCALE=3` +
   `scripts/capture-icon-transitions.sh` 逐帧捕获后，环覆盖角/彗星半径单调、数字不横移、过渡结束帧 = 稳态帧；
   规范见 [icon-transitions.md](icon-transitions.md)。
5. 设置窗口：标准 titlebar、可缩放、位置记忆、关闭不退出；所有设置即时生效。
6. 面板：Liquid Glass 材质下深浅色文字可读；Esc/外部点击关闭；状态项高亮随面板开合。

## 9. 参考资料

- 原生规范实测：[docs/research/macos-ui-conventions.md](research/macos-ui-conventions.md)（含 16 张标注截图）
- 本次重设计契约：[docs/ui-redesign-spec.md](ui-redesign-spec.md)
- 图标建议：[docs/icon-suggestions.md](icon-suggestions.md)
- 协议：[docs/protocol.md](protocol.md)；产品设计：[docs/design.md](design.md)

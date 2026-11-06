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

- **运行中彗星弧**：`CAShapeLayer` + `CAKeyframeAnimation`，顺时针；
  6s 一个节奏周期转 3 圈（平均 2s/圈），速度按正弦 ±32% 平滑起伏（48 个采样关键帧，首尾整数圈无缝）；
  弧长 `strokeEnd` 0.26 ⇄ 0.58、1.7s 单程呼吸。
- 静态部分（外环 / 轨道 / 数字 / 鲸鱼）继续走 `button.image`，切换桌面/菜单栏重建时系统总有正确静态帧，
  不会闪黑块；动画只加在图层上，由 GPU 驱动，实测常驻 CPU 0.0%。
- **状态切换过渡**（可关）：外环颜色/有无变化时，隐藏外环的静态图打底 → `CAShapeLayer` 用新颜色扫一圈
  （strokeEnd 0→1，0.45s）→ 颜色渐变 → 恢复完整静态图；过渡期间暂停彗星弧（0.75s 兜底）。
- 尊重「减弱动态效果」与低电量模式（自动降级静态）；设置页「播放运行动画」可彻底关闭。

### 2.4 资源

- 鲸鱼矢量路径来自 DSH 前端 `FISH_LOGO_PATH`（`WhaleLogo.swift` 内置 path 与 M/C/L/Z 解析器），
  不依赖外部图片，任何分辨率都清晰；面板 header / 空态复用同一路径（模板图片，随主题着色）。

## 3. 弹出面板（自定义 NSPanel，原生 popover 观感）

### 3.1 窗口与材质

- 不用 `NSPopover`：无边框 `NSPanel`（`.borderless + .nonactivatingPanel`），**没有 popover 箭头**，
  `.statusBar` 层级、跨 Space、不抢焦点；**20pt continuous 圆角**、系统窗口阴影。
- 材质（设置页「面板背景」可切，默认液态玻璃）：
  - macOS 26+：`NSGlassEffectView(style: .regular)`，`cornerRadius = 20`；
    tint 用 **低透明度白色**（`NSColor(white: 1, alpha: 0.12)`）：焦点态保持**半透明液态玻璃**，
    与未聚焦时（切到别的菜单栏菜单时）的观感一致。
    关键：`NSGlassEffectView` 在窗口为 key 时会把**不透明 tint**（如 `.windowBackgroundColor`、不透明灰）
    渲染成实色卡片；只有低透明度 tint 才能保持玻璃的模糊/折射。
  - 旧系统：`NSVisualEffectView(.popover)` 经典磨砂；
  - 显式选「实色」或系统开启「降低透明度」时用不透明填充。
- **双层窗口**：SwiftUI 内容在可成为 key 的透明面板窗口里（Esc/键盘/active 文本），
  材质背景放在一个**永不成为 key 的子窗口**（`PanelGlassWindow`）里，窗口比面板四周大 26pt。原因：`NSGlassEffectView`
  在窗口为 key 时会叠加提亮/实色观感——点开面板时和失焦（点开其它菜单栏菜单）时观感不一致；
  材质始终由非 key 窗口渲染后，**常态即等于失焦态的半透明液态玻璃**。
- **几何**：圆角 16pt、内容左右内边距 14pt、面板宽度 330pt（同 Status Trio）；阴影用系统窗口阴影。
- **状态项高亮 = 系统按下态高亮（逐点对齐）**：本机实测按下状态为「按钮左右各外扩 2pt、顶部比按钮顶高 1pt、
  底部比按钮底低 3pt」= 42×26.5pt、圆角 10.75、白色 28%；该几何随按钮尺寸推导，打开面板时用一个
  透明覆盖窗口（`StatusItemHighlightWindow`）绘制（状态项自己的窗口只有 item 宽，画不出系统这种更宽的胶囊）。
- 定位：状态项下方 **6pt**，按屏幕可见区域夹取（左右/底部 8pt）；宽度固定 **320pt**。
- 出现：**0.16s ease-out 淡入**（Reduce Motion 时直接显示）；关闭立即。
- 面板展示期间状态项图标显示**高亮胶囊**（与原生菜单栏项一致）。
- 关闭：再次点击状态项、点击面板外（含本 App 其它窗口）、Esc。

### 3.2 结构（自上而下）

```
┌ header 40 ────────────────────────────────┐  鲸鱼 13pt secondary + 「DSH 会话」13pt semibold
│                                           │  右侧：6pt 连接圆点（systemGreen / tertiary）+ 「实时/未连接」11pt secondary
├ 通知提示 32（仅未授权时）─────────────────┤  bell.slash(12, systemYellow) + 11pt secondary 文案 + 「去开启」+ chevron
├ 内容（滚动，最大 480，随屏幕收缩）────────┤
│  运行中 · 1                               │  分组标题 11pt semibold secondary，leading 6，高 26
│  ▸ 会话行（44）                           │  16pt filled 状态 glyph（系统状态色）+ 13pt semibold 标题
│    ◦ 子智能体行（24）                      │  + 11pt secondary 副标题 + 9pt chevron
│  ── 分隔线（左右内缩 6，视觉 12）──        │
│  打开 DSH（40）                           │  15pt secondary arrow.up.forward.app + 13pt regular 标题；无 chevron
├ footer 38 ────────────────────────────────┤  左：gearshape 11 + 「设置…」12pt secondary
└───────────────────────────────────────────┘  右：bell / power 13pt 图标按钮（24×24 命中区）
```

- 会话行 leading 状态色只用系统调色板：待回答 `systemYellow`、运行中 `systemBlue`、
  已完成 `systemGreen`、已停止 `systemRed`；未连接/不可用用 `secondaryLabelColor`。
- hover：仅整行底色（主文字色 8%/6%，6pt continuous 圆角，0.08s），不改变文字颜色。
- 子智能体：缩进 38pt、11pt secondary、4pt 状态色圆点、行高 24；点击打开父会话；不计入分组计数。
- 空状态（高 132）：鲸鱼 24pt tertiary +「全部空闲」13 semibold +「没有需要关注的会话」11 secondary。
- 未连接（高 148）：`exclamationmark.circle` 16 secondary +「DSH 未连接」13 semibold + 说明 + 原生 bordered 小按钮。
- 分组之间与动作行前为发丝分隔线（`separatorColor`），左右内缩 12pt（视觉）。

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
- 分区顺序：**菜单栏图标 → 显示 → 项目显示 → 通知 → 面板 → 通用**；页脚为 11pt tertiary 版本/连接脚注。
- 分区说明文字为 11pt secondary、左对齐，位于卡片下方。

| 分区 | 设置 | 说明 |
| --- | --- | --- |
| 菜单栏图标 | 中心数字 | 全部任务数（默认）/ 需要介入 / 与环颜色一致 / 不显示 |
| | 状态切换动效 | 外环扫一圈 + 颜色渐变（默认开） |
| | 播放运行动画 | 关闭可省电；低电量 / 减弱动态效果自动关闭 |
| 显示 | 待回答 / 运行中 / 已完成 / 已停止 | 关掉的状态不在面板出现，也不进圆环与数字 |
| 项目显示 | 按 workspace 逐个开关 | 关掉即隐藏该项目（会话本身不受影响） |
| 通知 | 系统通知状态 | 已开启 / 允许通知 / 打开系统设置 |
| | 待回答（推荐）/ 已完成 / 已停止 | 默认只开待回答 |
| 面板 | 材质 | 液态玻璃（macOS 26+ 默认）/ 经典磨砂 / 实色 |
| 通用 | 退出前确认 | 点面板电源键或右键「退出」时先弹确认框 |
| | 恢复所有设置… | NSAlert 二次确认后恢复推荐默认值 |

- 所有设置项即时生效并持久化到 UserDefaults（键前缀 `dshStatus.`，含旧域迁移）。
- HIG 说明：HIG 建议设置窗口采用「工具栏 + 多 pane」结构、不提供 app 专属外观设置；
  本 App 为单页设置（内容量不足以拆分 pane），保持标准 titlebar + grouped Form；
  「面板材质」保留为兼容/可读性选项（系统「降低透明度」优先），在文档中标注该取舍。

## 5. 视觉规范（token）

- **颜色**：文字一律系统语义色（label / secondaryLabel / tertiaryLabel）；界面状态色用系统调色板
  （systemYellow/Blue/Green/Red），彩色只出现在状态 glyph、设置图标块、连接点。
  菜单栏图标另有 22pt 专用调色板（需要更大对比度），见 `Theme.statusNSColor`。
- **字号**：面板行标题 13 semibold、副标题 11、分组标题 11 semibold；设置行标题 13、副标题 11、
  分区 footnote 11；页脚 12/11。最小可读 10pt。
- **圆角**：面板 20、hover 行 6、设置图标块 6（卡片/控件圆角由系统 Form 决定，约 10–12）。
- **间距**：面板：header 40 / 行 44 / 子行 24 / 分组标题 26 / footer 38 / 内容内边距 6（视觉 12）；
  设置：系统 Form 默认（约 20pt 外边距、48pt 图标行）。
- **分隔线**：`separatorColor`；面板分组分隔线左右内缩 12；工具栏/卡片分层用系统 elevated 背景。
- **动效**：出现 0.16s ease-out；hover 0.08s；状态切换 0.45s；全部可关闭/尊重 Reduce Motion。

## 6. 通知

### 6.0 系统权限（关键）

- 通知权限**不能由 App 单方面决定**：被拒后 `requestAuthorization` 不会弹框，只会静默失败。
  因此启动/打开面板时查询 `UNUserNotificationCenter.getNotificationSettings`：
  - 未授权（notDetermined）：面板顶部提示「通知未开启，任务结束不会提醒 · 去开启」，点击后
    `NSApp.activate` + `requestAuthorization`（避免 App 在后台时系统框被静默拒绝）；
  - 已拒绝（denied）：提示变为「去开启」，点击打开系统设置「通知」面板；
  - 已授权：面板正常，铃铛可切换待回答通知。
- **通知图标缓存（重要）**：macOS 按「App 身份（bundle id + .app 路径）」缓存通知横幅里的图标，
  改了图标/颜色但身份不变时会一直显示旧图标。需要刷新时：换新 bundle id **并且**换 .app 路径。
- App 图标使用与菜单栏空闲态同款的鲸鱼 glyph：**透明底、无圆角方块、主色 `#416EFB`**
  （构建时由 `WhaleLogo` 生成 `.icns`），与宿主 DeepSeek Harness 的官方图标区分开；退出确认弹窗同源。
  图标改进建议（分层 squircle / Icon Composer）见 [docs/icon-suggestions.md](icon-suggestions.md)。

### 6.1 行为

- 默认**只对「进入待回答」发通知**（title = 会话标题，body = 待回答摘要，点击 → 打开对应会话）。
- 已完成/已停止默认不发；待回答通知 30s 内同会话去重。

## 7. App 结构（Swift Package，无第三方依赖）

```
app/
  Package.swift
  Sources/DSHStatusBar/
    main.swift                  // 入口；--render-previews / --render-app-icon 离屏出图
    AppDelegate.swift           // 装配：模型 / 桥 / 状态项 / 面板 / 设置 / 通知
    StatusItemController.swift  // NSStatusItem / 右键菜单 / 图标刷新 / 过渡
    CometAnimator.swift         // 运行动画（CA 图层）
    MenuBarIconRenderer.swift   // 图标绘制（鲸鱼 / 单色优先级环 / 数字）
    WhaleLogo.swift             // 鲸鱼矢量路径 + SVG path 解析器
    BridgeClient.swift          // bridge.json 轮询 + SSE + 命令 POST + 重连
    Models.swift                // BridgeState / SessionRow / Command（Codable）
    AppModel.swift              // UI 状态模型（过滤 / 分组 / 状态跃迁）
    StatusPanelController.swift // 自定义 NSPanel + Liquid Glass 材质 + 定位/关闭
    StatusPanelView.swift       // 面板 SwiftUI 内容
    Settings.swift              // AppSettings（UserDefaults）+ 设置页 SwiftUI（grouped Form）
    SettingsWindow.swift        // 设置窗口 chrome（标准 NSWindow / frame autosave）
    NotificationManager.swift   // 通知权限与发送
    Theme.swift                 // 设计 token（系统语义色 / 尺寸 / hover）
    PreviewRenderer.swift       // 离屏预览图（图标矩阵 / 面板 / 场景 / 设置页）
```

- 入口参数/环境：
  - `--render-previews <outDir>`：生成图标矩阵、面板三态、场景示意、设置页（深/浅）。
  - `--bridge-file <path>` / `DSH_STATUS_BRIDGE_FILE=<path>`：覆盖 bridge.json 路径。
  - `--open-panel` / `--open-settings`：启动后自动打开面板/设置（截图/调试）。
  - `DSH_STATUS_APPEARANCE=light|dark`：强制界面外观（仅调试/出图，不改系统设置）。
  - `--render-app-icon <path>`：生成 App 图标 PNG。
- `scripts/build-app.sh`：`swift build -c release` → `dist/DSHStatusBar.app`（Info.plist + ad-hoc 签名）。
- 异常宽容：bridge.json 缺失/损坏、SSE 断开、DSH 重启都不得崩溃。

## 8. 验收

1. `swift build -c release` 通过；`scripts/build-app.sh` 产出可启动 .app。
2. `--render-previews` 产出图标矩阵、面板三态（深/浅）、场景示意图、设置页（深/浅）。
3. 连 mock 桥时图标数字/颜色随状态变化，面板分组正确，点行会 POST 命令并打开 DSH。
4. 断开 mock 后 6s 内进入未连接态；mock 恢复后自动重连。
5. 设置窗口：标准 titlebar、可缩放、位置记忆、关闭不退出；所有设置即时生效。
6. 面板：Liquid Glass 材质下深浅色文字可读；Esc/外部点击关闭；状态项高亮随面板开合。

## 9. 参考资料

- 原生规范实测：[docs/research/macos-ui-conventions.md](research/macos-ui-conventions.md)（含 16 张标注截图）
- 本次重设计契约：[docs/ui-redesign-spec.md](ui-redesign-spec.md)
- 图标建议：[docs/icon-suggestions.md](icon-suggestions.md)
- 协议：[docs/protocol.md](protocol.md)；产品设计：[docs/design.md](design.md)

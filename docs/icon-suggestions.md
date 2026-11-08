# 图标设计建议（菜单栏图标 + App 图标）

> 状态：建议稿 v1 · 2026-11-05 · 作者：icon-advisor
> 范围：**只讨论图标**（菜单栏状态图标、App 图标、通知横幅 / 退出弹窗里的图标）；面板与设置页布局另有文档，本文不涉及。
> 基线：当前 `app/` 实现（v5：单色优先级环 + 双层动态弧 + 空闲鲸鱼）；参数以 **源码为准**，预览图见 `docs/previews/`。
> 配套标注图：[`docs/icon-suggestions.png`](icon-suggestions.png)（把现有预览图放大 10× 并标注尺寸 / 对比度 / 色觉模拟）。
> 约束：本文只做研究与建议，**没有改任何源码、没有运行 App、没有改 `docs/previews/`**。

---

## 0. 结论先行

1. **「挺满意」的部分应当保留**：鲸鱼 + 单色优先级环 + 中心数字这套信息结构是对的——颜色只表达一件事、形状稳定、不堆叠多色。建议改的是**实现方式**和**边界条件**，不是推翻设计。
2. **最该改的是「模板图」问题**（P0-1）：菜单栏里所有中性元素（鲸鱼、数字、轨道、彗星、虚线）现在都是非模板位图、靠 `NSApp.effectiveAppearance` 手动取白/深灰。Apple 的规范做法是 black+clear 模板图，由系统负责深浅色、选中态、提高对比度；彩色只保留在外环一层。这同时能修掉「选中/高亮时白色元素在浅底上消失」的隐患。
3. **浅色模式有两处对比度不达标**（P0-3）：待回答黄 `#C79900` 对菜单栏背景只有 **2.23:1**、未连接灰 **2.47:1**，都低于 WCAG 非文本 3:1；而红（已停止）与绿（已完成）在绿色盲模拟下 ΔE 仅 **13–19**，基本不可分。建议加深浅色黄 + 给「已停止」加非颜色冗余。
4. **App 图标需要按 macOS 26/27 规范重做**（P0-4）：现在是透明底、80% 宽、自加投影的位图 `.icns`；HIG 要求 1024×1024 分层、系统 squircle 遮罩、系统负责 Liquid Glass 效果，用 Icon Composer 产出 `.icon`。通知横幅 / 退出弹窗里「悬浮贴纸」的观感就来自这里。
5. **运行中动效保留，但可以更克制**（P1-6）：菜单栏是常驻、视野边缘的持续运动，2s/圈偏快；建议旋转降到 3.5–4s/圈、调制 ±12%，以「呼吸」为主信号。同时 `docs/app-design.md §2` 里的动效参数已经和代码不一致，需要一起修。

优先级：**P0 = 建议改（4 条）** · **P1 = 值得做（4 条）** · **P2 = 可选（4 条）**。

---

## 1. 现状速览（以源码为准）

### 1.1 状态映射

| 情况 | 外环 | 内层 | 中心数字 |
| --- | --- | --- | --- |
| 完全空闲 | 无（鲸鱼 glyph） | — | — |
| 只有运行中 | 无 | 外环大小的中性动态弧（+16% 轨道） | 运行数 |
| 有已停止 | **红**（最高） | 有运行时为内层中性弧 | 见设置 |
| 有待回答 | **黄**（高于绿） | 同上 | 见设置 |
| 只有已完成 | **绿** | 同上 | 见设置 |
| 未连接 | 灰色虚线环 + 短横 | — | — |

优先级 **红(已停止) > 黄(待回答) > 绿(已完成)**；外环始终是同一半径的整圈，只换颜色。双层环时中心不显示数字（22pt 放不下第三层）——这是正确的取舍，见 P1-5。

### 1.2 关键尺寸（22pt 画布，设计值 / 从 3.2× 预览实测）

| 元素 | 设计值 | 实测 | 说明 |
| --- | --- | --- | --- |
| 画布 | 22×22pt | — | HIG：菜单栏高度 24pt → 上下各留 1pt |
| 外环 | r 7.9 / 线宽 2.1pt | 外径 17.97pt、线宽 ≈2.0–2.3pt | 外径占画布 81.5% |
| 单环内径 | 13.7pt | 13.6pt | 数字可用区 |
| 中心数字 | 字号 10.4pt，圆体 Bold | cap 高 7.50–7.81pt，笔画 ≈1.6–1.9pt | 到环内缘径向间隙 ≈2.9–3.1pt |
| 双层内环 | r 4.95 / 线宽 1.4pt | — | 内环内径仅 8.5pt |
| 两环间隙 | 1.2pt | — | 1x 下 1.2px，容易粘连 |
| 空闲鲸鱼 | 18.8pt 宽（等比） | ink bbox 18.80×13.83pt | 路径 ink bbox 正好等于 viewBox 23.16×17.04 |
| 未连接 | r 7.9 / 线宽 1.6pt / dash 2.2, 3.2 / 短横 6×1.4 | — | — |
| 运行中动画 | CA：6s 转 3 圈（平均 2s/圈）、±32% 速度调制；strokeEnd 0.26–0.58（94°–209°）呼吸 1.7s 往返 | — | 与 `docs/app-design.md §2.2` 写的 12fps / 2.4s / 85°–215° / 4.8s 不一致（见 P2-10） |
| 预览倍率 | 3.2×（渲染 2×） | 图标列 x=740..881px | 预览图「真实大小」一行右侧被裁切（见 P2-11） |

### 1.3 颜色与对比度（实测）

对比度按 WCAG 2.1 相对亮度计算；背景取预览图里的菜单栏底色（深 `#1C1C1E` / 浅 `#ECECEF`）。系统色为本机 macOS 27.2 上用 `NSColor` 读到的值，仅作对照（HIG 明确说系统色值会随版本浮动，**不要硬编码**）。

| 状态 | 深色值 | 深色对比 | 浅色值 | 浅色对比 | macOS 系统色（浅 / 深） |
| --- | --- | --- | --- | --- | --- |
| 待回答 | `#F2B900` | 9.49:1 ✅ | `#C79900` | **2.23:1 ❌** | `#FFCC00` / `#FFD600` |
| 运行中 | `#0A84FF` | 4.66:1 ✅ | `#007AFF` | 3.41:1 ✅ | `#0088FF` / `#0091FF` |
| 已完成 | `#34C759` | 7.66:1 ✅ | `#248A3D` | 3.73:1 ✅ | `#34C759` / `#30D158` |
| 已停止 | `#FF453A` | 4.99:1 ✅ | `#D70015` | 4.57:1 ✅ | `#FF383C` / `#FF4245` |
| 未连接 | 前景 42% → `#7B7B7C` | 4.02:1 ✅ | 前景 36% → `#979799` | **2.47:1 ❌** | `#8E8E93` / `#98989D` |
| 中心数字 | 白 | 17.01:1 ✅ | `#0F1115` | 16.03:1 ✅ | — |

色觉模拟（绿色盲 deuteranopia，Machado 2009，severity 1.0，CIE76 ΔE）：

| 对比对 | 正常视觉 ΔE | 绿色盲 ΔE | 结论 |
| --- | --- | --- | --- |
| 红(已停止) vs 绿(已完成) | 130.4 | **13.0（深）/ 19.0（浅）** | 基本不可分 |
| 红 vs 黄(待回答) | 71.7 | 53.6 | 可分 |
| 黄 vs 绿 | 78.3 | 52.4 | 可分 |

也就是说：**最需要区分的两个状态（停止 / 完成）恰好是色盲下最不可分的组合**，颜色不能是唯一线索。

### 1.4 与 macOS 系统调色板的关系

现有四色是「手工调过的状态色板」，不是系统语义色：

- `#0A84FF`（运行中，深色）与系统深色蓝几乎一致；`#FF453A`（已停止，深色）与系统深色红几乎一致；
- `#F2B900`（待回答）比系统黄更深、更偏琥珀；`#34C759`（已完成）介于系统绿的深浅之间；
- 浅色四个值都是**手工加深**过的（为了在浅色菜单栏上可读），因此和系统浅色色值差异较大——这是对的，但要写成规范。

HIG 要求：自定义颜色必须同时提供 light / dark / **提高对比度（Increase Contrast）** 三套变体，并避免硬编码系统色值。目前只有 light/dark 两套，且「提高对比度」设置没有响应（见 P0-3）。

---

## 2. P0（建议改）

### P0-1 菜单栏图标改为「模板图 + 彩色环图层」混合渲染

**现状**
`MenuBarIconRenderer.render()` 统一 `image.isTemplate = false`；中性元素（鲸鱼、数字、轨道、彗星、虚线环）按 `NSApp.effectiveAppearance` 手动取白（深色）或 `#1F1F23`（浅色）。彩色只有外环一层。

**问题**
1. HIG 对 menu bar extras 的明确做法是：图标/符号用 **black + clear 的模板图**，「系统可以把其他颜色应用到黑色区域，让它在深色和浅色菜单栏、以及菜单栏项被选中时都好看」。现在手动取色拿不到系统在**选中态**下的反色/提亮处理——深色模式下白色数字与白色鲸鱼，在点击时出现的浅色高亮底上会明显掉对比度。
2. 用 `NSApp.effectiveAppearance` 而不是按钮的实际外观：切桌面 / 全屏 / 换壁纸时可能瞬时解析成另一种外观（代码注释也承认这点），出现一闪而过的深/浅错版。
3. 无法自动响应「提高对比度 / 降低透明度」等辅助功能设置（模板图由系统处理）。
4. 22pt 画布上，中性层和彩色层其实**天然可分离**：数字、鲸鱼、轨道、彗星都在环带以内或环带以外，与彩色环的像素几乎不重叠。

**具体建议**
- 中性层改为 `isTemplate = true` 的 `NSImage`（`WhaleLogo.templateImage(height:)` 已有现成实现，panel header 在用同一套）。数字、轨道、彗星、虚线环、鲸鱼全部画进模板图。
- 彩色外环改由 `CAShapeLayer` 叠加（`IconAnimator` 已经有图层机制，直接复用），颜色仍来自 `Theme`。图层在模板图之上，只在环带区域有像素，不会遮住中性元素。
- 删除渲染器里手动 `dark ? .white : #1F1F23` 的分支（保留给预览离屏渲染用的显式外观参数即可）。
- 验收：深/浅色 + 选中态 + 「提高对比度」开启三种条件下截图对比；模板图在浅色菜单栏上应为自动深色、深色菜单栏上自动白色。

**依据 / 参考**
- HIG *The menu bar* → *Menu bar extras*：「Both interface icons and symbols use black and clear colors to define their shapes; the system can apply other colors to the black areas in each image so it looks good on both dark and light menu bars, and when your menu bar extra is selected. The menu bar's height is 24 pt.」
  <https://developer.apple.com/design/human-interface-guidelines/the-menu-bar>
- `NSImage.isTemplate`：「Images you mark as template images should consist of only black and clear colors.」
  <https://developer.apple.com/documentation/appkit/nsimage/istemplate>
- HIG *Icons*（interface icons 用 black/clear + 系统着色）
  <https://developer.apple.com/design/human-interface-guidelines/icons>
- WWDC25 *Meet Liquid Glass*：「Small elements, symbols, and glyphs flip from light to dark, so the material is discernible.」
  <https://developer.apple.com/videos/play/wwdc2025/219/>

---

### P0-2 中心数字：等宽数字 + 固定光学基线，消除左右跳动

**现状**
`drawCount` 用「字形轮廓面积质心」做水平居中（`lineAreaCentroidX`），字号按位数取 10.4 / 9.0 / 7.6pt，圆体 Bold，带 1pt 阴影。

**问题**
实测不同数字的 ink bbox 中心相对画布中心的偏移差异很大：

| 数字 | ink bbox 中心偏移（水平） | ink 尺寸 |
| --- | --- | --- |
| `1` | **−1.02pt** | 3.91 × 7.50pt |
| `3` | −0.62pt | 5.94 × 7.81pt |
| `2` | −0.39pt | 5.47 × 7.66pt |
| `6` | −0.16pt | 5.94 × 7.81pt |

- 数量在 1→2→3 之间变化时，数字会左右跳 **0.6–0.9pt**（22pt 画布的 3–4%），在菜单栏里看起来像在抖；
- `1` 被推左约 1pt，视觉上反而没有居中（面积质心 ≠ 视觉中心，对「1」这种重心偏右的字形尤其明显）；
- 浅色模式是近黑数字 + 黑色阴影，阴影纯属噪声；深色模式的白字 + 黑阴影才有分离作用。

**具体建议**
- 改用 **等宽数字**：`NSFont.monospacedDigitSystemFont` 或给现有字体加 `kNumberSpacing = monospaced`（SF Pro 的 tabular figures 就是为数字对齐设计的）；以 **advance box** 居中，不再用面积质心。
- 只对 `1` 保留一个**固定**光学微调（−0.2 ~ −0.3pt），其余数字 0 偏移。
- 字号收敛为三档固定值，不要按 ink 宽度缩：1 位 10.4pt、2 位 9.8pt、3 位 8.8pt（`99+` 仍用 8.8pt）。
- 阴影只在深色模式保留（`offset (0,−0.3)`、`blur 1.0`、黑 35%）；浅色模式去掉。
- 验收：1↔2↔6 切换时数字中心漂移 ≤ 0.1pt；「1」单独看仍然居中。

**依据 / 参考**
- HIG *Icons* → optical alignment：「Some icons — especially asymmetric ones — can look unbalanced when you center them geometrically instead of optically… Adjustments for optical centering are typically very small, but they can have a big impact.」
  <https://developer.apple.com/design/human-interface-guidelines/icons>
- WWDC25 *Say hello to the new look of app icons*：新网格让「optically balanced artwork」更容易。
  <https://developer.apple.com/videos/play/wwdc2025/220/>

---

### P0-3 浅色黄不达标 + 红/绿只靠颜色区分：补对比度与非颜色冗余

**现状**
`Theme.statusRGB`：待回答浅色 `#C79900`、已完成浅色 `#248A3D`、已停止浅色 `#D70015`；未连接用 `labelColor` 42%（深）/36%（浅）。环色是「状态」的唯一编码，中心数字只表示数量。

**问题**
1. **对比度**：浅色待回答 `#C79900` vs `#ECECEF` = **2.23:1**；浅色未连接 = **2.47:1**。WCAG 1.4.11 对「传达状态的图形」要求 3:1，HIG 也要求自定义色提供提高对比度变体。浅色模式恰好是菜单栏最常见的状态（浅色壁纸 / 浅色模式），这两处是最常被看到的。
2. **色盲**：红 vs 绿在绿色盲下 ΔE 13.0 / 19.0，几乎不可分；而「已停止 / 已完成」正是需要区分「要处理 / 已处理」的两个状态。
3. 颜色是唯一线索：数字只回答「几个」，不回答「哪种状态」。

**具体建议**
- 浅色待回答 `#C79900` → **`#A87F00`（3.12:1）**，更保守可用 `#9A7400`（3.66:1）；色相保持琥珀，不改成系统黄（`#FFCC00` 在浅色菜单栏上只有 1.28:1）。
- 未连接：深色前景 42% → **55%**（4.02 → 5.98:1），浅色 36% → **48%**（2.47 → 3.59:1）。
- 给「已停止」加**非颜色冗余**（任选其一，建议 A）：
  - A. 外环在 12 点方向留 **18° 缺口**（其余状态为完整环）——形状差异在 1x 下也能看出，且不增加视觉重量；
  - B. 外环线宽 2.1 → **2.4pt**（最重 = 最需要处理）；
  - C. 中心数字加「停止」角标（22pt 下空间不足，不推荐）。
- 响应系统辅助功能：`NSWorkspace.shared.accessibilityDisplayShouldDifferentiateWithoutColor` 打开时启用 A/B；`accessibilityDisplayShouldIncreaseContrast` 打开时把四色再加深/提亮一档（浅色 −15% 亮度、深色 +10%）。
- 保留现有 tooltip / accessibilityLabel 文本（已实现，很好）。
- 验收：浅色待回答 ≥3:1；绿色盲模拟下红/绿可区分（ΔE 目标 ≥25）；开关「区分颜色」时红环出现缺口。

**依据 / 参考**
- HIG *Accessibility* →「Strive to meet color contrast minimum standards」（WCAG AA：≤17pt 文本 4.5:1、≥18pt 或粗体 3:1）；「Convey information with more than color alone… people who are color blind may have particular difficulty with pairings such as red-green and blue-orange. Offer visual indicators, like distinct shapes or icons, in addition to color.」
  <https://developer.apple.com/design/human-interface-guidelines/accessibility>
- HIG *Color* →「Avoid relying solely on color to differentiate between objects, indicate interactivity, or communicate essential information.」；「If you define a custom color, make sure to supply light and dark variants, and an increased contrast option for each variant.」
  <https://developer.apple.com/design/human-interface-guidelines/color>
- WCAG 2.1 1.4.11 Non-text Contrast：<https://www.w3.org/TR/WCAG21/#non-text-contrast>

---

### P0-4 App 图标改为 1024 分层 `.icon`（Icon Composer），带满幅背景层

**现状**
`AppIconRenderer.image(size:)` 生成**透明底**、鲸鱼宽 = 画布 80%、带 26% 黑色投影的 `#416EFB` 鲸鱼；`scripts/build-app.sh` 用 `sips` 生成各尺寸 `.icns`。通知横幅、退出确认弹窗（`NSAlert.icon`）、设置页预览都用这个 glyph。

**问题**
1. macOS 26+ 的 App 图标是**分层 + 系统遮罩**：HIG 要求 1024×1024、分层（背景层 + 1–4 个前景层），squircle 由系统裁切，**不要自加投影/高光/模糊**——现在恰好相反（无背景层、自加投影）。
2. 透明底图标在系统容器里会变成「悬浮贴纸」：通知横幅里它被放在系统给的浅色图标位中，退出弹窗里则直接悬浮；而 Apple 自己的图标是满幅背景 + squircle，放进去是无缝的。
3. 系统对非分层位图会尝试自动分割（背景/前景两层），但对细线和复杂形状不处理——鲸鱼的尾鳍和眼睛细节属于这一类，结果不可控。
4. `docs/previews/app-icon.png` 是「深色底合成图」，看不出透明底的实际情况；`quit-confirm-dark.png` 还是旧版「深底白鲸」截图，与当前实现不一致。

**具体建议**
- 画布 **1024×1024**；**背景层满幅、不透明**：品牌蓝 `#416EFB` → 深蓝（如 `#2440B8`）的柔和渐变；前景层 = 鲸鱼（矢量 SVG，宽 ≈ **62–66%** 画布 = 635–676px，水平/垂直居中，ink bbox 居中）。
- **删除 26% 黑投影**（系统会加 Liquid Glass 的 specular / shadow；静态投影会和系统效果打架）。
- 分层导出 SVG → **Icon Composer** 生成 `AppIcon.icon`，Xcode 自动为旧系统生成位图；同时保留 `.icns` 兜底（macOS 15 及更早）。若不想上 Xcode 工程，也至少把 `.icns` 从「透明底」改成「满幅背景 + squircle 内容」。
- 重出三张预览：1024 原图（透明 + 浅色底 + 深色底）、通知横幅、退出弹窗；设置页里的图标矩阵同步。
- 注意：如果刻意想和 DeepSeek Harness 官方图标区分，**用背景色/构图区分，不要用透明底**——透明底在系统里看起来像「没做完的图标」，而且会被系统自动分割。
- 验收：Finder / 通知 / 退出弹窗 / 设置页四处观感一致；1024 原图在深色与浅色壁纸上都不「发灰」。

**依据 / 参考**
- HIG *App icons*：Layer design（背景层 + 前景层、Icon Composer）、Icon formats（非分层位图或分层 Icon Composer 文件）、Icon shape（系统遮罩成圆角矩形）、Visual effects（「Let the system handle blurring and other visual effects… no need to include specular highlights, drop shadows…」）、Specifications（macOS：1024×1024、Layered、default/dark/clear/tinted）。
  <https://developer.apple.com/design/human-interface-guidelines/app-icons>
- Xcode *Creating your app icon using Icon Composer*：「Remove blurs and shadows, and specular, opacity, and translucency settings.」「Don't export the canvas mask because the system applies that automatically.」
  <https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer>
- WWDC25 *Say hello to the new look of app icons*（macOS 图标改为新圆角矩形模板、1024 画布、避免细线、鼓励浅色模式用彩色背景）
  <https://developer.apple.com/videos/play/wwdc2025/220/>
- WWDC25 *Create icons with Icon Composer*（分层、` .icon` 交付、mono 外观映射）
  <https://developer.apple.com/videos/play/wwdc2025/361/>
- Icon Composer 下载：<https://developer.apple.com/icon-composer>
- App 图标网格模板（Figma/Sketch/PS/AI）：<https://developer.apple.com/design/resources/>

---

## 3. P1（值得做）

### P1-5 22pt 网格微调：线宽 / 两环间隙 / 环与数字的层级

**现状**
外环 r7.9 / 2.1pt；单环内径 13.7pt；数字 cap 7.5–7.8pt；双层时内环 r4.95 / 1.4pt，两环间隙 1.2pt，且不显示数字。

**问题**
- 内环 1.4pt 在 1x 屏上只有 1.4px，叠加抗锯齿会糊；两环间隙 1.2pt（1x 下 1.2px）会让两环视觉粘连。
- 外环线宽 2.1pt 比数字笔画（≈1.6–1.9pt）更重，**环抢走了「一眼可读」的注意力**。从信息价值看：环回答「有没有 / 多急」，数字回答「几件事」——用户扫菜单栏时最先要的是「有没有红色」，但一旦有颜色，下一步要读的是数字。所以层级应该是：颜色（瞬间）→ 数字（半秒）→ 面板（点击后）。
- 双层态不显示数字是合理取舍（内环内径只有 8.5pt，放不下可读数字），但要在别处补：tooltip / accessibilityLabel 已包含各状态计数（好），面板打开时 header 也应显示汇总。

**具体建议**
- 外环线宽 **2.1 → 2.0pt**（外径保持 17.9）。
- 内环线宽 **1.4 → 1.5pt**，半径 4.95 → **4.85**（外缘 5.35 → 5.6，视觉上仍在中间层）。
- 两环间隙 **1.2 → 1.4pt**（外环内缘 6.9 − 内环外缘 5.5）。
- 数字：字号不再按位数缩到 9.0/7.6（见 P0-2），保持 cap ≥7.5pt；数字与环内缘间隙保持 ≥2.8pt。
- 明确「一眼可读」的优先级写进规范：颜色 > 数字 > 面板；不要给环加额外装饰（描边、渐变、光晕）。
- 验收：1x（非 Retina 外接屏）+ 2x 两种缩放下，环、两环间隙、数字都可分辨；与系统菜单栏图标并排不显得笨重。

**依据 / 参考**
- HIG *Icons*：「In general, match the weights of interface icons and adjacent text.」
  <https://developer.apple.com/design/human-interface-guidelines/icons>
- HIG *SF Symbols* → Weights and scales（权重与文字匹配的概念）
  <https://developer.apple.com/design/human-interface-guidelines/sf-symbols>
- HIG *The menu bar* → Menu bar extras（菜单栏高度 24pt）
  <https://developer.apple.com/design/human-interface-guidelines/the-menu-bar>

---

### P1-6 运行中动效：保留，但更克制；同时修正文档参数

**现状**
`IconAnimator`：6s 转 3 圈（平均 **2s/圈**）+ ±32% 速度调制；弧长 `strokeEnd` 0.26–0.58（**94°–209°**）以 1.7s 往返（3.4s 周期）呼吸。已实现「减弱动态效果 / 低电量模式 / 设置开关」三条降级路径。`docs/app-design.md §2.2` 仍写「12fps、2.4s/圈、85°–215°、4.8s」。

**问题**
- 菜单栏是**常驻、视野边缘**的持续运动。HIG Motion 的原则是「Add motion purposefully… Don't add motion for the sake of adding motion」；持续旋转比呼吸更容易抢注意力，2s/圈比系统里的常驻动画都快。
- 动效本身是有意义的：它表达「有任务在跑」，而且是唯一能表达「正在变化」的通道（颜色只表达待办优先级）。所以**不建议删**，建议降强度。
- 文档与代码不一致，评审和回归没有基准（见 P2-10）。

**具体建议**
- 以「呼吸」为主信号：旋转 **2s/圈 → 3.5–4s/圈**，速度调制 **±32% → ±12%**（更匀速、更不抢眼）。
- 弧长呼吸幅度收窄：**94°–209° → 110°–170°**，周期 3.4s → 4s。
- 颜色/透明度保持中性（现在已是白/深灰 92%），不要再引入蓝色或品牌色（见 P2-12）。
- 保留三条降级路径；额外建议在设置里提供三档「流畅 / 呼吸（默认）/ 静态」，把「动效是否必要」的选择权交给用户。
- 把 `app-design.md §2.2` 的参数同步为代码值（或干脆改为引用 `IconAnimator` 常量）。
- 可选进阶：如果以后想更「系统化」，可以用 SF Symbols 7 的 Draw / variable color 表达进度，而不是自定义彗星弧（但会失去「环 + 数字」这套自定义语义，收益不大）。
- 验收：连续看 10 分钟不觉得烦；录屏对比 2s/圈与 4s/圈的观感；CPU 占用仍为 0%（CA 方案已满足）。

**依据 / 参考**
- HIG *Motion*：「Add motion purposefully, supporting the experience without overshadowing it. Don't add motion for the sake of adding motion.」「As much as possible, avoid displaying motion at the edges of a person's field of view.」
  <https://developer.apple.com/design/human-interface-guidelines/motion>
- HIG *Accessibility* → Reduce Motion：「When this setting is active, ensure your app or game responds by reducing automatic and repetitive animations.」
  <https://developer.apple.com/design/human-interface-guidelines/accessibility>
- WWDC25 *What's new in SF Symbols 7*（Draw / variable color 作为「进行中」的系统化表达）
  <https://developer.apple.com/videos/play/wwdc2025/337/>

---

### P1-7 未连接态：语义对，但太淡

**现状**
灰色虚线环（r7.9、线宽 1.6pt、dash 2.2/3.2）+ 6×1.4pt 短横，颜色 `labelColor` 42%（深）/36%（浅）。

**问题**
- 浅色模式对比度 **2.47:1**，低于 3:1；断连是「功能不可用」的重要状态，却比空闲鲸鱼还淡，容易被当成「一切正常」。
- 断连时用户可能以为「没有任务」，实际是「看不到任务」——这是最危险的状态混淆。

**具体建议**
- 形状不变（虚线环 + 短横的语义已经很清楚），只提高对比：深色 42% → **55%**、浅色 36% → **48%**（2.47 → 3.59:1）。
- 短横 6×1.4 → **6.5×1.5pt**，圆角 0.7 → 0.8pt，与数字笔画（≈1.6pt）保持同一套粗细语言。
- 可选：断连瞬间播放一次 0.3s 的「虚线旋转一圈」作为状态变化提示（`transitionAnimation` 已有同类机制），之后保持静止。
- 保持 tooltip「DSH 未连接」与 accessibilityLabel（已实现）。
- 验收：浅色模式下 1x 也能一眼看出「虚线 + 短横」，且与空闲鲸鱼区分明显。

**依据 / 参考**
- HIG *Color*：「Avoid using colors that make it hard to perceive content… insufficient contrast can cause icons and text to blend with the background.」
  <https://developer.apple.com/design/human-interface-guidelines/color>
- HIG *Accessibility* → color contrast minimum standards
  <https://developer.apple.com/design/human-interface-guidelines/accessibility>

---

### P1-8 彩色壁纸保护：给环一条对比兜底

**现状**
v4 移除了 v3 的白色包边（commit `39e019a` 曾加过），外环颜色直接画在透明画布上；运行中已改中性色（好），但红/黄/绿环仍直接压在壁纸上。

**问题**
菜单栏是半透明材质，会采样壁纸颜色。历史真机截图 `docs/previews/icon-real-zoom.png` 实测：蓝环 `#0A84FF` 在青绿壁纸 `#3C8C6E` 上只有 **1.11:1**（几乎不可见），而白色包边达到 **4.06:1**——说明 v3 的白包边确实在解决真问题。现在的红/黄/绿环在相近色壁纸（红墙纸、绿植、米黄壁纸）上会遇到同样的问题。

**具体建议**（二选一，推荐 B）
- **A. 0.5pt 中性包边**：深色模式白 25% / 浅色模式黑 25%，画在环外沿（外径 17.9 → 18.4pt，仍 ≤ 22pt 画布）。
- **B. 16% 前景色轨道垫底**：外环下恒画一条 16% 前景色轨道，再把彩色环压在上面——与运行中轨道是同一套视觉语言，不增加外径、不增加新元素。
- 验收：在青绿 / 橙 / 粉三张彩色壁纸上各截一张图，环都能被辨认；同时确认不会让图标变「脏」。

**依据 / 参考**
- HIG *Materials*（材质会采样背景、vibrancy 用于保证前景可读）
  <https://developer.apple.com/design/human-interface-guidelines/materials>
- HIG *Color*（避免前景与背景对比不足）
  <https://developer.apple.com/design/human-interface-guidelines/color>
- 项目历史：`git show 39e019a`（v3「菜单栏圆环加白色包边，彩色壁纸下更清晰」）

---

## 4. P2（可选）

### P2-9 空闲鲸鱼：光学居中与尺寸归一

**现状**
鲸鱼按 viewBox 等比放大到 18.8pt 宽、ink bbox 18.80×13.83pt，bbox 中心 = 画布中心 (11,11)。

**问题**
- 路径**面积质心**在 (10.44, 11.43)，相对画布中心偏左 **0.56pt**、偏上 **0.43pt**（鲸鱼身体重心在左下，尾鳍在右上）。
- 空闲态 ink 宽 18.8pt，比环外径 17.9pt 宽 **0.9pt**；空闲 ↔ 有任务切换时图标会「跳一下」。
- 注意：路径 ink bbox 正好等于 viewBox（23.16×17.04），所以现在的「bbox 居中」是几何居中；光学修正要另外加。

**具体建议**
- 等比缩到 **17.9pt 宽**（高 13.2pt），与环外径一致，消除尺寸跳变。
- 整体右移 **+0.3pt**、下移 **−0.2pt**（约为质心偏移的一半，先做保守修正，再用 3.2× 预览和真机截图各验证一次）。
- 如果以后换成图片资源：按 HIG 的做法，把光学修正做成 **asset 四周的 padding**，然后几何居中 asset 即可。
- 验收：与环状态并排看，鲸鱼视觉重心居中、切换不跳。

**依据 / 参考**
- HIG *Icons* → optical alignment：「add padding to a custom interface icon to achieve optical alignment… Adjustments for optical centering are typically very small.」
  <https://developer.apple.com/design/human-interface-guidelines/icons>
- HIG *App icons*：「Keep primary content centered to avoid truncation when the system adjusts corners or applies masking.」
  <https://developer.apple.com/design/human-interface-guidelines/app-icons>

---

### P2-10 图标规格收敛到单一来源，修正文档漂移

**现状**
图标参数散落在 `MenuBarIconRenderer`（半径/线宽/字号）、`IconAnimator`（旋转/呼吸）、`Theme`（颜色）、`docs/app-design.md §2`（文字规格）、`PreviewRenderer`（3.2× 预览）。预览图由同一套渲染器生成（这点很好）。

**问题**
文档已经明显漂移，评审时无法判断哪个是「正确值」：
- §2.2 写「12fps / 2.4s/圈 / 85°–215° / 4.8s」，代码是 CA 2s/圈 / 94°–209° / 3.4s 周期；
- §2.6 还写 v3 的「外环一个任务一段、等长、段间缺口；段长 ≤26° 改圆点」，但 v5 是**整圈单色**，代码里没有任何分段逻辑；
- §2.6 只列了深色四个色值（`#F2B900 / #0A84FF / #34C759 / #FF453A`），浅色变体没写；
- README 说「图标已升级到 v4（双层环）」，设计文档写 v5。

**具体建议**
- 新建 `IconSpec.swift`（或 `Theme` 内 `struct IconSpec`）集中所有尺寸/颜色/动效常量，`MenuBarIconRenderer` / `IconAnimator` / `PreviewRenderer` 全部引用；颜色给出 light / dark / increased-contrast 三套。
- `app-design.md §2` 改为「引用 IconSpec + 状态表 + 一句设计原则」，不再复制具体数字；补浅色色值。
- 每次改参数必须重跑 `--render-previews`，并在 PR 里贴新旧预览图。
- 验收：文档与代码参数一致（可以加一个简单脚本 grep 关键常量对比）。

**依据 / 参考**
- HIG *Icons*：「Maintain visual consistency across all interface icons in your app… consistent size, level of detail, stroke thickness (or weight), and perspective.」
  <https://developer.apple.com/design/human-interface-guidelines/icons>
- 仓库约定：`AGENTS.md`「修改行为/接口时同步更新 README / STATUS」。

---

### P2-11 预览图：「真实大小」一行被裁切 + 缺 App 图标预览矩阵

**现状**
`PreviewRenderer.renderIconSheet` 的 1x 行从 `margin + 150` 开始，14 个图标 × 46pt = 644pt，画布只有 760pt → 第 13 个图标落到圆角条之外、第 14 个完全被裁切（预览图最右的「2」悬在条外）。`app-icon.png` 是深色底合成图；`quit-confirm-dark.png` 已过期。

**问题**
预览图是评审依据：被裁切会漏看状态；App 图标没有透明底/浅色底/通知尺寸的预览，无法评估 P0-4 的效果。

**具体建议**
- 1x 行拆成两行（每行 7 个），或间距 46 → 38pt；保证 14 个状态全部落在圆角条内。
- 新增 `app-icon-preview.png` 矩阵：1024 原图 / 512 / 128 / 32pt，透明 + 浅色底 + 深色底三种背景；再附通知横幅与退出弹窗真机截图。
- 重出 `quit-confirm-dark.png`（当前实现是透明底蓝鲸，截图是旧版深底白鲸）。
- 验收：`--render-previews` 产出的图无裁切、含 App 图标矩阵；`docs/previews/README.md` 同步。

**依据 / 参考**
- HIG *App icons*（系统会在通知、设置等位置缩放到不同尺寸，需要在多尺寸下检查）
  <https://developer.apple.com/design/human-interface-guidelines/app-icons>
- 项目 `docs/previews/README.md` 的预览约定

---

### P2-12 图标与面板视觉语言的统一规则（品牌色只出现在该出现的地方）

**现状**
菜单栏鲸鱼用中性白/深灰（正确）；面板 header 鲸鱼用模板图（正确）；App 图标品牌蓝 `#416EFB`；面板状态色与图标环色同源 `Theme`。

**问题**
规则没有被写下来，后续容易走偏：有人可能觉得「菜单栏图标太素」而加品牌蓝，或者在面板里加第五种颜色；`#416EFB` 与状态色没有任何关系，需要明确它是「品牌色，只用于 App 图标」，避免被误用到状态语义里。

**具体建议**
把以下规则写进 `docs/app-design.md`（或单独 `docs/icon-spec.md`）：
1. **菜单栏 = 单色语义 + 一个状态色**：禁止品牌色、禁止渐变、禁止多色并置；
2. **品牌色 `#416EFB` 只用于 App 图标**（以及未来的 About 窗口），不进菜单栏、不进面板；
3. **状态色四色 + 中性灰**是唯一的状态编码，面板 / 设置页 / 通知 / 菜单栏复用同一 `Theme`；
4. **面板 header 鲸鱼保持 template**，随主题着色，不描边、不加底色；
5. 新增颜色前先查这张表：颜色要么表达状态，要么是品牌，不允许「装饰色」。
- 验收：新加图标/颜色时能一眼判断该不该用品牌色。

**依据 / 参考**
- HIG *Color*：「Avoid using the same color to mean different things.」「Apply color sparingly… reserve it for elements that truly benefit from emphasis, such as status indicators.」
  <https://developer.apple.com/design/human-interface-guidelines/color>
- HIG *Dark Mode*：语义色自动适配，自定义色要提供两套变体
  <https://developer.apple.com/design/human-interface-guidelines/dark-mode>
- HIG *Icons*（interface icon 用 black/clear，系统负责着色）
  <https://developer.apple.com/design/human-interface-guidelines/icons>

---

## 5. 验证清单

| 检查项 | 方法 | 通过标准 |
| --- | --- | --- |
| 模板图 + 环图层 | 深色 / 浅色 / 选中态 / 提高对比度 四种条件下截图 | 中性元素自动适配；环色不变 |
| 数字稳定性 | 在 1 / 2 / 6 / 12 之间切换，录屏逐帧看中心 | 水平漂移 ≤ 0.1pt |
| 对比度 | 按 1.3 表格重算（浅色黄、未连接） | 全部 ≥ 3:1 |
| 色盲 | 绿色盲模拟（Machado 2009） | 红/绿 ΔE ≥ 25，或红环有缺口 |
| 1x 可读性 | 非 Retina 外接屏截图 | 环、两环间隙、数字都能分辨 |
| 彩色壁纸 | 青绿 / 橙 / 粉三张壁纸截图 | 环在三种壁纸上都能辨认 |
| 动效 | 连续看 10 分钟；录屏对比 2s 与 4s | 不烦、不抢注意力；CPU 仍 ≈0% |
| App 图标 | Finder / 通知 / 退出弹窗 / 设置页 | 四处观感一致，无「悬浮贴纸」感 |
| 文档一致 | 对比 `app-design.md §2` 与 `IconSpec` | 参数一致、无 v3/v4 残留 |

---

## 6. 参考（Apple 官方）

**Human Interface Guidelines**
- The menu bar（Menu bar extras）：<https://developer.apple.com/design/human-interface-guidelines/the-menu-bar>
- Icons（含 optical alignment）：<https://developer.apple.com/design/human-interface-guidelines/icons>
- SF Symbols：<https://developer.apple.com/design/human-interface-guidelines/sf-symbols>
- App icons：<https://developer.apple.com/design/human-interface-guidelines/app-icons>
- Color：<https://developer.apple.com/design/human-interface-guidelines/color>
- Dark Mode：<https://developer.apple.com/design/human-interface-guidelines/dark-mode>
- Materials：<https://developer.apple.com/design/human-interface-guidelines/materials>
- Motion：<https://developer.apple.com/design/human-interface-guidelines/motion>
- Accessibility：<https://developer.apple.com/design/human-interface-guidelines/accessibility>

**Developer Documentation**
- `NSImage.isTemplate`：<https://developer.apple.com/documentation/appkit/nsimage/istemplate>
- `NSStatusItem`：<https://developer.apple.com/documentation/appkit/nsstatusitem>
- Creating your app icon using Icon Composer：<https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer>
- Icon Composer 下载：<https://developer.apple.com/icon-composer>
- App 图标网格模板：<https://developer.apple.com/design/resources/>

**WWDC25**
- 220 — Say hello to the new look of app icons：<https://developer.apple.com/videos/play/wwdc2025/220/>
- 361 — Create icons with Icon Composer：<https://developer.apple.com/videos/play/wwdc2025/361/>
- 219 — Meet Liquid Glass：<https://developer.apple.com/videos/play/wwdc2025/219/>
- 356 — Get to know the new design system：<https://developer.apple.com/videos/play/wwdc2025/356/>
- 337 — What's new in SF Symbols 7：<https://developer.apple.com/videos/play/wwdc2025/337/>
- 310 — Build an AppKit app with the new design：<https://developer.apple.com/videos/play/wwdc2025/310/>

**标准**
- WCAG 2.1 1.4.11 Non-text Contrast：<https://www.w3.org/TR/WCAG21/#non-text-contrast>

---

## 附录 A 测量方法

- **尺寸**：读取 `docs/previews/icon-preview-dark.png`（1520×2800px，760×1400pt @2×），图标按 `PreviewRenderer` 的 3.2× 缩放绘制（22pt → 70.4pt → 140.8px），用像素掩码测环外径、线宽、数字 ink bbox、鲸鱼 ink bbox；设计值以源码常量为准，实测用于交叉验证。
- **对比度**：WCAG 2.1 相对亮度公式，前景/背景取 sRGB 分量；背景取预览图菜单栏底色（`#1C1C1E` / `#ECECEF`）。
- **色觉模拟**：Machado et al. 2009 色觉缺陷矩阵（deuteranopia，severity 1.0），ΔE 用 CIE76。
- **系统色**：在本机 macOS 27.2 上用 `NSColor`（aqua / darkAqua 外观）读取，仅作对照；HIG 明确说系统色值会随版本浮动。
- **鲸鱼质心**：解析 `WhaleLogo.pathData`（M/C/L/Z），按 0.025 步长采样曲线，用多边形面积矩计算面积质心。
- 本报告未运行 App、未修改源码；标注图 `docs/icon-suggestions.png` 由 Pillow 处理已有预览图生成。

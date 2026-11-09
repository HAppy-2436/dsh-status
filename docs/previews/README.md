# 预览图

- 离屏图：由 `dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews docs/previews` 生成
  （`*-preview-*.png`、`scene-preview-dark.png`、`scene-preview-light.png`）；
  `app-icon.png` 由同一 App 的 `--render-app-icon docs/previews/app-icon.png` 生成（1024×1024 透明 PNG，
  与构建 .icns 使用同一绘制代码）；
  `settings-sound-preview-*.png` / `settings-background-preview-*.png` 是在 640pt 窗口内真实滚动到
  对应分区后截出的离屏图（调试入口 `DSH_STATUS_SETTINGS_PREVIEW_HEIGHT=<pt>` 可出完整长页、
  `DSH_STATUS_SETTINGS_BACKGROUND_OFFSET=<pt>` 可校准后台分区滚动位置）；
- 真机截图：`menubar-real.png` / `icon-real-zoom.png` / `panel-real-dark.png` /
  `panel-real-expanded-dark.png` / `panel-real-idle-dark.png` / `panel-real-idle-hover-dark.png` / `settings-real-dark.png`
  （macOS 27.2 深色模式，2x；空闲态那张用空闲 mock 桥出图；`menubar/panel/icon` 系列截于
  2026-11-05/06 的 0.1.x 构建，菜单栏与面板外观与 0.2.0 一致；`settings-real-dark.png`、
  `quit-confirm-dark.png` 已于 0.2.0 重截）；
- 动效逐帧：`icon-transition-dark.png`（真机动画放慢 3×，由
  `scripts/capture-icon-transitions.sh` 捕获后按迁移拼接；每行一次迁移、从左到右为时间顺序）。
- 面板离屏预览用实色背景（毛玻璃无法离屏渲染），真实玻璃观感以 `panel-real-dark.png` 为准。

| 文件 | 内容 |
| --- | --- |
| `icon-transition-dark.png` | **图标全状态切换动效逐帧对照（真机，放慢 3×）**：12 行 × 6 帧，覆盖扫入/收回/换色/彗星换道/数字滚动/断连/恢复；规范见 [../icon-transitions.md](../icon-transitions.md) |
| `icon-audit-99plus-and-fix.png` | **2026-11-08 验收检查证据**：左 = 修复前 `99+` 7.6pt+质心居中压外环（8× 离屏）；中 = 修复后 6.4pt+bbox 居中；右 = 真机基线 T30（100→101）同一「99+」双影帧；报告见 [../icon-audit.md](../icon-audit.md) |
| `app-icon.png` | **原创 App 图标（1024 源图，透明底）**：深色圆角方底 + 品牌「双层环」（外环品牌绿 + 内环冷白），对应菜单栏双层环状态；构建 `.icns`、通知横幅与退出确认弹窗共用同一绘制代码。菜单栏空闲态默认仍为鲸鱼，也可在设置中切换为品牌「虚线双环」 |
| `icon-preview-dark.png` | **图标状态矩阵（深色，主用）**：空闲鲸鱼（默认）/ 空闲虚线双环（可选）/ 运行中动态环 / 介入渐变环 / 双层环 / 未连接；放大 3.2× + 真实 1x 一行 |
| `icon-preview-light.png` | 同上，浅色菜单栏 |
| `menubar-real.png` | 真机菜单栏（8×）：运行中动态弧 + 中心运行数 |
| `icon-real-zoom.png` | 真机菜单栏图标 10× 放大（深色模式） |
| `panel-real-dark.png` | 真机面板（深色，Liquid Glass，330pt；扁平列表 + 已完成/运行中两态圆点；子智能体默认折叠） |
| `panel-real-expanded-dark.png` | 同上，点父行**行尾「数量 + 下箭头」**展开子智能体后的状态（下箭头转成上箭头，面板高度自动适配） |
| `panel-preview-dark.png` / `panel-preview-light.png` | 面板六态：默认折叠 / 行悬停 / 按钮悬停 / 展开子智能体 / 全部空闲 / 未连接（后两态 = 330×68 一整块大按钮） |
| `panel-real-idle-dark.png` | 真机空闲态（Liquid Glass，330×68）：鲸鱼 +「全部空闲」，整块面板可点打开 DSH |
| `panel-real-idle-hover-dark.png` | 同上，鼠标悬停态：高亮底色铺满整块内容区（圆角 12），说明点哪里都有效 |
| `scene-preview-dark.png` / `scene-preview-light.png` | 场景示意（离屏渲染，菜单栏 + 打开的面板；外壳圆角与真机同为 16pt continuous） |
| `settings-preview-dark.png` / `settings-preview-light.png` | 设置页（离屏渲染，深/浅）：原生 grouped Form 的八个分区（窗口默认高度下可见前三个） |
| `settings-sound-preview-dark.png` / `settings-sound-preview-light.png` | **提示音分区（2026-11-08 新增；2026-11-09 加「播放方式」，离屏渲染）**：通知 → 提示音；播放方式（App 直接播放 / 系统通知音）、音色/自定义文件、音量、勿扰同时静音 |
| `settings-background-preview-dark.png` / `settings-background-preview-light.png` | **后台分区（2026-11-09 新增，离屏渲染）**：面板 → 后台 → 通用；「运行时阻止睡眠」默认关，开启后有会话运行中时阻止 Mac 闲置睡眠 |
| `settings-real-dark.png` | 设置窗口真机截图（深色，540×668 标准 NSWindow；2026-11-09 于 0.2.0 重截） |
| `ui-before-after-dark.png` | 改版前后对照（面板 + 设置窗口，深色） |
| `quit-confirm-dark.png` | 退出二次确认弹窗（深色，默认焦点在「取消」；2026-11-09 于 0.2.0 重截，显示原创 App 图标） |
| `p1-devhost-panel.png` / `p1-devhost-menubar.png` | P1 联调截图：原 `plugin/test/dev-host.mjs` 假 Host + 真实 App 走完整桥协议（SSE/状态合并；插件后已迁至 dsh-status-bridge 仓库）；数据为开发演示数据，非真实 DSH |

图标语义（v5 单色优先级环，**菜单栏**）：空闲 = 鲸鱼；外环颜色 = 最高优先级待办（红停止 > 黄待答 > 绿完成）；
内层动态弧 = 运行中；只有运行中时动态弧占外环 + 中心运行数；中心数字语义可设置。
**App / 通知图标**与菜单栏图标分开：为原创「四色状态环」（`app-icon.png`，红/黄/绿/蓝 = 停止/待答/完成/运行中），
不含任何 DSH 官方品牌素材；菜单栏空闲态的鲸鱼保持不变。

配色与面板/设置页结构参考 [Status Trio](https://github.com/lingyired/status-trio)（Apache-2.0）。

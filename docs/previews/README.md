# 预览图

- 离屏图：由 `dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews docs/previews` 生成
  （`*-preview-*.png`、`scene-preview-dark.png`）；
- 真机截图：`menubar-real.png` / `icon-real-zoom.png` / `panel-real-dark.png` / `settings-real-dark.png`
  （macOS 27.2 深色模式，2x）。
- 面板离屏预览用实色背景（毛玻璃无法离屏渲染），真实玻璃观感以 `panel-real-dark.png` 为准。

| 文件 | 内容 |
| --- | --- |
| `icon-preview-dark.png` | **图标状态矩阵（深色，主用）**：空闲鲸鱼 / 运行中动态环 / 介入渐变环 / 双层环 / 未连接；放大 3.2× + 真实 1x 一行 |
| `icon-preview-light.png` | 同上，浅色菜单栏 |
| `menubar-real.png` | 真机菜单栏（8×）：运行中动态弧 + 中心运行数 |
| `icon-real-zoom.png` | 真机菜单栏图标 10× 放大（深色模式） |
| `panel-real-dark.png` | 真机面板（深色，Liquid Glass + 系统窗口色 tint，320pt；含真实会话与子智能体） |
| `panel-preview-dark.png` / `panel-preview-light.png` | 面板三态：有会话 / 全部空闲 / 未连接 |
| `scene-preview-dark.png` | 场景示意（离屏渲染，菜单栏 + 打开的面板） |
| `settings-preview-dark.png` / `settings-preview-light.png` | 设置页（离屏渲染，深/浅）：原生 grouped Form 的六个分区 |
| `settings-real-dark.png` | 设置窗口真机截图（深色，540×640 标准 NSWindow） |
| `ui-before-after-dark.png` | 改版前后对照（面板 + 设置窗口，深色） |
| `quit-confirm-dark.png` | 退出二次确认弹窗（深色，默认焦点在「取消」） |
| `p1-devhost-panel.png` / `p1-devhost-menubar.png` | P1 联调截图：`plugin/test/dev-host.mjs` 假 Host + 真实 App 走完整桥协议（SSE/状态合并）；数据为开发演示数据，非真实 DSH |

图标语义（v5 单色优先级环）：空闲 = 鲸鱼；外环颜色 = 最高优先级待办（红停止 > 黄待答 > 绿完成）；
内层动态弧 = 运行中；只有运行中时动态弧占外环 + 中心运行数；中心数字语义可设置。

配色与面板/设置页结构参考 [Status Trio](https://github.com/lingyired/status-trio)（Apache-2.0）。

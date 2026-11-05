# 预览图（P0）

由 `dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews docs/previews` 生成；
`menubar-real.png` / `icon-real-zoom.png` / `panel-real-dark.png` 为真机截图（深色模式）。

| 文件 | 内容 |
| --- | --- |
| `icon-preview-dark.png` | **图标状态矩阵（深色，主用）**：空闲鲸鱼 / 1 段运行中 / 2 段 / 待回答 / 已完成 / 已停止 / 三、五等分混合 / 未连接；放大 3.2× + 真实 1x 一行 |
| `icon-preview-light.png` | 同上，浅色菜单栏 |
| `menubar-real.png` | 真机菜单栏（6×）：柔和分段圆环 + 中心 3 |
| `icon-real-zoom.png` | 真机菜单栏图标 10× 放大（深色模式） |
| `panel-real-dark.png` | 真机 NSPopover（深色，v3 柔和配色 + 毛玻璃） |
| `panel-preview-dark.png` / `panel-preview-light.png` | 面板三态：有会话 / 全部空闲 / 未连接 |
| `scene-preview-dark.png` | 场景示意（离屏渲染，菜单栏 + 打开的面板） |
| `settings-preview-dark.png` | 设置页（离屏渲染，深色）：显示状态 / 项目显示 / 菜单栏图标 / 通知 |
| `settings-real-dark.png` | 设置页真机截图（深色） |
| `quit-confirm-dark.png` | 退出二次确认弹窗（深色，默认焦点在「取消」） |
| `p1-devhost-panel.png` / `p1-devhost-menubar.png` | P1 联调截图：`plugin/test/dev-host.mjs` 假 Host + 真实 App 走完整桥协议（SSE/状态合并）；数据为开发演示数据，非真实 DSH |

图标语义：空闲 = 纯白鲸鱼；非空闲 = 按任务数等分的彩色圆环（段色 = 任务状态）；
中心数字 = 待回答+已完成+已停止，只有运行中时不显示数字。

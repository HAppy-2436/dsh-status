# 预览图（P0）

由 `dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews docs/previews` 生成；
`menubar-real.png` / `icon-real-zoom.png` / `panel-real-dark.png` 为真机截图（深色模式）。

| 文件 | 内容 |
| --- | --- |
| `icon-preview-dark.png` | **图标状态矩阵（深色，主用）**：空闲鲸鱼 / 运行中动态环 / 介入渐变环 / 双层环 / 未连接；放大 3.2× + 真实 1x 一行 |
| `icon-preview-light.png` | 同上，浅色菜单栏 |
| `menubar-real.png` | 真机菜单栏（8×）：运行中动态弧 + 中心运行数 |
| `icon-real-zoom.png` | 真机菜单栏图标 10× 放大（深色模式） |
| `panel-real-dark.png` | 真机 NSPopover（深色，柔和配色 + 毛玻璃） |
| `panel-preview-dark.png` / `panel-preview-light.png` | 面板三态：有会话 / 全部空闲 / 未连接 |
| `scene-preview-dark.png` | 场景示意（离屏渲染，菜单栏 + 打开的面板） |
| `settings-preview-dark.png` | 设置页（离屏渲染，深色）：显示状态 / 项目显示 / 菜单栏图标 / 通知 |
| `settings-real-dark.png` | 设置页真机截图（深色） |
| `quit-confirm-dark.png` | 退出二次确认弹窗（深色，默认焦点在「取消」） |
| `p1-devhost-panel.png` / `p1-devhost-menubar.png` | P1 联调截图：`plugin/test/dev-host.mjs` 假 Host + 真实 App 走完整桥协议（SSE/状态合并）；数据为开发演示数据，非真实 DSH |

图标语义（v4 双层环）：空闲 = 鲸鱼；外层彩色环 = 需要介入（待回答黄 / 已停止红 / 已完成绿，按数量比例）；
内层动态弧 = 运行中；只有运行中时动态弧用外环大小 + 中心运行数；双层时不显示数字。

配色与面板/设置页结构参考 [Status Trio](https://github.com/lingyired/status-trio)（Apache-2.0）。

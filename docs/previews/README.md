# 预览图（P0）

由 `dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews docs/previews` 生成；
`menubar-real.png` / `icon-real-zoom.png` / `panel-real-dark.png` 为真机截图（深色模式）。

| 文件 | 内容 |
| --- | --- |
| `icon-preview-dark.png` | **图标状态矩阵（深色，主用）**：空闲鲸鱼 / 1 段运行中 / 2 段 / 待回答 / 已完成 / 已停止 / 三、五等分混合 / 未连接；放大 3.2× + 真实 1x 一行 |
| `icon-preview-light.png` | 同上，浅色菜单栏 |
| `menubar-real.png` | 真机菜单栏（3×）：分段圆环 + 中心 3，位于微信/天气图标左侧 |
| `icon-real-zoom.png` | 真机菜单栏图标 10× 放大（深色模式） |
| `panel-real-dark.png` | 真机 NSPopover（深色） |
| `panel-preview-dark.png` / `panel-preview-light.png` | 面板三态：有会话 / 全部空闲 / 未连接 |
| `scene-preview-dark.png` | 场景示意（离屏渲染，菜单栏 + 打开的面板） |

图标语义：空闲 = 纯白鲸鱼；非空闲 = 按任务数等分的彩色圆环（段色 = 任务状态）；
中心数字 = 待回答+已完成+已停止，只有运行中时不显示数字。

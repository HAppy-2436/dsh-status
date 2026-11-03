# 预览图（P0）

由 `dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews docs/previews` 生成。

| 文件 | 内容 |
| --- | --- |
| `scene-preview-dark.png` | **场景示意（深色，主用）**：模拟菜单栏 + 打开的面板。离屏渲染，与真实菜单栏同一套绘制代码 |
| `icon-preview-dark.png` | 单圆形图标 × 7 种状态 × 两个变体（disc / ring），放大 3×；底部为真实 1x 尺寸 |
| `icon-preview-light.png` | 同上，浅色菜单栏 |
| `panel-preview-dark.png` | 面板三态：有会话 / 全部空闲 / 未连接（深色，主用） |
| `panel-preview-light.png` | 面板三态（浅色） |

图标信息层级：圆盘数字 = 待回答+已完成+已停止；圆盘颜色 = 最高优先级原因；
外圈蓝弧 = 有会话运行中（不计入数字）；未连接 = 灰色虚线环。

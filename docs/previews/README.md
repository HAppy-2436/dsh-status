# 预览图（P0）

由 `dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews docs/previews` 生成。

| 文件 | 内容 |
| --- | --- |
| `icon-preview-light.png` / `icon-preview-dark.png` | 三种基础图形（A fish / B sessions stack / C harness nodes）× 7 种状态，放大 2.4×；底部为真实 1x 尺寸 |
| `panel-preview-light.png` / `panel-preview-dark.png` | 面板三态：有会话 / 全部空闲 / 未连接（离屏渲染） |
| `menubar-real.png` | 真实菜单栏截图（放大 4×）：fish + 运行等化器 + 红色角标 3 |
| `panel-real-dark.png` | 真实 NSPopover 截图（深色模式，mock 数据） |

状态含义：空闲 / 运行中（蓝色等化器条）/ 已完成（绿）/ 已停止（橙）/ 待回答（红）/ 未连接（灰）。

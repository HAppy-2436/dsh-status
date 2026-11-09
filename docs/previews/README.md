# 预览图

> **隐私说明**：本仓库**不包含任何真机截图**（面板 / 设置 / 通知 / 桌面 / 菜单栏原始截图）。
> 下列图片全部由 App 内置的 `--render-previews` / `--render-app-icon` 生成，属于**离屏渲染**，
> 使用虚构示例数据（`example-app` 等项目名、通用会话标题），不含真实会话、项目名或个人信息。

- 离屏图：`dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews docs/previews`
  （`*-preview-*.png`、`scene-preview-*.png`）；
  `app-icon.png` / `app-icon-whale.png` 由 `--render-app-icon` / `--render-app-icon-whale` 生成；
  `settings-sound-preview-*.png` / `settings-background-preview-*.png` 是在 640pt 窗口内离屏滚动到
  对应分区后截出的图（调试入口 `DSH_STATUS_SETTINGS_PREVIEW_HEIGHT=<pt>` 可出完整长页）。

| 文件 | 内容 |
| --- | --- |
| `app-icon.png` | **品牌「双层环」App 图标（1024 源图，透明底）**：深色圆角方底 + 外环品牌绿 + 内环冷白；构建 `.icns`、通知与退出确认弹窗共用同一绘制代码（离屏渲染） |
| `app-icon-whale.png` | 可选的「DeepSeek 蓝色鲸鱼」App 图标（1024 源图，透明底，`#416EFB`）；设置 → 通用 → 应用图标 可切换（离屏渲染；鲸鱼矢量来自 DSH，MIT，见 [../../THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md)） |
| `icon-preview-dark.png` / `icon-preview-light.png` | **菜单栏图标状态矩阵（深/浅色）**：空闲鲸鱼（默认）/ 空闲虚线圆环（可选，未连接样式）/ 运行中 / 已完成 / 待回答 / 已停止 / 双层环 / 未连接；放大 3.2× + 真实 1x 一行（离屏渲染） |
| `panel-preview-dark.png` / `panel-preview-light.png` | 面板六态：默认折叠 / 行悬停 / 按钮悬停 / 展开子智能体 / 全部空闲 / 未连接（离屏渲染，示例数据） |
| `scene-preview-dark.png` / `scene-preview-light.png` | 场景示意：菜单栏 + 打开的面板（离屏渲染，示例数据；外壳圆角与真机同为 16pt continuous） |
| `settings-preview-dark.png` / `settings-preview-light.png` | 设置窗口：原生 grouped Form 的八个分区（离屏渲染，深/浅） |
| `settings-sound-preview-dark.png` / `settings-sound-preview-light.png` | 提示音分区（离屏渲染）：播放方式 / 声音 / 音量 / 自定义音频 |
| `settings-background-preview-dark.png` / `settings-background-preview-light.png` | 后台分区（离屏渲染）：登录时自动启动 / 运行时阻止睡眠 |

图标语义（菜单栏）：空闲 = 鲸鱼（默认，可切「虚线圆环」）；外环颜色 = 最高优先级待办
（红停止 > 黄待答 > 绿完成）；内层动态弧 = 运行中；中心数字语义可设置。
App / 通知图标为原创「双层环」（默认）或可选的 DeepSeek 蓝色鲸鱼，见 `app-icon*.png`。

配色与面板/设置页结构参考 [Status Trio](https://github.com/lingyired/status-trio)（Apache-2.0）。

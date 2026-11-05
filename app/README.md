# DSHStatusBar（Swift 菜单栏 App）

macOS 菜单栏常驻 App：显示 DSH 会话的「待回答 / 运行中 / 已完成 / 已停止」，
图标旁数字 = 待回答 + 已完成 + 已停止 的数量；单击弹出面板，点会话行跳到 DSH 对应会话。

## 构建

```bash
bash ../scripts/build-app.sh          # 产出 dist/DSHStatusBar.app（release + ad-hoc 签名）
```

## 运行（P0：mock 假数据）

```bash
# 1) 起 mock 桥
export PATH="$HOME/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin:$PATH"
node ../mock/bridge.mjs --file bridge.mock.json --dir "$HOME/.dsh-status"

# 2) 起 App（默认读 ~/.dsh-status/bridge.json，此处指向 mock）
DSH_STATUS_BRIDGE_FILE="$HOME/.dsh-status/bridge.mock.json" \
  ../dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar
```

或直接 `bash ../scripts/demo.sh`（mock + App 一键起）。调试入口：

- `--open-panel` / `--open-settings`：启动后自动打开面板 / 设置窗口（截图用）
- `--bridge-file <path>`：指定桥文件
- `DSH_STATUS_APPEARANCE=light|dark`：强制界面外观（仅调试/出图，不改系统设置）
- `--render-previews <dir>`：离屏生成全部设计预览图
- `--render-app-icon <path>`：生成 1024pt App 图标 PNG

设置入口：面板底部齿轮按钮，或右键菜单栏图标 →「设置…」（⌘,）。设置即时生效并保存在 UserDefaults。

## 设计预览图

```bash
../dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews ../docs/previews
```

生成：`icon-preview-dark/light.png`（图标状态矩阵）、`panel-preview-dark/light.png`（面板三态）、
`scene-preview-dark.png`（菜单栏 + 面板场景示意）、`settings-preview-dark/light.png`（设置页深/浅）。

## 结构

- `MenuBarIconRenderer.swift` — 图标绘制（空闲鲸鱼 / 非空闲分段圆环，深色优先）
- `WhaleLogo.swift` — DeepSeek 鲸鱼 Logo 矢量路径 + SVG path 解析器
- `BridgeClient.swift` — bridge.json 轮询 + SSE + 命令 POST + 重连
- `StatusItemController.swift` — NSStatusItem、左右键行为、样式切换菜单
- `StatusPanelView.swift` — SwiftUI 面板内容（原生 popover 观感）
- `StatusPanelController.swift` — 自定义 NSPanel、Liquid Glass 材质、定位与关闭
- `SettingsWindow.swift` — 设置窗口 chrome（标准 NSWindow / frame autosave）
- `PreviewRenderer.swift` — 离屏预览图
- `NotificationManager.swift` — 待回答/已完成/已停止系统通知
- `Theme.swift` — 设计 token：系统语义色/状态色、尺寸、hover；菜单栏图标专用调色板
- `Settings.swift` — 设置模型（UserDefaults 持久化）+ SwiftUI 设置页（原生 grouped Form）

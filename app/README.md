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

或直接 `bash ../scripts/demo.sh`（mock + App 一键起）。加 `--open-panel` 可启动后自动打开面板
（截图/调试用）；加 `--bridge-file <path>` 可指定桥文件。

## 设计预览图

```bash
../dist/DSHStatusBar.app/Contents/MacOS/DSHStatusBar --render-previews ../docs/previews
```

生成：`icon-preview-light.png` / `icon-preview-dark.png`（三种图标样式 × 状态矩阵）、
`panel-preview-light.png` / `panel-preview-dark.png`（面板三种状态）。

## 结构

- `MenuBarIconRenderer.swift` — 图标绘制（fish / stack / nodes 三种基础图形，2x 渲染）
- `BridgeClient.swift` — bridge.json 轮询 + SSE + 命令 POST + 重连
- `StatusItemController.swift` — NSStatusItem、左右键行为、样式切换菜单
- `StatusPanelView.swift` — SwiftUI 面板
- `PreviewRenderer.swift` — 离屏预览图
- `NotificationManager.swift` — 待回答系统通知

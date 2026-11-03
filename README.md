# dsh-status

> macOS 菜单栏常驻工具：图标旁数字 = DeepSeek Harness 中「待回答 + 已完成 + 已停止」的会话数；
> 单击弹出面板，只列非空闲会话（运行中 / 已完成 / 已停止 / 待回答），点击某行跳到 DSH 主窗口并打开该会话。

## 当前状态（2026-11-03）

- **P0 已完成**：Swift 菜单栏 App 可用（图标三方案 / 面板 / SSE 桥客户端 / 未连接态 / 待回答通知），
  配套 mock 桥可以脱离 DSH 演示；设计预览图在 [`docs/previews/`](docs/previews/README.md)。
- **P1 待做**：DSH 插件（Host 薄桥 + Client 状态聚合 + 跳转命令），之后接入真实会话。
- 图标基础方案（A fish / B sessions stack / C harness nodes）**待选定**。

## 快速开始（P0 演示，假数据）

```bash
bash scripts/demo.sh          # 起 mock 桥 + 菜单栏 App；Ctrl-C 退出
```

菜单栏会出现图标：mock 数据 = 1 待回答 + 2 运行中 + 1 已完成 + 1 已停止（角标 3）。
点图标看面板，点会话行会打印一条 openSession 命令（mock 不真跳转）。

真实接入（P1 完成后）：

```bash
bash scripts/install.sh       # 构建 App 到 ~/Applications，并打印插件安装步骤
```

## 架构

```
DSH renderer ── 插件 Client 半（读 uiSession 状态）──┐
                                                    ├─ 本机 HTTP/SSE ── 原生菜单栏 App
DSH Host ── 插件 Host 薄桥（bridge.json + 路由）────┘
```

- 协议：[docs/protocol.md](docs/protocol.md)
- 产品设计：[docs/design.md](docs/design.md)
- App / 图标设计规范：[docs/app-design.md](docs/app-design.md)
- P0 演示与协议自检：`scripts/demo.sh`、`scripts/test-bridge.sh`

## 目录结构

- `app/` — Swift 菜单栏 App（SwiftPM，无第三方依赖）
- `plugin/` — DSH 插件 bundle（P1）
- `mock/` — mock 桥（P0 演示 / App 联调）
- `scripts/` — 构建、安装、演示、协议测试
- `docs/` — 设计文档与预览图

## 文档

- [docs/previews/README.md](docs/previews/README.md) — 图标/面板预览图说明
- `STATUS.md` — 当前状态与下一步（**每轮工作后更新**）
- `AGENTS.md` — 给 agent 的固定上下文

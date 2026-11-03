# dsh-status

> macOS 菜单栏常驻工具：图标旁数字 = DeepSeek Harness 中「待回答 + 已完成 + 已停止」的会话数；
> 单击弹出面板，只列非空闲会话（运行中 / 已完成 / 已停止 / 待回答），点击某行跳到 DSH 主窗口并打开该会话。

## 当前状态

**设计方案 v2（简化版）已完成，待确认后开工**：见 [docs/design.md](docs/design.md)。

架构结论：DSH 桌面版没有 macOS 菜单栏 API，因此方案 = **DSH 插件（Client 状态 + Host 薄桥）**
+ **原生 Swift 菜单栏 App（界面）**。状态模型直接复用 DSH Client 自带的
`ctx.uiSession.sessionStatus`（`running` / `pendingInteraction` / `completionUnread`）。

## 快速开始

```bash
# 待实现（P0/P1 开始后补）
```

## 目录结构

- `docs/design.md` — 设计方案（需求、状态来源、面板交互、架构、分期、风险）
- `plugin/` — DSH 插件（Host 薄桥 + Client 状态）— 待建
- `app/` — Swift 菜单栏 App — 待建
- `scripts/` — 构建与安装脚本 — 待建

## 文档

- [docs/design.md](docs/design.md) — 设计方案
- `STATUS.md` — 当前状态与下一步（**每轮工作后更新**）
- `AGENTS.md` — 给 agent 的固定上下文

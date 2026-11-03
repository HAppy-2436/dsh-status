# dsh-status

> macOS 菜单栏常驻工具：实时显示 DeepSeek Harness 各项目（workspace）的运行状态
> （空闲 / 运行中 / 已完成 / 已停止 / 需要回答），支持多项目、单击浮窗、双击打开主页面、
> 状态切换系统通知，并可在浮窗内直接回答问题。

## 当前状态

**设计方案已完成，待确认后开工**：见 [docs/design.md](docs/design.md)。

架构结论：DSH 桌面版没有 macOS 菜单栏 API，因此方案 = **DSH 插件（数据与动作）**
+ **原生 Swift 菜单栏 App（界面）**，两者通过本机回环 HTTP + token 桥接。

## 快速开始

```bash
# 待实现（P0/P1 开始后补）
```

## 目录结构

- `docs/design.md` — 设计方案（架构、状态模型、交互、分期、风险）
- `plugin/` — DSH 插件（Host 半 / P2 的 Client 半）— 待建
- `app/` — Swift 菜单栏 App — 待建
- `scripts/` — 构建与安装脚本 — 待建

## 文档

- [docs/design.md](docs/design.md) — 设计方案
- `STATUS.md` — 当前状态与下一步（**每轮工作后更新**）
- `AGENTS.md` — 给 agent 的固定上下文

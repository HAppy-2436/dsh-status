# dsh-status

> macOS 菜单栏常驻工具：图标旁数字 = DeepSeek Harness 中「待回答 + 已完成 + 已停止」的会话数；
> 单击弹出面板，只列非空闲会话（运行中 / 已完成 / 已停止 / 待回答），点击某行跳到 DSH 主窗口并打开该会话。

## 当前状态（2026-11-03）

- **安装位置 / Bundle ID**：`~/Applications/DSH Status.app`，`com.liyitong.dshstatus.menubar`
  （更早版本的设置域会在首次启动时自动迁移）
- **App 图标**：与菜单栏空闲态同款的鲸鱼 glyph，**透明底、无圆角方块、主色 `#416EFB`**
  （构建时由 `WhaleLogo` 生成 `.icns`），避免和 DeepSeek Harness 官方图标混淆
- **P0 已完成**：Swift 菜单栏 App 可用——**鲸鱼 + 单色优先级环图标（v5）**：
  - 外环始终是一整圈单色，颜色 = 当前最高优先级待办：**红(已停止) > 黄(待回答) > 绿(已完成)**；
  - 有任务运行时：彗星弧用 Core Animation（GPU）平滑旋转 + 弧长呼吸；
    静态层只在状态变化时重绘，实测常驻 CPU ≈ 0%；
  - 只有运行中：动态弧直接用外环大小 + 中心运行数；内外环同时存在时不显示数字；
  - 中心数字可在设置里选：全部任务（默认）/ 需要介入 / 与环色一致 / 不显示；
  - 完全空闲时显示 DeepSeek 鲸鱼 Logo。、面板、**设置页**（自定义显示状态 / 隐藏项目 / 中心数字 / 段数上限 / 通知）、
  SSE 桥客户端、未连接态、通知；
  界面按 macOS 原生风格调校（自定义无箭头 NSPanel + Liquid Glass 材质、20pt 圆角、系统强调色；
可切换液态玻璃 / 经典磨砂 / 实色）；
  配套 mock 桥可脱离 DSH 演示；设计预览图与真机截图在 [`docs/previews/`](docs/previews/README.md)。
- **P1 已实现（待安装验证）**：DSH 插件（Host 薄桥 + Client 状态聚合 + 跳转命令）代码与测试完成；
  还差在 DSH 里通过 Plugins 页面安装（Desktop profile 只能 GUI 安装），然后真机验证。
- 图标已升级到 v4（双层环），配色/材质/通知等也已在真机联调中迭代。

## 快速开始（P0 演示，假数据）

```bash
bash scripts/demo.sh          # 起 mock 桥 + 菜单栏 App；Ctrl-C 退出
```

菜单栏会出现图标：mock 数据 = 1 待回答 + 2 运行中 + 1 已完成 + 1 已停止（角标 3）。
点图标看面板，点会话行会打印一条 openSession 命令（mock 不真跳转）。

打开设置：点面板底部齿轮，或右键菜单栏图标 →「设置…」；修改即时生效。

真实接入（一次性安装）：

```bash
bash scripts/install.sh       # 构建 App 到 ~/Applications，并打印插件安装步骤
```

然后在 DeepSeek Harness 左侧边栏 **Plugins → Add plugin → Install a third-party plugin**，
粘贴本仓库 `plugin/` 的绝对路径安装并启用。插件会写 `~/.dsh-status/bridge.json` 并自动拉起 App。

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
- `plugin/` — DSH 插件 bundle：Host 薄桥 + Client 状态聚合（含 `node --test` 测试与开发用 dev-host）
- `mock/` — mock 桥（P0 演示 / App 联调）
- `scripts/dev-*` — 开发辅助（见各脚本头部说明）
- `scripts/` — 构建、安装、演示、协议测试
- `docs/` — 设计文档与预览图

## 文档

- [docs/previews/README.md](docs/previews/README.md) — 图标/面板预览图说明
- `STATUS.md` — 当前状态与下一步（**每轮工作后更新**）
- `AGENTS.md` — 给 agent 的固定上下文

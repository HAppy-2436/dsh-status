# dsh-status

> macOS 菜单栏常驻工具：图标旁数字 = DeepSeek Harness 中「待回答 + 已完成 + 已停止」的会话数；
> 单击弹出面板，只列非空闲会话（运行中 / 已完成 / 已停止 / 待回答），点击某行跳到 DSH 主窗口并打开该会话。
> 面板与设置窗口按 **macOS 26/27（Liquid Glass）原生规范**重做：无箭头自定义 NSPanel + 系统玻璃材质、
> 系统语义色与字号；设置窗口为标准 NSWindow + 原生 grouped Form。

## 当前状态（2026-11-06）

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
  - 完全空闲时显示 DeepSeek 鲸鱼 Logo。
  - 面板：**自定义无箭头 NSPanel**（330pt 宽、16pt continuous 圆角、顶边贴住菜单栏下沿），
    Liquid Glass（`NSGlassEffectView(.regular)`，不设 tint）/ 经典磨砂 / 实色可切；
    **扁平会话列表**（不按状态分组，最近一次状态变化在上）+ 行首红/黄/蓝/绿状态圆点；
    子智能体默认折叠（父行**行尾**显示「数量 + 下箭头」，点它展开/收起、展开时箭头转成上箭头；
    该按钮有独立悬停胶囊、便于点击；无子会话的行行尾是右箭头 `chevron.right`，点卡片任意位置跳转会话）；
    圆角阶梯（面板 16 continuous 超椭圆 / 行与整块高亮 12 / 子行 8 / 行尾按钮 5；12 是「更圆」的视觉偏好，
    比严格同心值 8 再大 4），
    动效对齐 macOS：hover 0.12s、箭头 0.22s 旋转、子行错班淡入、面板高度 0.22s 跟随，且全部尊重「减弱动态效果」；
    **空闲 / 未连接时面板缩成一块 330×68 的大按钮**（鲸鱼 + 「全部空闲」/「未连接」，居中），
    点面板任意位置就打开 DSH —— 不显示副标题、说明文字或额外的「打开 DSH」按钮；
    footer 一行 = 连接状态点 + 设置 / 勿扰 / 退出；面板打开时状态项系统原生高亮；
    通知未授权时面板顶部可操作提示。
  - 勿扰：面板底部月亮按钮（总开关，持久化）；开启时静音全部系统通知，设置页单项开关保留。
  - 设置窗口：标准 NSWindow（540×640、可缩放、位置记忆、关闭不退出）+ 原生 `Form(.grouped)`；
    分区「菜单栏图标 / 显示 / 项目显示 / 通知 / 面板 / 通用」，24pt 图标块 + 原生开关/弹出按钮；
    恢复默认带二次确认，页脚显示版本与连接状态。
  - SSE 桥客户端、未连接态、通知；配套 mock 桥可脱离 DSH 演示；
    设计预览图与真机截图在 [`docs/previews/`](docs/previews/README.md)。
- **P1 已实现并真机接通（2026-11-05）**：DSH 插件（Host 薄桥 + Client 状态聚合 + 跳转命令）已在 DSH 安装启用，
  真实状态推送正常；待验证「点击会话行跳转」与「通知点击」。
- 图标系统 v5（鲸鱼 + 单色优先级环 + 运行中彗星弧）；进一步图标改进建议见
  [docs/icon-suggestions.md](docs/icon-suggestions.md)。

### 圆环同心性核查结论（2026-11-06）

**结论：几何上全部同心（偏差 0.00px），但双层环在视觉上确实会「看起来外圈略偏右」。**
逐项测量（2x 渲染 44×44px，复现方法见下「圆环同心性核查」一节）：

| 元素 | 圆心（pt，画布中心 = 11,11） | 判定 |
| --- | --- | --- |
| 外环（红/黄/绿/蓝整环，静态图） | (11.000, 11.000) | 同心 |
| 内层轨道（16% 中性细环） | (11.000, 11.000) | 同心 |
| 外环扫入过渡层（CAShapeLayer，`button.bounds` 中心） | (11.000, 11.000) | 同心 |
| 彗星弧（CA 层，`bounds.midX/midY`） | (11.000, 11.000) | 同心 |
| 未连接虚线环 | (11.065, 10.955) | 虚线相位造成的分布偏移，非几何偏心 |
| 中心数字 | 字形质心（面积质心 + 墨迹居中） | 有意为之的视觉居中 |

「偏右」的视觉成因（外圈被误看成偏心，实际是**内层视觉重心偏右**）：
1. **中性影子的视觉不对称**：22pt 画布中央的黑色不是背景色，而是中性层内容阴影的扩散光晕，能量中心约在 (13.2, 12.9)。
2. **内层亮弧的静止位置在右上**：只运行中 / 双层的内层彗星弧，静态帧固定起始于 90°（正上方）并顺时针铺开，
   落点偏右上；动态旋转时也不是对称的整环，整圈的「视觉重量」在右上更重。
3. **彗星弧旋转层的支点比静态层偏右 0.5pt**：静态图 22pt 画在 44px 位图上；
   CA 层用 `button.bounds.midX` 作为支点，按钮宽度是奇数像素（如 31px → midX = 15.5），
   与静态层的 22pt 中心（约 15.0）差 0.5px。肉眼通常看不出来，但与 2 同向叠加会放大「外圈偏右」。

可选修正（未实施，需用户确认）：把 CA 层支点取整到与静态图一致（`round(bounds.midX)`）；或把内层彗星的静态帧起点
改为对称/上下镜像的落点，降低右上偏重。

**复现**：`swift build -c release` 后 `.build/release/DSHStatusBar --render-previews /tmp/prev`，
`docs/previews/icon-preview-*.png` 里含全部双层/单层/运行中/未连接状态；几何参数集中在
`MenuBarIconRenderer.center / outerRadius / innerRadius`（`center` 只有一处，全部圆环共用）。


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

## 开源致谢

- 面板窗口/材质实现参考 [Status Trio](https://github.com/lingyired/status-trio)（Apache-2.0，
  Copyright 2026 lingyired）：无边框 `NSPanel` + `NSGlassEffectView(.regular)`（不设 tint）+ 系统窗口阴影 + 16pt 圆角，
  内容宿主放在 `glass.contentView` 内；本仓库按 Apache-2.0 条款保留出处与许可说明。

## 架构

```
DSH renderer ── 插件 Client 半（读 uiSession 状态）──┐
                                                    ├─ 本机 HTTP/SSE ── 原生菜单栏 App
DSH Host ── 插件 Host 薄桥（bridge.json + 路由）────┘
```

- 协议：[docs/protocol.md](docs/protocol.md)
- 产品设计：[docs/design.md](docs/design.md)
- App / 图标设计规范：[docs/app-design.md](docs/app-design.md)
- 原生 UI 实测与 HIG 依据：[docs/research/macos-ui-conventions.md](docs/research/macos-ui-conventions.md)
- 本次面板/设置重设计契约：[docs/ui-redesign-spec.md](docs/ui-redesign-spec.md)
- 图标设计建议：[docs/icon-suggestions.md](docs/icon-suggestions.md)
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

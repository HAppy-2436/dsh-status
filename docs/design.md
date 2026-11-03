# dsh-status 设计方案

> 状态：**提案，待确认**（2026-11-03）
> 目标：在 macOS 菜单栏常驻一个图标，实时显示 DeepSeek Harness 各项目（workspace）的运行状态，
> 支持单击浮窗、双击打开主页面、状态切换系统通知，并能在浮窗里直接回答问题。

## 1. 结论

方向可行，值得做。但有一个架构性约束：

**DSH 桌面版没有对外的 macOS 菜单栏 / 托盘接口，纯插件做不了菜单栏图标。**
所以方案必须拆成两部分：

- **DSH 插件（中枢）**：运行在 DSH Host / Client 中，负责取状态、执行动作、对外暴露一个本地桥。
- **原生菜单栏 App（门面）**：Swift/AppKit 写的独立 `.app`，负责 NSStatusItem、浮窗、通知。

两者通过本机回环 HTTP + 共享 token 通信。安装时用户只需两步：装插件包（DSH 设置 → 插件 → 添加本地目录）、
构建并首次授权菜单栏 App（`install.sh` 自动完成）。

## 2. 已验证的 DSH 事实

基于本机 `DeepSeek Harness 0.2.1-rc.5`（desktop profile）的源码 / 文档核实：

| 事实 | 依据 |
| --- | --- |
| macOS 没有菜单栏 API；Desktop 的 Tray 是 Windows 专用 | `app.asar/lib/main.js` 中 `// Windows system tray` |
| Desktop 注册了 `dsh://open` 深链，可唤起主窗口 | `main.js` `setAsDefaultProtocolClient("dsh")` |
| 插件体系是 Cordis（Host + Client 两半），支持本地目录安装、HMR | `dsh-plugin-manager` / `dsh-client-ui-plugin-manager` 文档 |
| `desktop` profile 由 Electron 独占管理，CLI 不能装插件；必须走 GUI | `dsh --profile desktop --dump-config` 报错 |
| Host 侧可拿到 workspace 列表与会话归属 | `ctx.workspaceRegistry.list()` |
| 会话实时状态：`ctx.agents.get(sessionId).status === 'running'` | `dsh-api-session-controller` `summaryFor()` |
| 会话事件全局可订阅：`turn/start`、`turn/end`（reason.kind: completed / aborted / error / blocked / max-tokens） | `dsh-session` / `dsh-agent-loop` |
| 提问状态可从投影读：`sessionProjections.stateOf(session, 'userQuestions')` | `dsh-user-questions` |
| 审批有审计事件：`approval/asked` / `approval/decided` | `dsh-user-approval` |
| 可停止运行：`agent.cancel()`；后台 job 另有 `ctx.jobs` | `dsh-agent` / `dsh-jobs` |
| 「已超时/继续中」的问题可以 Host 侧直接回答：`ctx.userQuestions.answer(agent, callId, answer)` | `dsh-user-questions` |
| **前台阻塞中的问题/审批只能由 Client 侧回传答案**（Host→Client waterfall 事件，Web UI 用 `ctx.remote.$on` 接管） | `dsh-api-remotes` 转发 `user-questions/request`、`approval/request` |
| 本地 Web 服务已存在（Desktop 也跑，renderer 经 Electron IPC 转发）；插件可挂路由 | `dsh-host-webserver`、`dsh-client-connection` |

最后一条是方案里唯一的硬骨头，见 §7。

## 3. 状态模型

「项目」= DSH workspace（`~/Developer/projects/<slug>` 这类目录）。一个项目可以有多个会话，状态取聚合。

| 状态 | 判定 | 菜单栏表现 |
| --- | --- | --- |
| 需要回答 | 有待答 `user_questions` 或待批准 request | 🔴 最高优先级，数字角标 |
| 运行中 | 任一会话 `agent.status === 'running'`（含工具执行 / 子 agent） | 🔵 呼吸动画 |
| 异常 | `turn/end` reason.kind 为 error / blocked | 🟠 未读 |
| 已停止 | `turn/end` reason.kind 为 aborted | ⚪️ 未读 |
| 已完成 | `turn/end` reason.kind 为 completed，且未读 | 🟢 未读 |
| 空闲 | 无运行、无未读结果 | ⚫️ 常态 |

- 聚合优先级：需要回答 > 运行中 > 异常 > 未读完成/停止 > 空闲；角标数字 = 需要关注的项目数。
- 「已完成 / 已停止」是**未读态**：在浮窗里展开看过、或超过 N 分钟（默认 10，可配置）后回落空闲。
- 摘要内容：会话标题 + 最后一条 assistant 文本（截断）+ 本次 turn 用时 / 工具数 / 模型。

## 4. 交互

- **单击图标** → NSPopover 浮窗：
  - 项目列表：状态圆点 + 项目名 + 一句话摘要；点开某项目看详情。
  - 运行中：当前动作（最近工具调用 / 正在生成）、已耗时。
  - 已完成 / 已停止：摘要、耗时、token。
  - 需要回答：直接显示问题选项 / 文本框 / 审批按钮（阶段 P2）。
  - 底部：全部未读清除、打开主页面、设置。
- **双击图标** → `dsh://open`（或 `open -a "DeepSeek Harness"`）唤起主窗口。
  - 代价：单击/双击共存需要约 250ms 的单击延迟；这是 macOS 菜单栏的常见取舍，可接受。
- **通知**：状态切换时发 UNUserNotificationCenter 通知，点击 → 打开主页面。
  - 按项目聚合、去抖（同一项目 3s 内合并）；按项目静音；首次使用申请通知权限。
- **右键**：打开全部 / 仅在需要时提醒 / 退出。

## 5. 组件与数据流

```
DSH Host 进程
 ├─ 插件 Host 半（@dsh-status/bridge）
 │    ├─ 订阅 workspace / agents / session 事件，维护状态模型
 │    ├─ 注册 /dsh-status/* 路由（用 ctx.connection.admit 校验浏览器同源）
 │    ├─ 写 ~/.dsh-status/bridge.json（端口 + 本地 token）
 │    └─ 启动 / 监视菜单栏 App（可配置 appPath）
 └─ 插件 Client 半（仅 P2 需要）
      └─ 接管 user-questions/request、approval/request 的 waterfall，
         把问题中继给 App，把 App 的答案回传（相当于第二个 Web 标签页）

原生 App：DSHStatusBar.app
 ├─ NSStatusItem / NSPopover / UNUserNotificationCenter
 ├─ 连 Host 桥（SSE 收状态、POST 发命令），断线自动重连
 └─ open "dsh://open" 唤起主页面
```

- 插件安装：DSH 侧边栏 → Plugins → Add plugin → 填插件包绝对路径（已确认支持本地目录 + HMR）。
- App 安装：`install.sh` 用 `swift build` 构建，放入 `~/Applications`，ad-hoc 签名；插件在激活时拉起。

## 6. 分期

| 阶段 | 内容 | 产出 |
| --- | --- | --- |
| P0 | Swift 菜单栏骨架 + 假数据桥：图标、浮窗、通知、双击、断线重连 | 可点可看的原型 |
| P1 | 插件 Host 半 + 真实状态/摘要/通知 + 停止任务 | 日常可用的 MVP |
| P2 | Client 半：浮窗内直接回答 / 批准；通知点击定位会话 | 完整目标 |
| P3 | 打磨：设置页、登录项、图标样式、多项目 layout、静音规则 | 稳定版 |

## 7. 风险与对策

1. **直接回答（唯一硬骨头）**：前台阻塞中的问题/审批，答案必须由 Client（web 页面）经 waterfall 回传，
   原生 App 无法直接调 Host 内部 API。
   - 对策 A（推荐，P2）：插件带一个 Client 半，作为「第二个客户端」注册同样的 `$on` 监听，中继给 App。
     与多开浏览器标签页的语义一致，Web UI 不受影响。
   - 对策 B（P1 可先做）：只对「已超时 / 继续中」的问题用 Host 侧 `userQuestions.answer` 直接回答；
     前台阻塞中的问题先显示 + 一键跳到 DSH 作答。
2. **单击/双击延迟**：可接受，或在设置里提供「单击直接打开主页面、不显示浮窗」选项。
3. **通知权限与签名**：本地 ad-hoc 即可；分发需 notarize。
4. **DSH API 变动**：rc 版本可能调整插件 API；把取数集中在插件 Host 半的一层里，App 不感知 DSH 细节。
5. **通知轰炸**：聚合 + 去抖 + 每项目静音，默认只对「需要回答 / 已完成 / 已停止 / 异常」通知。

## 8. 待确认

1. 项目粒度：按 workspace 聚合（推荐）还是按会话逐条列出？
2. 直接回答：P1 先做「显示 + 跳转」（推荐，先拿到可用产品），P2 再上原生作答；还是第一版就要完整作答？
3. 是否按本方案开始 P0 + P1？

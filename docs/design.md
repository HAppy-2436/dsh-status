# dsh-status 设计方案（v2 · 简化版）

> **历史文档**：本文是 2026-11-03 的设计阶段记录。插件代码已于 2026-11-09 拆分为独立仓库
> [dsh-status-bridge](https://github.com/HAppy-2436/dsh-status-bridge)；实现细节以仓库代码与
> [docs/protocol.md](protocol.md) 为准。

> 状态：**提案 v2，待确认**（2026-11-03）
> 图标已在实现阶段按用户 v4 设计更新（空闲鲸鱼 / 外层介入环 + 内层运行弧），见 [docs/app-design.md](app-design.md)。
>
> v2 相对 v1 的简化：去掉双击语义、逐状态单击行为、摘要详情、浮窗内直接作答；
> 改为「数字角标 + 一个面板 + 点击跳转」。

## 1. 需求（v2）

- 菜单栏图标旁显示一个数字 = **待回答 + 已完成 + 已停止** 的会话总数（运行中、空闲不计）。
- 单击图标弹出面板，只列非空闲会话：运行中 / 已完成 / 已停止 / 待回答；空闲会话不显示。
- 点击面板某一行 → 跳到 DSH 主窗口并打开该会话。
- （v1 保留项，待确认）状态切换系统通知，点击打开主页面。

## 2. 结论与架构

架构约束与 v1 相同：**DSH 桌面版没有 macOS 菜单栏 API，纯插件做不出图标**。所以仍是两部分：

- **DSH 插件**（Host 桥 + Client 状态）：取状态、执行跳转。
- **原生 Swift 菜单栏 App**：图标、数字、面板、通知。

v2 的实现量大幅下降，原因见 §3：**状态模型 DSH 客户端已经算好了，直接复用**。

## 3. 关键发现：DSH 客户端已有现成状态

`@deepseek-ai/dsh-client-ui-session` 在 Client 侧暴露了 `ctx.uiSession.sessionStatus`
（`getSnapshot()` / `subscribe()`，`Map<sessionId, SessionStatus>`）：

| 字段 | 含义 | 直接对应的需求状态 |
| --- | --- | --- |
| `running` | 会话正在跑 turn | 运行中 |
| `pendingInteraction` | 待回答的问题 / 待批准（含 `kind`、`questions`） | 待回答 |
| `completionUnread` | 本次运行结束后用户还没看过该会话 | 已完成 / 已停止 |

配套的现成能力：

| 需要 | 现成 API |
| --- | --- |
| 会话列表、标题、cwd、更新时间 | `ctx.sessions.list.getSnapshot()`（`items[]`：`sessionId`、`title`、`cwd`、`updatedAt`、`parentSessionId`、`blank`…） |
| 项目（workspace）列表与归属 | `ctx.workspaces.list.getSnapshot()`（`workspaceIds`、`titles`、`archivedSessionIds`…） |
| 跳转到会话 | `ctx.uiWorkspace.openSession(sessionId)` |
| 唤起主窗口 | `open "dsh://open"`（Desktop 已注册该 scheme） |
| 运行结束原因（区分已完成 / 已停止） | Host 侧 `ctx.on('session/event')` 的 `turn/end.reason.kind`：`completed` / `aborted` / `error` / `blocked` / `max-tokens` |

`completionUnread` 的清除规则正好符合直觉：用户打开该会话（成为主视图）就清；
`pendingInteraction` 则要回答/批准后才清。

代价是：**正在看的会话跑完时不会置 `completionUnread`**（`observeRunning` 里
`!isMain(sessionId)` 才 add），于是既没有 completed 行、也没有状态跃迁通知。0.4.3 起由桥补一条
`SessionNotice`（Client 上报 `focused` 列表，Host 在收到该会话 `turn/end` 时生成）：
照常弹横幅 / 提示音，但不产生面板行、不计入 counts / 角标（协议见 `protocol.md` §2）。

## 4. 状态判定与计数

```
待回答   = pendingInteraction != null
运行中   = running == true（且不参与计数）
已完成   = completionUnread && lastTurnOutcome == completed
已停止   = completionUnread && lastTurnOutcome == aborted / blocked
（焦点会话：不进 counts，靠 notices 发通知，见 §3 末）
异常     = completionUnread && lastTurnOutcome == error（v2 先并入「已停止」或单独标红，待定）
空闲     = 其余（面板不显示）
```

- **角标数字** = `pendingInteraction` 数 + `completionUnread` 数。
- **不清零规则**：打开面板本身不清零；点某一行跳过去后，DSH 自己会清掉该会话的
  `completionUnread`，数字自然减一；待回答必须回答/批准后才减。
- **过滤**：不显示空闲会话、`parentSessionId` 存在的子会话、已归档会话、空（blank）会话。
- **已知限制**：`completionUnread` 是 Client 进程内的内存态，DSH 重启后归零（与 DSH 自带提醒一致）；
  多窗口/多标签同时打开时各自维护，桥接取最近活跃的那个 Client 的快照（MVP 先按单窗口假设）。

## 5. 面板与交互

```
┌──────────────────────────────────────┐
│  ● 待回答 (1)                         │
│    example-app · 「选择实现方案」 [红] │   ← 点击跳转
│  ● 运行中 (2)                         │
│    example-app · 正在执行命令…  02:14 │   ← 显示实时动作/耗时
│  ● 已完成 (1)                         │
│    example-lab · 3 分钟前             │
│  ● 已停止 (1)                         │
│    example-tools · 1 小时前           │
├──────────────────────────────────────┤
│  打开 DSH            通知 ⏰    设置   │
└──────────────────────────────────────┘
```

- 分组顺序：待回答 → 运行中 → 已完成 → 已停止；组内按更新时间倒序。
- 行内容：状态点 + 项目名 · 会话标题（截断）+ 右侧辅助信息
  （待回答显示问题标题；运行中显示当前动作/已耗时；完成/停止显示相对时间）。
- 行点击：`open "dsh://open"`（唤起窗口）+ 通知 Client 桥执行 `openSession(sessionId)`。

### 5.1 跳转的实现细节（已验证）

- `ctx.uiWorkspace.openSession(sessionId)` 就是 Web UI 会话列表的导航入口：
  `replaceMain()` → `sessions.retain(sessionId, {source:'mainView'})` → 写 selection → `layout.selectPanel(null)`。
  调用后该会话变为主视图，DSH 自己的 `completionUnread` 随之清除（角标数字自动减一）；
  若是待回答会话，聊天区会自动展开问题卡片，可直接作答。
- 命令链路：App → `POST /dsh-status/commands {openSession: id}` → Host 桥排队 → Client 半长轮询取走 →
  `openSession(id)`。App 同时 `open "dsh://open"` 唤起窗口。
- **窗口隐藏也能跳**：DSH 关闭窗口是 hide（`window.on('close')` preventDefault），renderer 与插件仍存活。
- **完全退出 DSH**：App 记住最后一次点击命令，等桥重连后补发；DSH 启动后自动落到目标会话。
- **避免后台节流**：Client→Host 用事件驱动 push（微任务合并，不用 `setTimeout`），Host→Client 用长轮询，
  防止窗口隐藏时 Chromium 定时器节流导致命令延迟。
- **风险**：`uiWorkspace` 是 DSH Client 内部服务（非公开稳定 API），rc 升级可能变；
  封装在 Client 半一层里，降级方案 = 只唤起主窗口（`dsh://open`）。
- 图标：鲸鱼 + 双层环；外层=待答黄/停止红/完成绿（按数量渐变），内层=运行中动态弧（详见 app-design.md）。
- 单击即开面板，没有双击延迟问题；面板再次点击图标关闭。

## 6. 组件与数据流

```
DSH renderer（Desktop 主窗口 / Web 标签页）
 └─ 插件 Client 半
      ├─ 订阅 ctx.uiSession.sessionStatus + ctx.sessions + ctx.workspaces
      ├─ 聚合出 { sessions[], counts, updatedAt } 快照
      ├─ POST /dsh-status/state  → Host 桥
      ├─ 长轮询 GET /dsh-status/commands ← Host 桥
      ├─ 执行 openSession(sessionId)（ctx.uiWorkspace）
      └─ 如需「已完成 vs 已停止」：接收 Host 侧 turn/end 结果映射

DSH Host 进程
 └─ 插件 Host 半（薄桥）
      ├─ 注册 /dsh-status/* 路由（ctx.webServer.register，auth: 'anonymous' + 自行鉴权）
      ├─ 全局监听 session/event，维护 lastTurnOutcome[sessionId]
      ├─ 写 ~/.dsh-status/bridge.json（端口 + 本机 token）
      └─ 启动 / 监视 DSHStatusBar.app

原生 App：DSHStatusBar.app（Swift/AppKit）
 ├─ NSStatusItem + NSPopover（状态排序、行点击）
 ├─ SSE/长轮询 Host 桥，断线重连
 ├─ UNUserNotificationCenter 通知（可选）+ 点击打开主页面
 └─ open "dsh://open"
```

- **插件安装**：DSH 侧边栏 → Plugins → Add plugin → 填插件包绝对路径（支持本地目录 + HMR）。
- **App 安装**：`install.sh` 构建放入 `~/Applications`，ad-hoc 签名；Host 插件激活时拉起。
- **桥安全**：只绑 127.0.0.1；路由向 DSH 声明 `auth: 'anonymous'`（DSH 0.2.3 起 web server
  默认要求登录态，会 401 掉原生 App），由桥自己鉴权：浏览器侧用 `ctx.connection.admit` 校验同源
  （DSH 0.2.2-rc.2 起该调用要放在声明 `connection.authentication` 的子 fiber 里，否则服务读取
  被拒、浏览器请求全 401），App 侧用 `~/.dsh-status/bridge.json` 里的随机 token + 回环 Host。

## 7. 分期

| 阶段 | 内容 | 产出 |
| --- | --- | --- |
| P0 | Swift 菜单栏骨架 + 假数据（图标/数字/面板/点击/SSE 重连） | 可看可点的原型 |
| P1 | Client 状态聚合 + Host 薄桥 + 点击跳转 | 核心功能可用 |
| P2 | 通知（待回答必发、完成/停止可选）+ 设置（开机启动、静音）+ 图标样式 | 日常可用 |
| P3（可选） | 面板内直接回答/批准（需 Client waterfall 中继，即 v1 的硬骨头） | 增强 |

## 8. 风险

1. **已完成/已停止的区分**依赖 Host 侧 `turn/end` 结果缓存；插件启动前已结束的会话拿不到原因，先按「已完成」处理。
2. `completionUnread` 是 Client 内存态：DSH 重启归零；多窗口快照可能不一致（MVP 取最新推送）。
3. 菜单栏 App 的通知权限、签名；分发需 notarize（本机 ad-hoc 即可）。
4. 插件 API 是 rc 版本，后续变动风险集中在 Client 半的取数层。

## 9. 待确认

1. 通知还要不要？建议：待回答发通知、已完成/已停止默认不发（角标已提示），设置里可开。
2. 「异常结束（error）」单独算一个状态，还是并入已停止？
3. 确认后是否直接开始 P0 + P1？

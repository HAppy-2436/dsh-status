# dsh-status 设计方案（v2 · 简化版）

> 状态：**提案 v2，待确认**（2026-11-03）
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

## 4. 状态判定与计数

```
待回答   = pendingInteraction != null
运行中   = running == true（且不参与计数）
已完成   = completionUnread && lastTurnOutcome == completed
已停止   = completionUnread && lastTurnOutcome == aborted / blocked
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
│    erhu · 「选哪种调音方案？」   [红]  │   ← 点击跳转
│  ● 运行中 (2)                         │
│    dsh-status · 正在执行 bash…  02:14 │   ← 显示实时动作/耗时
│  ● 已完成 (1)                         │
│    stability · 3 分钟前               │
│  ● 已停止 (1)                         │
│    homebrew · 1 小时前                │
├──────────────────────────────────────┤
│  打开 DSH            通知 ⏰    设置   │
└──────────────────────────────────────┘
```

- 分组顺序：待回答 → 运行中 → 已完成 → 已停止；组内按更新时间倒序。
- 行内容：状态点 + 项目名 · 会话标题（截断）+ 右侧辅助信息
  （待回答显示问题标题；运行中显示当前动作/已耗时；完成/停止显示相对时间）。
- 行点击：`open "dsh://open"`（唤起窗口）+ 通知 Client 桥执行 `openSession(sessionId)`。
- 图标：模板图标（SF Symbol）+ 数字文本；有任何待回答时数字用红色，否则橙色，0 时只显示图标。
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
      ├─ 注册 /dsh-status/* 路由（ctx.webServer.register，admit 校验浏览器请求）
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
- **桥安全**：只绑 127.0.0.1；浏览器侧路由用 `ctx.connection.admit` 校验同源；App 侧用
  `~/.dsh-status/bridge.json` 里的随机 token。

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

# DSH 通知与状态：方案对比

DSH 有会话列表，但你在别的窗口工作时，仍然需要知道：会话跑完了没有、是不是出错了、
是不是在等你回答。社区里已经有一些插件在解决这个问题，侧重点不同。这一页把已知的选项
放在一起对比，帮你选最小够用的那个。

> DSH Status 是本项目。其他条目列出来是因为用户会问；具体行为与兼容性请以各项目 README
> 为准。它们都是非官方第三方工具。

| 方案 | 形态 | 多了什么 | 安装 |
| --- | --- | --- | --- |
| **DSH Status** | 原生 macOS App + DSH 插件 | 系统通知、菜单栏实时状态与角标、点击跳转、提示音、勿扰 | 从 [Releases](https://github.com/HAppy-2436/dsh-status/releases/latest) 下载 DMG，再 `dsh plugin --profile web add dsh-status-bridge` |
| `dsh-niao-message` | DSH 插件 | macOS 通知中心横幅，按「异常终止 / 需要你操作 / 正常完成」分类，可配点击目标 | `dsh plugin --profile web add dsh-niao-message` |
| `dsh-completion-notifier` | DSH 插件 | 一轮对话完成时的浮窗/提示音 | `dsh plugin --profile web add dsh-completion-notifier` |
| `dsh-notch` | DSH 插件 | Mac 刘海区域的会话状态、审批与提问 | `dsh plugin --profile web add dsh-notch` |
| `dsh-notify-tray` | DSH 插件 | 通知 + 托盘/状态栏图标，跨平台，带进度与花费 | `dsh plugin --profile web add dsh-notify-tray` |

## 怎么选

- **只想要一个完成横幅**：`dsh-niao-message` 或 `dsh-completion-notifier` 最轻。
- **想要刘海/托盘常驻，或需要 Windows/Linux**：`dsh-notch` 或 `dsh-notify-tray`。
- **想要原生 macOS 菜单栏面板：实时状态、需要你的角标、点击跳转、提示音、勿扰**：
  DSH Status。
- **不想再装一个 App**：DSH Status 的桥插件现在可以单独用，提供基础通知；App 是可选升级。
- **用 Windows 或 Linux**：DSH Status 只支持 macOS，选 `dsh-notify-tray` 等跨平台方案。

## DSH Status「只装插件」是什么样

桥插件是可直接安装的部分。不装 App 时，它在每次有意义的状态变化时发一条 macOS 通知：

- 会话等待输入或审批；
- 一轮对话完成；
- 一轮对话出错停止。

优先走 `terminal-notifier`，没装则用 `osascript`。点击跳转、菜单栏面板、提示音与勿扰
需要 App。App 连上后，插件停止发 fallback 通知，避免重复。

## 两条命令装齐

```bash
# 1) 插件（必需）
dsh plugin --profile web add dsh-status-bridge

# 2) App（可选，推荐）
# 从 https://github.com/HAppy-2436/dsh-status/releases/latest 下载 DMG
```

App 首次打开需要 README 里的 Gatekeeper 放行步骤；目前未公证。

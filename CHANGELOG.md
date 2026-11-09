# Changelog / 更新日志

本项目所有值得注意的变更都记录在这里，中英双语。
All notable changes to this project are documented here, in Chinese and English.

格式遵循 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。
This project adheres to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and [Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-11-09

### 中文

#### 新增
- 首个公开预览版本（macOS 菜单栏 App `DSH Status`）：
  - **菜单栏图标**：待回答 / 运行中 / 已完成 / 已停止四态，数字角标，状态切换动效
    （外环扫入/收回、数字里程表滚动、彗星弧变形），遵循「减弱动态效果」与低电量模式；
  - **面板**：会话列表、子智能体展开/收起、点击会话跳到 DSH 对应会话；
  - **通知**：待回答 / 已完成 / 已停止通知，支持勿扰模式；
  - **提示音**：App 内独立音量，内置 DSH 提示音 / 系统声音 / 自定义音频；
    可走「App 直接播放」或「系统通知音」（跟随系统专注模式）；
  - **后台**：「运行时阻止睡眠」开关（默认关，有会话运行且已连接时阻止闲置系统睡眠）；
  - **设置页**：应用/图标/通知/提示音/后台分区，显示版本与连接状态；
  - 调试与验收入口：`--render-previews`、`--self-test-sound`、`--test-sound` 等。
- DMG 发布产物：`DSH-Status-0.2.0.dmg` + `.sha256`，内含中英双语 `INSTALL.txt`。

#### 变更
- DSH 插件拆分到独立 npm 包 [`dsh-status-bridge`](https://github.com/HAppy-2436/dsh-status-bridge)；
  App 与插件通过 `~/.dsh-status/bridge.json` 通信。
- 许可证：MIT（Copyright © 2026 HAppy-2436）；第三方许可见 `LICENSES/`。

#### 说明
- 0.2.0 的 DMG 为 ad-hoc 签名、**未公证**：首次打开需右键 →「打开」，或到
  「系统设置 → 隐私与安全性」点「仍要打开」；详见 DMG 内 `INSTALL.txt` 与
  [`docs/RELEASE.md`](docs/RELEASE.md)。

### English

#### Added
- First public preview release (macOS menu bar app `DSH Status`):
  - **Menu bar icon**: pending / running / completed / stopped states, badge count and
    animated transitions (ring sweep, odometer-style number roll, comet-arc morphing)
    that respect Reduce Motion and Low Power Mode;
  - **Panel**: session list, sub-agent disclosure, click a session to open it in DSH;
  - **Notifications**: pending / completed / stopped, with a Do Not Disturb switch;
  - **Notification sounds**: independent in-app volume, built-in DSH chime / system sounds /
    custom audio; delivered either in-app or via the system notification sound
    (honours system Focus modes);
  - **Background**: "prevent idle system sleep while sessions are running" switch
    (off by default);
  - **Settings**: app/icon/notification/sound/background sections with version and
    connection state;
  - Debug and verification entry points: `--render-previews`, `--self-test-sound`,
    `--test-sound`, and more.
- DMG release artifacts: `DSH-Status-0.2.0.dmg` plus `.sha256`, with a bilingual
  `INSTALL.txt` inside.

#### Changed
- The DSH plugin was split into the standalone npm package
  [`dsh-status-bridge`](https://github.com/HAppy-2436/dsh-status-bridge); the app talks to
  it through `~/.dsh-status/bridge.json`.
- License: MIT (Copyright © 2026 HAppy-2436); third-party licenses are listed in `LICENSES/`.

#### Notes
- The 0.2.0 DMG is ad-hoc signed and **not notarized**: on first launch use
  right-click → Open, or click "Open Anyway" in System Settings → Privacy & Security.
  See `INSTALL.txt` inside the DMG and [`docs/RELEASE.md`](docs/RELEASE.md).

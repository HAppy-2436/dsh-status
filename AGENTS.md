# AGENTS.md — 仓库固定上下文

面向在本仓库工作的 coding agent。用户文档见 `README.md` / `README.zh.md`；
`STATUS.md` 是维护者的内部工作日志（当前进度与下一步），不属于公开文档。

## 开始前

1. 读 `README.md` 了解产品，读 `STATUS.md` 顶部的 `next` 了解当前工作
2. `git status` 确认工作区状态

## 常用命令

```bash
bash scripts/build-app.sh    # release 构建 dist/DSHStatusBar.app（ad-hoc 签名，含提示音自检）
bash scripts/demo.sh         # mock 桥 + App，不依赖 DSH
bash scripts/test-bridge.sh  # 桥协议合约测试
bash scripts/release-dmg.sh  # 生成 DMG 发布产物
(cd app && swift build -c release)
```

## 约定

- App：Swift 5.9+ / macOS 13+，源码在 `app/Sources/DSHStatusBar`，无第三方依赖。
- 桥插件在独立仓库 `dsh-status-bridge` 维护，不要在本仓库新增插件代码；
  插件与 App 的通信协议见 `docs/protocol.md`。
- 改动行为或界面时，同步更新 `README.md`、`README.zh.md` 和相关 `docs/`。
- `docs/previews/*.png` 由 App 的 `--render-previews` 生成，优先重新生成而不是手改；
  另有多张真机截图，重截时注意保持文件名与用途一致。
- 不要提交构建产物（`dist/`、`.build/`）、凭据或本机绝对路径。
- 许可证：改编自 Status Trio 的代码为 Apache-2.0，DeepSeek 鲸鱼矢量路径为 MIT；
  涉及这些内容时同步维护 `THIRD_PARTY_NOTICES.md`、`NOTICE` 与 `LICENSES/`。

## 收尾

更新 `STATUS.md` 的 `updated` 与 `next`。

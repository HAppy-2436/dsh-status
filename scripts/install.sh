#!/usr/bin/env bash
# dsh-status 安装脚本（开发机用）：
#   1) 构建并安装菜单栏 App 到 ~/Applications
#   2) 打印 DSH 插件安装步骤
#
# 终端用户请从 GitHub Releases 下载 DMG 安装，无需运行本脚本。
#
# 用法：bash scripts/install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SRC="$ROOT/dist/DSHStatusBar.app"
APP_DST="$HOME/Applications/DSH Status.app"

echo "==> 构建 App"
bash "$ROOT/scripts/build-app.sh"

echo "==> 安装到 $APP_DST"
mkdir -p "$HOME/Applications"
if [[ -d "$APP_DST" ]]; then
  # 已运行的旧实例先退出，避免覆盖运行中的二进制
  pkill -f "Contents/MacOS/DSHStatusBar" 2>/dev/null || true
  rm -rf "$APP_DST"
fi
cp -R "$APP_SRC" "$APP_DST"
xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true
codesign --force --deep -s - "$APP_DST" >/dev/null 2>&1 || true

cat <<EOF

✅ App 已安装：$APP_DST

接下来安装 DSH 插件（Desktop profile 只能通过 GUI 安装）：
  1. 打开 DeepSeek Harness → 左侧边栏「插件」（Plugins）
  2. 点「添加插件」→「安装第三方插件」（Install a third-party plugin）
  3. 输入 npm 包名：dsh-status-bridge
     （npm 包发布前，可改为粘贴 Git 地址：github:HAppy-2436/dsh-status-bridge）
  4. 安装 → 完成后点「立即启用」（Enable now）
  5. 若提示需要重启，重启 DeepSeek Harness

插件激活后会：
  - 写 ~/.dsh-status/bridge.json
  - 自动拉起 /Applications/DSH Status.app 或 ~/Applications/DSH Status.app（若存在）
  - 菜单栏出现 DSH 图标；首次待回答消息会请求通知权限

只想先看界面效果（不装插件）：
  bash scripts/demo.sh

排查：
  - App 日志：启动时加 stdbuf 不适用；可临时用
      DSH_STATUS_BRIDGE_FILE=~/.dsh-status/bridge.json $APP_DST/Contents/MacOS/DSHStatusBar
    前台运行看输出
  - 协议自检：bash scripts/test-bridge.sh --file ~/.dsh-status/bridge.json --no-start
EOF

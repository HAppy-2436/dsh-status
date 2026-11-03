#!/usr/bin/env bash
# dsh-status 安装脚本（本机）：
#   1) 构建并安装菜单栏 App 到 ~/Applications
#   2) 打印 DSH 插件安装步骤
#
# 用法：bash scripts/install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SRC="$ROOT/dist/DSHStatusBar.app"
APP_DST="$HOME/Applications/DSHStatusBar.app"

echo "==> 构建 App"
bash "$ROOT/scripts/build-app.sh"

echo "==> 安装到 $APP_DST"
mkdir -p "$HOME/Applications"
if [[ -d "$APP_DST" ]]; then
  # 已运行的旧实例先退出，避免覆盖运行中的二进制
  pkill -f "DSHStatusBar.app/Contents/MacOS/DSHStatusBar" 2>/dev/null || true
  rm -rf "$APP_DST"
fi
cp -R "$APP_SRC" "$APP_DST"
xattr -dr com.apple.quarantine "$APP_DST" 2>/dev/null || true
codesign --force --deep -s - "$APP_DST" >/dev/null 2>&1 || true

cat <<EOF

✅ App 已安装：$APP_DST

接下来安装 DSH 插件（Desktop profile 只能通过 GUI 安装）：
  1. 打开 DeepSeek Harness → 左侧边栏「Plugins」（插件）
  2. 点「Add plugin / 添加插件」→ 选「Install a third-party plugin」
  3. 在包名输入框粘贴本地绝对路径：
       $ROOT/plugin
  4. Install → 安装完成后点「Enable now / 立即启用」
  5. 若提示需要重启，重启 DeepSeek Harness

插件激活后会：
  - 写 ~/.dsh-status/bridge.json
  - 自动拉起 ~/Applications/DSHStatusBar.app（若存在）
  - 菜单栏出现 DSH 图标；首次待回答消息会请求通知权限

只想先看界面效果（不装插件）：
  bash scripts/demo.sh

排查：
  - App 日志：启动时加 stdbuf 不适用；可临时用
      DSH_STATUS_BRIDGE_FILE=~/.dsh-status/bridge.json $APP_DST/Contents/MacOS/DSHStatusBar
    前台运行看输出
  - 协议自检：bash scripts/test-bridge.sh --file ~/.dsh-status/bridge.json --no-start
EOF

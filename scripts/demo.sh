#!/usr/bin/env bash
# dsh-status P0 一键演示：启动 mock 桥 + 菜单栏 App（不依赖 DSH 运行）。
#
# 用法：
#   bash scripts/demo.sh [--cycle]        # --cycle: 每 8s 推进一次状态，便于看变化
#   Ctrl-C 退出（会同时关掉 mock 和 App）
#
# 说明：mock 写入 ~/.dsh-status/bridge.mock.json，App 用 DSH_STATUS_BRIDGE_FILE 指向它，
#       不会干扰真实的 ~/.dsh-status/bridge.json（Lab/正式插件用）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
resolve_node() {
  local candidates=(
    "${NODE:-}"
    "$HOME/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/node/bin/node"
    "/Applications/DeepSeek Harness.app/Contents/Resources/runtime/primary-runtime/dependencies/node/bin/node"
  )
  for c in "${candidates[@]}"; do
    [[ -n "$c" && -x "$c" ]] && { echo "$c"; return; }
  done
  echo ""
}
NODE="${NODE:-$(resolve_node)}"
BRIDGE_FILE="${DSH_STATUS_BRIDGE_FILE:-$HOME/.dsh-status/bridge.mock.json}"
APP="$ROOT/dist/DSHStatusBar.app"

if [[ ! -x "$APP/Contents/MacOS/DSHStatusBar" ]]; then
  echo "==> 未找到 App，先构建：$APP"
  bash "$ROOT/scripts/build-app.sh"
fi

if [[ ! -x "$NODE" ]]; then
  echo "找不到 node：$NODE（可用 NODE=/path/to/node 覆盖）" >&2
  exit 1
fi

mkdir -p "$(dirname "$BRIDGE_FILE")"
MOCK_PID=""
APP_PID=""
cleanup() {
  [[ -n "$APP_PID" ]] && kill "$APP_PID" 2>/dev/null || true
  [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> 启动 mock 桥（bridge: $BRIDGE_FILE）"
"$NODE" "$ROOT/mock/bridge.mjs" --file "$(basename "$BRIDGE_FILE")" --dir "$(dirname "$BRIDGE_FILE")" "$@" &
MOCK_PID=$!
sleep 0.6

echo "==> 启动菜单栏 App"
DSH_STATUS_BRIDGE_FILE="$BRIDGE_FILE" "$APP/Contents/MacOS/DSHStatusBar" &
APP_PID=$!

cat <<'EOF'

菜单栏图标已出现（右上角）。
- 数字 = 待回答 + 已完成 + 已停止 的会话数（当前 mock 数据：1 待回答 + 1 已完成 + 1 已停止 = 3）
- 单击图标看面板；点击会话行会记录一条 openSession 命令（mock 不真正跳转，看终端日志）
- Ctrl-C 退出演示

EOF

wait "$APP_PID" 2>/dev/null || true

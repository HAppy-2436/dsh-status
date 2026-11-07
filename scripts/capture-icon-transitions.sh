#!/usr/bin/env bash
# 真机逐帧捕获菜单栏图标状态切换动画（调试/验收用）。
#
# 原理：启动带 `--test-icon-transitions` 的 App，App 会把它自己的状态项屏幕矩形
# 打印到 stderr（`capture-rect x y w h`，左上角原点、已含 6pt 边距），本脚本只捕获这一小块，
# 同时把每帧的墙钟时间写入 index.txt —— 事后即可按时间线逐帧量化（环扫入角度/数字位置/透明度等）。
#
# 用法：scripts/capture-icon-transitions.sh [输出目录] [倍速] [起始步] [步数]
#   · 输出目录默认 /tmp/dsh-icon-transitions
#   · 倍速默认 3（`DSH_STATUS_ANIM_SCALE`，越大越慢，便于抓中间帧）
#   · 起始步/步数用于只回放其中一段（例：只抓「换色」：起始 1 步数 2）
#
# 注意：会先 pkill 正在运行的 DSHStatusBar（含已安装的 ~/Applications/DSH Status.app），
# 捕获结束后如需恢复安装版菜单栏图标，重新打开 ~/Applications/DSH Status.app 即可。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-/tmp/dsh-icon-transitions}"
SCALE="${2:-3}"
START="${3:-0}"
COUNT="${4:-}"

BIN="$ROOT/app/.build/release/DSHStatusBar"
if [[ ! -x "$BIN" ]]; then
  echo "找不到 $BIN，先构建：bash scripts/build-app.sh" >&2
  exit 1
fi

pkill -f "Contents/MacOS/DSHStatusBar" 2>/dev/null || true
sleep 0.6
rm -rf "$OUT"
mkdir -p "$OUT/frames"

ARGS=(--test-icon-transitions)
if [[ -n "$COUNT" ]]; then
  ARGS+=("--test-icon-transitions=${START},${COUNT}")
elif [[ "$START" != "0" ]]; then
  ARGS+=("--test-icon-transitions=${START},")
fi

DSH_STATUS_ANIM_SCALE="$SCALE" "$BIN" "${ARGS[@]}" 2> "$OUT/timeline.log" &
APP_PID=$!

# 防止系统睡眠/显示器休眠导致 screencapture 静默失败（实测睡醒后中间帧全部缺失）。
CAFFEINATE_PID=""
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dims -w "$APP_PID" &
  CAFFEINATE_PID=$!
fi

# 等 App 报告状态项屏幕矩形
RECT=""
for _ in $(seq 1 200); do
  RECT="$(awk '/capture-rect/{print $5","$6","$7","$8}' "$OUT/timeline.log" 2>/dev/null || true)"
  [[ -n "$RECT" ]] && break
  sleep 0.05
done
if [[ -z "$RECT" ]]; then
  echo "未拿到 capture-rect，查看 $OUT/timeline.log" >&2
  kill "$APP_PID" 2>/dev/null || true
  exit 1
fi
echo "捕获区域：${RECT}（倍速 ${SCALE}）"

: > "$OUT/index.txt"
i=0
while kill -0 "$APP_PID" 2>/dev/null; do
  frame="$(printf 'frame-%04d.png' "$i")"
  ts="$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time')"
  echo "$ts $frame" >> "$OUT/index.txt"
  screencapture -x -R "$RECT" "$OUT/frames/$frame" 2>/dev/null || true
  i=$((i + 1))
done
wait "$APP_PID" 2>/dev/null || true
if [[ -n "$CAFFEINATE_PID" ]]; then
  kill "$CAFFEINATE_PID" 2>/dev/null || true
fi

echo "帧数：${i}"
echo "时间线：${OUT}/timeline.log"
echo "帧索引：${OUT}/index.txt"

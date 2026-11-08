#!/usr/bin/env bash
# 真机逐帧捕获菜单栏图标状态切换动画（调试/验收用）。
#
# 原理：启动带 `--test-icon-transitions` 的 App，App 会把它自己的状态项屏幕矩形
# 打印到 stderr（`button-frame x y w h`，Cocoa 屏幕坐标），本脚本**全屏截图**并记录每帧墙钟时间；
# 事后按 `button-frame` 推算图标区域再裁剪分析。全屏截图约 12fps、单帧 <100KB，比
# `screencapture -R` 区域截图更稳（实测区域截图在本机 CA 动画期间会出现错帧/缩放错乱）。
#
# 用法：scripts/capture-icon-transitions.sh [输出目录] [倍速] [起始步] [步数]
#   · 输出目录默认 /tmp/dsh-icon-transitions
#   · 倍速默认 3（`DSH_STATUS_ANIM_SCALE`，越大越慢，便于抓中间帧）
#   · 起始步/步数用于只回放其中一段（例：只抓「换色」：起始 1 步数 2）
#
# 产物：
#   timeline.log    App 的步骤时间线（含绝对时间戳 @epoch 与 button-frame 屏幕矩形）
#   index.txt       每帧墙钟时间 + 文件名
#   frames/*.png    全屏截图
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

# 显示器休眠时 screencapture 会静默产出全黑帧；`-u` 模拟一次用户活动把显示器唤醒。
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -u -t 4 &
  sleep 2.5
fi

# 锁屏时菜单栏不可见，捕获到的只是壁纸 —— 直接拒绝运行。
if ioreg -n Root -d1 -a 2>/dev/null | grep -A1 'IOConsoleLocked' | grep -q '<true/>'; then
  echo "屏幕已锁定：请先解锁，再重跑捕获脚本（否则 captures 只有锁屏壁纸）。" >&2
  exit 1
fi

# 全屏应用会隐藏菜单栏；切到 Finder（桌面 Space）保证菜单栏可见。
if command -v osascript >/dev/null 2>&1; then
  osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
  sleep 1.5
fi

rm -rf "$OUT"
mkdir -p "$OUT/frames"

if [[ -n "$COUNT" ]]; then
  ARGS=("--test-icon-transitions=${START},${COUNT}")
elif [[ "$START" != "0" ]]; then
  ARGS=("--test-icon-transitions=${START},")
else
  ARGS=(--test-icon-transitions)
fi

DSH_STATUS_ANIM_SCALE="$SCALE" "$BIN" "${ARGS[@]}" 2> "$OUT/timeline.log" &
APP_PID=$!

# 防止系统睡眠/显示器休眠导致 screencapture 静默失败（实测睡醒后中间帧全部缺失）。
CAFFEINATE_PID=""
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -dimsu -w "$APP_PID" &
  CAFFEINATE_PID=$!
fi

# 等 App 报告状态项屏幕矩形
FRAME_RECT=""
for _ in $(seq 1 200); do
  FRAME_RECT="$(awk '/button-frame/{print $5","$6","$7","$8}' "$OUT/timeline.log" 2>/dev/null || true)"
  [[ -n "$FRAME_RECT" ]] && break
  sleep 0.05
done
if [[ -z "$FRAME_RECT" ]]; then
  echo "未拿到 button-frame，查看 $OUT/timeline.log" >&2
  kill "$APP_PID" 2>/dev/null || true
  exit 1
fi
echo "状态项矩形：${FRAME_RECT}（倍速 ${SCALE}）"

: > "$OUT/index.txt"
i=0
while kill -0 "$APP_PID" 2>/dev/null; do
  frame="$(printf 'frame-%04d.png' "$i")"
  ts="$(perl -MTime::HiRes=time -e 'printf "%.3f\n", time')"
  echo "$ts $frame" >> "$OUT/index.txt"
  screencapture -x "$OUT/frames/$frame" 2>/dev/null || true
  i=$((i + 1))
done
wait "$APP_PID" 2>/dev/null || true
if [[ -n "$CAFFEINATE_PID" ]]; then
  kill "$CAFFEINATE_PID" 2>/dev/null || true
fi

echo "帧数：${i}"
echo "时间线：${OUT}/timeline.log"
echo "帧索引：${OUT}/index.txt"

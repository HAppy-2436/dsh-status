#!/usr/bin/env bash
# 人工验收：脚本化回放菜单栏图标的全部状态切换（51 步），用肉眼验收动画。
#
# 与 --test-icon-transitions 的区别：会先退出已安装的 App、结束后再自动打开，
# 避免菜单栏同时出现两个图标（验收时只需要盯一个）。
#
# 用法：scripts/replay-icon-transitions.sh [倍速] [起始步,步数]
#   · 倍速默认 2（慢放 2 倍，便于看清扫入/换道；1 = 原速，4~10 = 逐帧核对）
#   · 可选只回放一段（步号见下方清单），例如只看 M9 与 M14：
#       scripts/replay-icon-transitions.sh 2 3,4
#   · 需要逐帧截图/量化时用 scripts/capture-icon-transitions.sh（会全屏截图）
#
# 依赖：已构建 app/.build/release/DSHStatusBar（bash scripts/build-app.sh）
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$ROOT/app/.build/release/DSHStatusBar"
APP="$HOME/Applications/DSH Status.app"
SCALE="${1:-2}"
RANGE="${2:-}"

[[ -x "$BIN" ]] || { echo "找不到 $BIN，先构建：bash scripts/build-app.sh" >&2; exit 1; }
if ioreg -n Root -d1 -a 2>/dev/null | grep -A1 'IOConsoleLocked' | grep -q '<true/>'; then
  echo "屏幕已锁定：验收动画需要看着菜单栏，请先解锁再运行。" >&2
  exit 1
fi

# 回放结束后恢复已安装版菜单栏图标（用户取消也算）。
restore() {
  if [[ -d "$APP" ]]; then
    open "$APP" >/dev/null 2>&1 || true
  fi
}
trap restore EXIT

pkill -f "Contents/MacOS/DSHStatusBar" 2>/dev/null || true
sleep 0.8

STEPS=51
if [[ -n "$RANGE" ]]; then
  echo "==> 回放片段：步 ${RANGE}（倍速 ${SCALE}×）"
  echo "    终端会打印每一步名字，对照行号即可。"
  ARGS=("--test-icon-transitions=${RANGE}")
else
  echo "==> 回放全部 51 步状态切换（倍速 ${SCALE}×，约 $(( STEPS * 115 * ${SCALE%.*} / 100 )) 秒）"
  ARGS=(--test-icon-transitions)
fi

cat <<'TIPS'
    重点观察（步号 → 预期）：
      · 运行中→已完成（M9，步 4）：白色彗星弧先熄 → 彩环 12 点顺时针扫入 → 数字最后落定；
        全程无整块跳、无双环、无环闪空，总时长约 0.6s（2× 慢放约 1.2s）。
      · 数字 3→2（M14，步 14）：环应保持亮度不闪（本轮修复项）；数字上/下滚 ≤2.4pt、水平不动。
      · 同色 attention→both（M10，步 25）：黄环不重播、不掉亮度，内层细轨淡入、彗星换到内径。
      · >99 边界（步 30，100→101）：图标应完全静止（本轮修复；旧版这里会出现「99+」双影）。
      · 换道（M12/M13，步 6 / 17）：彗星弧半径连续变形、旋转不重启（不是淡出一个再淡入一个）。
      · 断连/恢复（M16/M17，步 11 / 12）：无方向性扫动，整体同拍淡化。
      · 任何一步结束后图标应停在完整静态帧，不应残留半透明/残影。
TIPS

DSH_STATUS_ANIM_SCALE="$SCALE" "$BIN" "${ARGS[@]}" 2>&1 | while IFS= read -r line; do
  printf '  %s\n' "${line#\[icon-transition\] }"
done

echo "==> 回放结束，已恢复已安装的 App。"

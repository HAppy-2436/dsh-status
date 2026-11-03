#!/usr/bin/env bash
# dsh-status 桥协议合约测试（docs/protocol.md §3.1）。
# 默认自起 mock 桥做测试；也可测真实插件：
#   bash scripts/test-bridge.sh                          # 起 mock + 测试
#   bash scripts/test-bridge.sh --file ~/.dsh-status/bridge.json --no-start   # 测已运行的桥
set -uo pipefail

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
FILE="$HOME/.dsh-status/bridge.test.json"
START=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="$2"; shift 2 ;;
    --no-start) START=0; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

MOCK_PID=""
cleanup() { [[ -n "$MOCK_PID" ]] && kill "$MOCK_PID" 2>/dev/null; rm -f "$FILE"; }
trap cleanup EXIT INT TERM

if [[ "$START" == 1 ]]; then
  mkdir -p "$(dirname "$FILE")"
  "$NODE" "$ROOT/mock/bridge.mjs" --port 0 --file "$(basename "$FILE")" --dir "$(dirname "$FILE")" --quiet &
  MOCK_PID=$!
  for _ in $(seq 1 40); do [[ -f "$FILE" ]] && break; sleep 0.1; done
fi

[[ -f "$FILE" ]] || { echo "FAIL: bridge file not found: $FILE" >&2; exit 1; }
read -r PORT TOKEN < <(python3 - "$FILE" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
print(d["port"], d["token"])
PY
)
BASE="http://127.0.0.1:$PORT"
AUTH="Authorization: Bearer $TOKEN"
fail=0
ok() { printf 'PASS  %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

code() { curl -s -o /dev/null -w '%{http_code}' -m 5 "$@"; }
body() { curl -s -m 5 "$@"; }

check "GET /health 200 且 ok=true" \
  "[[ \"\$(body '$BASE/dsh-status/health')\" == *'\"ok\":true'* ]]"
check "GET /state 无 token → 401" \
  "[[ \"\$(code '$BASE/dsh-status/state')\" == 401 ]]"
check "GET /state 带 token → 200 且含 counts/sessions" \
  "[[ \"\$(body -H '$AUTH' '$BASE/dsh-status/state')\" == *'\"counts\"'* && \"\$(body -H '$AUTH' '$BASE/dsh-status/state')\" == *'\"sessions\"'* ]]"
check "POST /command 合法命令 → ok=true" \
  "[[ \"\$(body -X POST -H '$AUTH' -H 'content-type: application/json' -d '{\"type\":\"openSession\",\"sessionId\":\"session-x\"}' '$BASE/dsh-status/command')\" == *'\"ok\":true'* ]]"
check "POST /command 非法命令 → 400" \
  "[[ \"\$(code -X POST -H '$AUTH' -H 'content-type: application/json' -d '{\"type\":\"nope\"}' '$BASE/dsh-status/command')\" == 400 ]]"
SSE_OUT=$( (curl -s -N -m 3 -H "$AUTH" "$BASE/dsh-status/stream" 2>/dev/null || true) | head -c 2000 || true )
if grep -q 'event: state' <<<"$SSE_OUT"; then ok "GET /stream 首帧含 event: state（3s 内）"; else bad "GET /stream 首帧含 event: state（3s 内）"; fi

echo
if [[ "$fail" == 1 ]]; then echo "合约测试失败"; exit 1; fi
echo "合约测试全部通过"

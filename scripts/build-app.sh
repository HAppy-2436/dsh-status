#!/usr/bin/env bash
# 构建 Swift 菜单栏 App 并组装为 .app 包（ad-hoc 签名）。
# 用法：bash scripts/build-app.sh [--debug]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="release"
[[ "${1:-}" == "--debug" ]] && CONFIG="debug"

cd "$ROOT/app"
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/DSHStatusBar"
[[ -x "$BIN" ]] || { echo "build 产物不存在：$BIN" >&2; exit 1; }

APP="$ROOT/dist/DSHStatusBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DSHStatusBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>DSHStatusBar</string>
  <key>CFBundleIdentifier</key>
  <string>com.liyitong.dsh-status</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>DSH Status</string>
  <key>CFBundleDisplayName</key>
  <string>DSH Status</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>dsh-status</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
echo "==> 已生成：$APP"

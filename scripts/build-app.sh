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

# 提示音资源：内置「DSH 提示音」（scripts/generate-dsh-chime.py 生成），
# 运行时由 NotificationSoundPlayer 从 Contents/Resources 读取（NSSound）。
RES_SRC="$ROOT/app/Resources"
if [[ -d "$RES_SRC" ]]; then
  cp -R "$RES_SRC/." "$APP/Contents/Resources/"
  echo "==> 已打包提示音资源：$(cd "$RES_SRC" && ls | tr '\n' ' ')"
else
  echo "警告：$RES_SRC 不存在，内置提示音将降级为系统 Glass" >&2
fi

# App 图标：菜单栏同款鲸鱼 glyph（透明底，无圆角方块），避免与 DeepSeek Harness 官方图标混淆。
ICON_WORK="$ROOT/dist/icon-work"
rm -rf "$ICON_WORK"; mkdir -p "$ICON_WORK"
ICON_PNG="$ICON_WORK/icon-1024.png"
"$APP/Contents/MacOS/DSHStatusBar" --render-app-icon "$ICON_PNG" >/dev/null 2>&1 || true
if [ -f "$ICON_PNG" ]; then
  ICONSET="$ICON_WORK/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  sips -z 16 16       "$ICON_PNG" --out "$ICONSET/icon_16x16.png"      >/dev/null
  sips -z 32 32       "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
  sips -z 32 32       "$ICON_PNG" --out "$ICONSET/icon_32x32.png"      >/dev/null
  sips -z 64 64       "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
  sips -z 128 128     "$ICON_PNG" --out "$ICONSET/icon_128x128.png"    >/dev/null
  sips -z 256 256     "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256     "$ICON_PNG" --out "$ICONSET/icon_256x256.png"    >/dev/null
  sips -z 512 512     "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512     "$ICON_PNG" --out "$ICONSET/icon_512x512.png"    >/dev/null
  sips -z 1024 1024   "$ICON_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/DSHStatus.icns" 2>/dev/null || true
fi

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
  <string>com.liyitong.dshstatus.menubar</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>DSH Status</string>
  <key>CFBundleDisplayName</key>
  <string>DSH Status</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.3</string>
  <key>CFBundleVersion</key>
  <string>7</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>CFBundleIconFile</key>
  <string>DSHStatus</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 HAppy-2436 · MIT License</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true

# 自检：提示音资源是否真的进了 bundle、选项能否解析、AppSettings 默认值/持久化是否符合预期。
echo "==> 自检：提示音资源 / 音量 / 设置持久化"
"$APP/Contents/MacOS/DSHStatusBar" --self-test-sound

echo "==> 已生成：$APP"

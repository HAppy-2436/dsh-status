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

# App 图标：构建两个 .icns —— 品牌「双层环」（默认）与 DeepSeek 蓝色鲸鱼（可选项）。
# 运行时由 AppIconController 按设置把所选变体写回 DSHStatus.icns（Finder/通知图标用它）。
ICON_WORK="$ROOT/dist/icon-work"
rm -rf "$ICON_WORK"; mkdir -p "$ICON_WORK"

build_icns() {
  local src_png="$1" out_icns="$2"
  local iconset="$ICON_WORK/$(basename "$out_icns" .icns).iconset"
  rm -rf "$iconset"; mkdir -p "$iconset"
  sips -z 16 16       "$src_png" --out "$iconset/icon_16x16.png"      >/dev/null
  sips -z 32 32       "$src_png" --out "$iconset/icon_16x16@2x.png"   >/dev/null
  sips -z 32 32       "$src_png" --out "$iconset/icon_32x32.png"      >/dev/null
  sips -z 64 64       "$src_png" --out "$iconset/icon_32x32@2x.png"   >/dev/null
  sips -z 128 128     "$src_png" --out "$iconset/icon_128x128.png"    >/dev/null
  sips -z 256 256     "$src_png" --out "$iconset/icon_128x128@2x.png" >/dev/null
  sips -z 256 256     "$src_png" --out "$iconset/icon_256x256.png"    >/dev/null
  sips -z 512 512     "$src_png" --out "$iconset/icon_256x256@2x.png" >/dev/null
  sips -z 512 512     "$src_png" --out "$iconset/icon_512x512.png"    >/dev/null
  sips -z 1024 1024   "$src_png" --out "$iconset/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$iconset" -o "$out_icns" 2>/dev/null || true
}

BRAND_PNG="$ICON_WORK/app-icon-brand-1024.png"
WHALE_PNG="$ICON_WORK/app-icon-whale-1024.png"
"$APP/Contents/MacOS/DSHStatusBar" --render-app-icon "$BRAND_PNG" >/dev/null 2>&1 || true
"$APP/Contents/MacOS/DSHStatusBar" --render-app-icon-whale "$WHALE_PNG" >/dev/null 2>&1 || true
if [ -f "$BRAND_PNG" ]; then
  build_icns "$BRAND_PNG" "$APP/Contents/Resources/DSHStatusBrand.icns"
  # 默认安装态 = 品牌图标；用户切过鲸鱼后由 App 启动时同步写回。
  cp "$APP/Contents/Resources/DSHStatusBrand.icns" "$APP/Contents/Resources/DSHStatus.icns"
fi
if [ -f "$WHALE_PNG" ]; then
  build_icns "$WHALE_PNG" "$APP/Contents/Resources/DSHStatusWhale.icns"
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
  <string>0.4.4</string>
  <key>CFBundleVersion</key>
  <string>18</string>
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

# 自检：焦点会话完成通知（notices 解码 / 文案兜底 / 去重基线 / 通知过滤），纯逻辑、不依赖通知权限。
echo "==> 自检：焦点会话完成通知"
"$APP/Contents/MacOS/DSHStatusBar" --self-test-notice

echo "==> 已生成：$APP"

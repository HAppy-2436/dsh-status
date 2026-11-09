#!/usr/bin/env bash
# 构建可发布的 DSH Status DMG（本地与 GitHub Actions 通用）。
#
# 用法（在仓库根目录或其外层任意目录均可执行）：
#   bash scripts/release-dmg.sh              # 版本号取 scripts/build-app.sh 的 CFBundleShortVersionString
#   bash scripts/release-dmg.sh 0.2.0        # 显式版本号，必须与 build-app.sh 一致
#   bash scripts/release-dmg.sh v0.2.0       # 允许带 v 前缀（CI 用 tag）
#
# 产物：
#   dist/release/DSH-Status-<version>.dmg
#   dist/release/DSH-Status-<version>.dmg.sha256
#
# 可选环境变量：
#   CODESIGN_IDENTITY     Developer ID Application 证书名；缺省 → ad-hoc 签名（未公证，Gatekeeper 会拦截）
#   NOTARY_PROFILE        notarytool 钥匙串 profile（本机公证：xcrun notarytool store-credentials）
#   APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD
#                         未设置 NOTARY_PROFILE 时的 notarytool 凭据（CI 用）
#   SKIP_GATEKEEPER_CHECK=1   跳过 spctl 评估（某些 CI 环境 Gatekeeper 不可用）
#
# 签名策略：
#   · CODESIGN_IDENTITY 存在 → codesign（hardened runtime + timestamp），
#     且若提供公证凭据 → notarytool submit --wait + stapler staple；
#   · 否则 ad-hoc 签名，并打印「未公证、首次打开需右键打开」的提示（DMG 内 INSTALL.txt 同样说明）。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT/scripts/build-app.sh"
BUILT_APP="$ROOT/dist/DSHStatusBar.app"
RELEASE_DIR="$ROOT/dist/release"
VOLNAME="DSH Status"

STAGING=""
MOUNT_POINT=""

die() {
  echo "错误：$*" >&2
  exit 1
}

cleanup() {
  local status=$?
  set +e
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    # 注意：/var 在 mount 输出里是 /private/var，不能靠 `mount | grep` 判断是否挂载；
    # hdiutil detach 接受挂载点路径，未挂载时失败也无妨（忽略错误）。
    hdiutil detach "$MOUNT_POINT" -force -quiet 2>/dev/null
    rmdir "$MOUNT_POINT" 2>/dev/null
  fi
  if [[ -n "$STAGING" && -d "$STAGING" ]]; then
    rm -rf "$STAGING"
  fi
  set -e
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

usage() {
  cat <<'USAGE'
构建可发布的 DSH Status DMG（本地与 GitHub Actions 通用）。

用法（在仓库根目录或其外层任意目录均可执行）：
  bash scripts/release-dmg.sh              # 版本号取 scripts/build-app.sh 的 CFBundleShortVersionString
  bash scripts/release-dmg.sh 0.2.0        # 显式版本号，必须与 build-app.sh 一致
  bash scripts/release-dmg.sh v0.2.0       # 允许带 v 前缀（CI 用 tag）

产物：
  dist/release/DSH-Status-<version>.dmg
  dist/release/DSH-Status-<version>.dmg.sha256

可选环境变量：
  CODESIGN_IDENTITY     Developer ID Application 证书名；缺省 → ad-hoc 签名（未公证）
  NOTARY_PROFILE        notarytool 钥匙串 profile（本机公证）
  APPLE_ID / APPLE_TEAM_ID / APPLE_APP_PASSWORD    CI 公证凭据
  SKIP_GATEKEEPER_CHECK=1                          跳过 spctl 评估
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi
if [[ $# -gt 1 ]]; then
  die "参数过多。用法：bash scripts/release-dmg.sh [版本号]"
fi

# ---------------------------------------------------------------------------
# 1. 版本号：默认从 build-app.sh 的 Info.plist 模板解析，显式参数必须与之一致
# ---------------------------------------------------------------------------
APP_VERSION="$(sed -n '/<key>CFBundleShortVersionString<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$BUILD_SCRIPT")"
[[ -n "$APP_VERSION" ]] || die "无法从 $BUILD_SCRIPT 解析 CFBundleShortVersionString"

ARG_VERSION="${1:-}"
ARG_VERSION="${ARG_VERSION#v}"
if [[ -n "$ARG_VERSION" ]]; then
  [[ "$ARG_VERSION" == "$APP_VERSION" ]] || die "版本号不一致：参数 ${ARG_VERSION} ≠ build-app.sh 中的 ${APP_VERSION}（请先更新 build-app.sh 的 CFBundleShortVersionString / CFBundleVersion）"
  VERSION="$ARG_VERSION"
else
  VERSION="$APP_VERSION"
fi

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || die "版本号格式非法：$VERSION"

DMG="$RELEASE_DIR/DSH-Status-$VERSION.dmg"
SHA_FILE="$DMG.sha256"

echo "==> DSH Status $VERSION 发布构建"
echo "    仓库根目录：$ROOT"

# ---------------------------------------------------------------------------
# 2. 完整重建 .app（build-app.sh 内部会跑 swift build、图标与 --self-test-sound 自检）
# ---------------------------------------------------------------------------
echo "==> 构建 .app（scripts/build-app.sh）"
bash "$BUILD_SCRIPT"
[[ -d "$BUILT_APP" ]] || die "构建产物不存在：$BUILT_APP"

# ---------------------------------------------------------------------------
# 3. 组装 staging：DSH Status.app + /Applications 符号链接 + INSTALL.txt(+ LICENSE)
# ---------------------------------------------------------------------------
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/dsh-status-stage.XXXXXX")"
STAGED_APP="$STAGING/DSH Status.app"

echo "==> 组装 DMG 内容（${STAGING}）"
cp -R "$BUILT_APP" "$STAGED_APP"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/INSTALL.txt" <<EOF
DSH Status $VERSION — 安装说明 / Installation Guide
================================================================

DSH Status 是开源的 macOS 菜单栏 App（MIT License），用于显示 DeepSeek Harness
的会话状态。本构建未经过 Apple 公证（notarized），首次打开时系统会拦截，
按下面步骤操作即可正常使用。

DSH Status is an open-source macOS menu bar app (MIT License) that shows
DeepSeek Harness session status. This build is NOT notarized by Apple, so
macOS will block the first launch. Follow the steps below.

----------------------------------------------------------------
1. 安装 / Install
----------------------------------------------------------------
把「DSH Status」拖进 Applications 文件夹（DMG 右侧的 Applications 是
/Applications 的快捷方式）。
Drag "DSH Status" onto the Applications folder (the Applications item on
the right is a shortcut to /Applications).

----------------------------------------------------------------
2. 首次打开 / First launch
----------------------------------------------------------------
先尝试在 Applications 里双击打开 DSH Status。
Double-click DSH Status in Applications first.

· 若被拦截（"Apple 无法检查其是否包含恶意软件" 等）：在 App 图标上
  右键 →「打开」，再在弹窗里点「打开」。
  If macOS blocks it: right-click the app icon → Open, then click Open in
  the dialog.

· 或打开「系统设置 → 隐私与安全性」，在页面底部点「仍要打开」。
  Or: System Settings → Privacy & Security → scroll down and click
  "Open Anyway".

----------------------------------------------------------------
3. 仍提示「已损坏」/ Still says "is damaged"
----------------------------------------------------------------
在「终端」执行下面命令，去掉下载隔离标记后再打开：
If macOS still says the app "is damaged", remove the quarantine attribute
in Terminal, then open it again:

    xattr -dr com.apple.quarantine "/Applications/DSH Status.app"

----------------------------------------------------------------
4. 说明 / Notes
----------------------------------------------------------------
· 这是未公证的开源构建：App 使用 ad-hoc 签名，所以 Gatekeeper 会提示；
  这是预期行为，不是文件损坏。代码、构建脚本与发布流程均在 GitHub
  仓库公开，可自行核对或从源码构建。
· This is an unnotarized open-source build with an ad-hoc signature.
  Gatekeeper warnings are expected; the app is not corrupt. The source
  code, build scripts and release pipeline are public on GitHub — review
  or build from source yourself.

项目主页 / Project: https://github.com/HAppy-2436/dsh-status
许可证 / License: MIT — Copyright © 2026 HAppy-2436
(完整许可证文本见 DMG 内的 LICENSE；第三方许可见 LICENSES/ 目录。)
EOF

# 许可证随包分发（MIT 要求保留版权与许可声明）；缺文件不阻断发布，但会提示。
if [[ -f "$ROOT/LICENSE" ]]; then
  cp "$ROOT/LICENSE" "$STAGING/LICENSE"
else
  echo "警告：未找到 $ROOT/LICENSE，DMG 内将不含 LICENSE" >&2
fi
if [[ -d "$ROOT/LICENSES" ]]; then
  cp -R "$ROOT/LICENSES" "$STAGING/LICENSES"
else
  echo "警告：未找到 $ROOT/LICENSES，DMG 内将不含第三方许可证" >&2
fi
if [[ -f "$ROOT/NOTICE" ]]; then
  cp "$ROOT/NOTICE" "$STAGING/NOTICE"
fi

# DMG 内权限归一化（staging 由 mktemp 创建，默认 700；挂载后应可正常浏览/读取）
chmod 755 "$STAGING"
if [[ -f "$STAGING/INSTALL.txt" ]]; then chmod 644 "$STAGING/INSTALL.txt"; fi
if [[ -f "$STAGING/LICENSE" ]]; then chmod 644 "$STAGING/LICENSE"; fi
if [[ -f "$STAGING/NOTICE" ]]; then chmod 644 "$STAGING/NOTICE"; fi
if [[ -d "$STAGING/LICENSES" ]]; then chmod -R a+rX "$STAGING/LICENSES"; fi

# ---------------------------------------------------------------------------
# 4. 签名：Developer ID（可选公证）或 ad-hoc
# ---------------------------------------------------------------------------
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
SIGN_DESC="ad-hoc"
NOTARIZED=0
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# 清理可能影响签名的扩展属性
xattr -cr "$STAGED_APP" 2>/dev/null || true

if [[ -n "$CODESIGN_IDENTITY" ]]; then
  echo "==> Developer ID 签名：$CODESIGN_IDENTITY"
  if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$CODESIGN_IDENTITY"; then
    echo "    当前钥匙串中的代码签名身份：" >&2
    security find-identity -v -p codesigning 2>/dev/null | sed 's/^/      /' >&2 || true
    die "找不到签名身份：${CODESIGN_IDENTITY}（检查证书是否已导入钥匙串）"
  fi
  codesign --force --deep --options runtime --timestamp \
    --sign "$CODESIGN_IDENTITY" "$STAGED_APP"
  SIGN_DESC="Developer ID（${CODESIGN_IDENTITY}）"
else
  echo "==> 未设置 CODESIGN_IDENTITY → 使用 ad-hoc 签名（未公证）"
  codesign --force --deep --sign - "$STAGED_APP"
fi

codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
echo "    签名校验通过"

# 可选公证：仅当有 Developer ID 且有 notarytool 凭据时执行
if [[ -n "$CODESIGN_IDENTITY" ]]; then
  if [[ -n "$NOTARY_PROFILE" ]]; then
    NOTARY_MODE="profile"
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    NOTARY_MODE="apple-id"
  else
    NOTARY_MODE=""
  fi

  if [[ -n "$NOTARY_MODE" ]]; then
    echo "==> 公证（notarytool，模式：${NOTARY_MODE}）——可能需要数分钟"
    NOTARY_ZIP="$STAGING/DSH-Status-$VERSION-notarize.zip"
    ditto -c -k --keepParent "$STAGED_APP" "$NOTARY_ZIP"
    if [[ "$NOTARY_MODE" == "profile" ]]; then
      xcrun notarytool submit "$NOTARY_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    else
      xcrun notarytool submit "$NOTARY_ZIP" \
        --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" --wait
    fi
    rm -f "$NOTARY_ZIP"
    xcrun stapler staple "$STAGED_APP"
    xcrun stapler validate "$STAGED_APP"
    NOTARIZED=1
    SIGN_DESC="$SIGN_DESC + 已公证（stapled）"
  else
    echo "警告：设置了 CODESIGN_IDENTITY 但未提供公证凭据（NOTARY_PROFILE 或 APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD）。"
    echo "      产物未公证，用户首次打开仍会看到 Gatekeeper 拦截提示。"
  fi
fi

# ---------------------------------------------------------------------------
# 5. 生成 DMG（UDZO，卷名 DSH Status）
# ---------------------------------------------------------------------------
mkdir -p "$RELEASE_DIR"
rm -f "$DMG" "$SHA_FILE"

echo "==> 生成 DMG：$DMG"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGING" \
  -noanyowners \
  -format UDZO \
  -ov -quiet \
  "$DMG"

# ---------------------------------------------------------------------------
# 6. 校验 1/4：hdiutil verify
# ---------------------------------------------------------------------------
echo "==> 校验 1/4：hdiutil verify"
hdiutil verify "$DMG" >/dev/null

# ---------------------------------------------------------------------------
# 7. 校验 2/4：只读挂载 + 内容检查
# ---------------------------------------------------------------------------
echo "==> 校验 2/4：只读挂载并检查内容"
MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/dsh-status-mnt.XXXXXX")"
hdiutil attach "$DMG" -readonly -noautoopen -mountpoint "$MOUNT_POINT" >/dev/null

MOUNTED_APP="$MOUNT_POINT/DSH Status.app"
cleanup_mount() {
  set +e
  if [[ -n "$MOUNT_POINT" && -d "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" -force -quiet
    rmdir "$MOUNT_POINT" 2>/dev/null
    MOUNT_POINT=""
  fi
  set -e
}

check_fail() {
  echo "    内容检查失败：$*" >&2
  cleanup_mount
  die "DMG 内容不符合预期"
}

[[ -d "$MOUNTED_APP" ]] || check_fail "缺少 \"DSH Status.app\""
[[ -x "$MOUNTED_APP/Contents/MacOS/DSHStatusBar" ]] || check_fail "缺少可执行文件 Contents/MacOS/DSHStatusBar"
[[ -L "$MOUNT_POINT/Applications" ]] || check_fail "缺少 /Applications 符号链接"
[[ "$(readlink "$MOUNT_POINT/Applications")" == "/Applications" ]] || check_fail "Applications 符号链接指向错误"
[[ -f "$MOUNT_POINT/INSTALL.txt" ]] || check_fail "缺少 INSTALL.txt"
grep -q 'xattr -dr com.apple.quarantine' "$MOUNT_POINT/INSTALL.txt" || check_fail "INSTALL.txt 缺少「已损坏」的 xattr 说明"
if [[ -f "$ROOT/LICENSE" && ! -f "$MOUNT_POINT/LICENSE" ]]; then
  check_fail "缺少 LICENSE（仓库存在 LICENSE，DMG 内缺失）"
fi
if [[ -f "$ROOT/NOTICE" && ! -f "$MOUNT_POINT/NOTICE" ]]; then
  check_fail "缺少 NOTICE（仓库存在 NOTICE，DMG 内缺失）"
fi
VOLUME_NAME="$(diskutil info "$MOUNT_POINT" 2>/dev/null | awk -F': +' '/Volume Name/{print $2; exit}')"
[[ "$VOLUME_NAME" == "$VOLNAME" ]] || check_fail "DMG 卷名 '$VOLUME_NAME' ≠ '$VOLNAME'"
MOUNTED_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$MOUNTED_APP/Contents/Info.plist" 2>/dev/null || true)"
[[ "$MOUNTED_VERSION" == "$VERSION" ]] || check_fail "Info.plist 版本号 '$MOUNTED_VERSION' ≠ 发布版本 '$VERSION'"
APP_ARCHS="$(lipo -archs "$MOUNTED_APP/Contents/MacOS/DSHStatusBar" 2>/dev/null || echo unknown)"
codesign --verify --deep --strict "$MOUNTED_APP" 2>/dev/null || check_fail "挂载后的 App 签名校验失败"
echo "    内容检查通过：DSH Status.app 版本 ${MOUNTED_VERSION}（${APP_ARCHS}）/ 卷名 ${VOLUME_NAME} / Applications → /Applications / INSTALL.txt"
ls -la "$MOUNT_POINT" | sed 's/^/    /'

# ---------------------------------------------------------------------------
# 8. 校验 3/4：Gatekeeper（spctl）评估
# ---------------------------------------------------------------------------
SPCTL_RC=0
SPCTL_OUT=""
GATEKEEPER_DESC="已跳过"
if [[ "${SKIP_GATEKEEPER_CHECK:-0}" != "1" ]]; then
  echo "==> 校验 3/4：Gatekeeper（spctl）评估"
  set +e
  SPCTL_OUT="$(spctl -a -vv "$MOUNTED_APP" 2>&1)"
  SPCTL_RC=$?
  set -e
  if [[ -n "$SPCTL_OUT" ]]; then
    printf '%s\n' "$SPCTL_OUT" | sed 's/^/    /'
  fi
  if [[ "$NOTARIZED" == "1" ]]; then
    if [[ $SPCTL_RC -ne 0 ]]; then
      cleanup_mount
      die "已公证产物应被 Gatekeeper 接受，但 spctl 返回 $SPCTL_RC"
    fi
    GATEKEEPER_DESC="accepted（已公证，预期）"
  else
    if [[ $SPCTL_RC -eq 0 ]]; then
      echo "    警告：未公证产物竟然被 spctl 接受，请人工复核" >&2
      GATEKEEPER_DESC="accepted（未公证却通过，需复核）"
    else
      # 未公证的 ad-hoc / Developer ID 构建被 Gatekeeper 拒绝是预期行为，
      # 依赖 DMG 内 INSTALL.txt 的「右键打开 / 仍要打开」说明。
      echo "    → rejected 属于预期（未公证；INSTALL.txt 已给首次打开步骤）"
      GATEKEEPER_DESC="rejected（未公证，预期）"
    fi
  fi
else
  echo "==> 校验 3/4：Gatekeeper 评估已跳过（SKIP_GATEKEEPER_CHECK=1）"
fi

cleanup_mount

# ---------------------------------------------------------------------------
# 9. 校验 4/4：SHA256 校验文件
# ---------------------------------------------------------------------------
echo "==> 校验 4/4：生成 SHA256"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "DSH-Status-$VERSION.dmg" > "DSH-Status-$VERSION.dmg.sha256"
  shasum -a 256 -c "DSH-Status-$VERSION.dmg.sha256"
)
SHA256="$(awk '{print $1}' "$SHA_FILE")"
SIZE_BYTES="$(stat -f%z "$DMG")"
SIZE_HUMAN="$(du -h "$DMG" | cut -f1 | tr -d ' ')"

# ---------------------------------------------------------------------------
# 10. 汇总
# ---------------------------------------------------------------------------
echo
echo "✅ 发布产物已生成"
echo "   版本:      $VERSION"
echo "   DMG:       $DMG"
echo "   大小:      ${SIZE_HUMAN}（${SIZE_BYTES} bytes）"
echo "   SHA256:    $SHA256"
echo "   校验文件:  $SHA_FILE"
echo "   架构:      ${APP_ARCHS}"
echo "   签名:      $SIGN_DESC"
echo "   Gatekeeper: $GATEKEEPER_DESC"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  echo
  echo "提示：本次为 ad-hoc 未公证构建。用户首次打开需「右键 → 打开」或在"
  echo "      系统设置 → 隐私与安全性里「仍要打开」（见 DMG 内 INSTALL.txt）。"
fi

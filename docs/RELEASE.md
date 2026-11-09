# 发布流程（Release）

面向维护者。**用户安装说明在 DMG 里的 `INSTALL.txt`**，本文只讲怎么产出和发布 DMG。

## 1. 产物

| 产物 | 路径 / 说明 |
| --- | --- |
| DMG | `dist/release/DSH-Status-<version>.dmg`（UDZO 压缩，卷名 `DSH Status`） |
| 校验文件 | `dist/release/DSH-Status-<version>.dmg.sha256`（内容为 `shasum -a 256` 输出，含裸文件名，可与 DMG 同目录 `shasum -a 256 -c` 校验） |
| GitHub Release | tag `v<version>`，附件为上面两个文件 |

DMG 内容：`DSH Status.app`、指向 `/Applications` 的符号链接、中英双语 `INSTALL.txt`、
`LICENSE`（存在时）与 `LICENSES/`（存在时）。

## 2. 版本号唯一来源

版本号只从 **`scripts/build-app.sh`** 的 `CFBundleShortVersionString` 解析；
`CFBundleVersion`（build 号）同步 +1。发版时三处必须一致：

1. `scripts/build-app.sh`：`CFBundleShortVersionString` / `CFBundleVersion`
2. `CHANGELOG.md`：新增 `## [<version>] - <YYYY-MM-DD>` 条目
3. Git tag：`v<version>`

`release-dmg.sh` 会校验显式传入的版本号与 `build-app.sh` 一致；`release.yml` 还会校验
tag 与 `build-app.sh`、`CHANGELOG.md` 一致，不一致直接失败（防止发错版本）。

## 3. 本地打包

```bash
# 从仓库根目录（任意目录执行也可以，脚本自己定位仓库根）
bash scripts/release-dmg.sh              # 版本号取 build-app.sh，当前为 0.2.0
bash scripts/release-dmg.sh 0.2.0        # 显式版本号，必须与 build-app.sh 一致
bash scripts/release-dmg.sh v0.2.0       # 允许带 v 前缀（与 tag 一致）
```

脚本步骤（`set -euo pipefail`，CI 与本地通用）：

1. `bash scripts/build-app.sh` 完整重建 `.app`（含 `swift build -c release`、图标生成、
   `--self-test-sound` 自检）；
2. 组装 staging：`DSH Status.app`（由 `dist/DSHStatusBar.app` 复制并改名，bundle 目录名
   即 Finder 中显示名）+ `/Applications` 符号链接 + `INSTALL.txt` + 许可证；
3. 签名：有 `CODESIGN_IDENTITY` → Developer ID（hardened runtime + timestamp），
   并提供公证凭据时继续 notarytool 公证 + staple；否则 ad-hoc 签名并给出提示；
4. `hdiutil create` 生成 UDZO DMG（卷名 `DSH Status`）；
5. `hdiutil verify` → 用 `mktemp` 的临时挂载点只读挂载，校验 app/符号链接/INSTALL.txt/
   Info.plist 版本/签名，`spctl` 评估 Gatekeeper，然后 `trap` 保证卸载；
6. 生成 `.sha256` 并自校验。

注意：**每次构建的 DMG 字节不一定相同**（ad-hoc/Developer ID 签名含时间戳、打包顺序等），
以最终上传的 SHA256 为准。发布目录 `dist/release/` 已被 gitignore，不用提交。

可选环境变量：

| 变量 | 作用 |
| --- | --- |
| `CODESIGN_IDENTITY` | Developer ID Application 证书名；缺省 → ad-hoc |
| `NOTARY_PROFILE` | 本机 notarytool 钥匙串 profile（`xcrun notarytool store-credentials` 创建） |
| `APPLE_ID` / `APPLE_TEAM_ID` / `APPLE_APP_PASSWORD` | CI 公证凭据（app-specific password） |
| `SKIP_GATEKEEPER_CHECK=1` | 跳过 `spctl` 评估（个别 CI 环境 Gatekeeper 不可用时） |

## 4. CI

runner 统一用 **`runs-on: macos-26`**（GitHub Actions 的 macOS 26 镜像为 Apple Silicon /
arm64；依据 `actions/runner-images` 仓库的 `images/macos/macos-26-arm64-Readme.md`）。
本机 macOS 27.2 + Xcode 27.2 已验证可构建。

### `.github/workflows/ci.yml`

`push` / `pull_request` 到 `main`（也可手动 `workflow_dispatch`）：

1. `bash -n` 检查 `scripts/*.sh` 语法；
2. `app/` 下 `swift build -c release`；
3. `bash scripts/build-app.sh`（含 `--self-test-sound`）；
4. 校验 `.app` 的版本号与代码签名；
5. `bash scripts/release-dmg.sh` 做一次 DMG 冒烟（验证发布脚本本身可用）；
6. 上传 DMG + `.sha256` 为 7 天期 artifact（仅冒烟用，不是发布产物）。

### `.github/workflows/release.yml`

`push` tag `v*` 触发：

1. 校验 tag 版本 = `build-app.sh` 版本，且 `CHANGELOG.md` 有对应条目；
2. `bash scripts/release-dmg.sh "$GITHUB_REF_NAME"` 构建签名 DMG；
3. `gh release create "$GITHUB_REF_NAME" ...dmg ...dmg.sha256`
   （`--title "DSH Status v<version>"`、`--notes-file`（安装说明 + CHANGELOG 本版本条目）
   + `--generate-notes`、`--latest`）。

## 5. 发版步骤（维护者）

```bash
# 1) 改版本号 + 写 CHANGELOG
#    scripts/build-app.sh: CFBundleShortVersionString 0.2.0 → 0.2.1，CFBundleVersion 4 → 5
#    CHANGELOG.md: 新增 ## [0.2.1] - YYYY-MM-DD

# 2) 本地完整验证
bash scripts/release-dmg.sh
hdiutil verify dist/release/DSH-Status-0.2.1.dmg
(cd dist/release && shasum -a 256 -c DSH-Status-0.2.1.dmg.sha256)
spctl -a -vv "dist/release/DSH-Status-0.2.1.dmg" 2>/dev/null || true   # 未公证时预期 rejected

# 3) 提交并推送 main
git add -A && git commit -m "release: 0.2.1" && git push origin main

# 4) 打 tag 并推送（触发 Release workflow）
git tag -a v0.2.1 -m "DSH Status 0.2.1"
git push origin v0.2.1

# 5) 在 Actions 里确认 Release job 成功，检查 Release 页面附件与 SHA256
gh release view v0.2.1
```

## 6. Gatekeeper 与未公证（0.2.0 的现状）

本机钥匙串当前 **0 个代码签名身份**（`security find-identity -v -p codesigning`），
所以 0.2.0 只能 ad-hoc 签名（`codesign --force --deep --sign -`）。
这样的 DMG 在用户机器上：

- `spctl -a -vv` → **rejected**（预期；说明未公证/非 Developer ID）；
- 首次双击会被 Gatekeeper 拦下，用户需「右键 → 打开」或「系统设置 → 隐私与安全性 →
  仍要打开」；
- 若仍提示「已损坏」：`xattr -dr com.apple.quarantine "/Applications/DSH Status.app"`。

以上步骤写在 DMG 内 `INSTALL.txt`，Release 正文也会提示。ad-hoc 签名不影响 App 功能，
代价只是首次打开多一步手动放行。

## 7. 未来启用 Developer ID 公证（可选）

准备好 Apple Developer Program 的 Developer ID Application 证书后：

### 7.1 GitHub Actions secrets

| Secret | 内容 |
| --- | --- |
| `CODESIGN_IDENTITY` | 证书名，如 `Developer ID Application: Your Name (TEAMID)` |
| `APPLE_ID` | Apple 开发者账号邮箱 |
| `APPLE_TEAM_ID` | Team ID（10 位） |
| `APPLE_APP_PASSWORD` | Apple ID app-specific password（appleid.apple.com 生成） |

CI 里还需要把证书导入临时 keychain（`release.yml` 目前**没有**这步，启用公证时补一个
「Import signing certificate」step，例如）：

```yaml
- name: Import signing certificate
  env:
    CERT_P12_BASE64: ${{ secrets.DEVELOPER_ID_P12_BASE64 }}
    CERT_P12_PASSWORD: ${{ secrets.DEVELOPER_ID_P12_PASSWORD }}
  run: |
    set -euo pipefail
    echo "$CERT_P12_BASE64" | base64 --decode > "$RUNNER_TEMP/cert.p12"
    security create-keychain -p actions "$RUNNER_TEMP/build.keychain"
    security set-keychain-settings -lut 21600 "$RUNNER_TEMP/build.keychain"
    security unlock-keychain -p actions "$RUNNER_TEMP/build.keychain"
    security import "$RUNNER_TEMP/cert.p12" -k "$RUNNER_TEMP/build.keychain" \
      -P "$CERT_P12_PASSWORD" -T /usr/bin/codesign
    security list-keychains -d user -s "$RUNNER_TEMP/build.keychain" "$(security default-keychain -s | tr -d '"')"
    security set-key-partition-list -S apple-tool:,apple: -s -k actions "$RUNNER_TEMP/build.keychain"
```

配置好 secrets 并导入证书后，`release-dmg.sh` 会自动：Developer ID 签名
（`--options runtime --timestamp`）→ `notarytool submit --wait` → `stapler staple`，
`spctl` 应为 `accepted`（脚本会把该结果作为发布 gate）。未提供公证凭据时脚本会打印警告，
产物仍是未公证的 Developer ID 签名。

### 7.2 本机公证（不依赖 CI）

```bash
xcrun notarytool store-credentials "dsh-status-notary" \
  --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-password"
NOTARY_PROFILE=dsh-status-notary \
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
  bash scripts/release-dmg.sh 0.2.0
```

### 7.3 进一步：公证 DMG 本身（可选）

当前脚本公证并 staple 的是 `.app`（用户从 DMG 拖出后即可通过 Gatekeeper）。若要做到
「DMG 本身也带公证票据」，可在 `hdiutil create` 之后追加：

```bash
codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
```

这会让 `spctl -a -vv dist/release/*.dmg` 也变为 `accepted`，但会多花一次公证时间；
0.2.0 暂未启用。

## 8. 排查

- **版本号不一致**：`release-dmg.sh` / `release.yml` 会报错——先改 `build-app.sh` 再打 tag。
- **`hdiutil: 资源忙` / 卷已挂载**：`hdiutil info` 找到后 `hdiutil detach /Volumes/DSH\ Status`。
- **`spctl` rejected**：未公证时的预期结果；只有 `spctl` 在已公证产物上 rejected 才是问题。
- **macOS 27 上的 deprecated 警告**：`hdiutil create/attach/detach` 会提示改用
  `diskutil image ...`；仍可正常工作（CI 与旧系统兼容性优先），属预期噪音。
- **DMG 内 `DSH Status.app` 无法打开、提示已损坏**：用户在「下载/解压」环节被加了隔离属性，
  按 `INSTALL.txt` 第 3 节 `xattr -dr com.apple.quarantine` 处理。
- **App 只有 arm64**：当前 `swift build` 按 runner/本机架构构建，0.2.0 产物为 Apple Silicon
  专用；如需支持 Intel Mac，需要改成 universal binary（`swift build --arch arm64 --arch x86_64`），
  属后续事项。

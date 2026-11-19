import AppKit

// --render-previews <dir>：离屏生成设计预览图，不启动菜单栏
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--render-previews") {
    let output = index + 1 < arguments.count ? arguments[index + 1] : "docs/previews"
    _ = NSApplication.shared
    do {
        try PreviewRenderer.renderAll(to: URL(fileURLWithPath: output))
        print("previews written to \(output)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data(("render-previews failed: \(error)\n").utf8))
        exit(1)
    }
}

// --render-app-icon-whale <path>：生成「DeepSeek 蓝色鲸鱼」版本 App 图标 PNG（构建 .icns 用）
if let index = arguments.firstIndex(of: "--render-app-icon-whale") {
    let path = index + 1 < arguments.count ? arguments[index + 1] : "/tmp/DSHStatus-app-icon-whale.png"
    _ = NSApplication.shared
    let image = AppIconRenderer.whaleImage(size: 1024)
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("app icon (whale) written to \(path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data(("render-app-icon-whale failed: \(error)\n").utf8))
            exit(1)
        }
    }
    exit(1)
}

// --render-app-icon <path>：生成 1024pt App 图标 PNG（构建 .icns 用）
if let index = arguments.firstIndex(of: "--render-app-icon") {
    let path = index + 1 < arguments.count ? arguments[index + 1] : "/tmp/DSHStatus-app-icon.png"
    _ = NSApplication.shared
    let image = AppIconRenderer.image(size: 1024)
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        do {
            try png.write(to: URL(fileURLWithPath: path))
            print("app icon written to \(path)")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data(("render-app-icon failed: \(error)\n").utf8))
            exit(1)
        }
    }
    exit(1)
}

// --self-test-sound：提示音功能自检（资源打包 / 选项解析 / 音量映射 / 设置持久化），无音频硬件依赖。
// 由 scripts/build-app.sh 在组装 .app 后自动执行。
if arguments.contains("--self-test-sound") {
    _ = NSApplication.shared
    exit(NotificationSoundSelfTest.run())
}

// --self-test-notice：焦点会话完成通知自检（notices 协议解码 / 文案兜底 / 去重基线 / 通知过滤）。
// 纯逻辑，不依赖系统通知权限；由 scripts/build-app.sh 在组装 .app 后自动执行。
if arguments.contains("--self-test-notice") {
    _ = NSApplication.shared
    exit(NoticeSelfTest.run())
}

// 单实例保护：正常启动时如果已经有一个同 bundle id 的菜单栏 App 在跑（例如同时装了
// `~/Applications/DSH Status.app` 和仓库里的 `dist/DSHStatusBar.app`），直接退出并激活已有实例，
// 避免菜单栏出现两个图标、通知发两遍。
// 调试入口（--test-* / --dump-* / --render-* / --self-test-* / --open-panel / --bridge-file 等）不受限制。
let debugFlagPrefixes = ["--test", "--dump", "--render", "--self-test", "--open-panel",
                         "--request-notify", "--bridge-file"]
let isDebugLaunch = arguments.dropFirst().contains { argument in
    debugFlagPrefixes.contains { argument.hasPrefix($0) }
}
if !isDebugLaunch, let bundleId = Bundle.main.bundleIdentifier {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
        .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    if let existing = others.first {
        existing.activate(options: [])
        exit(0)
    }
}

let app = NSApplication.shared
// 调试/截图：DSH_STATUS_APPEARANCE=light|dark 强制界面外观（不影响系统设置）。
if let appearance = ProcessInfo.processInfo.environment["DSH_STATUS_APPEARANCE"] {
    app.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

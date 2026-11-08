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

// --render-icon-states <dir>：审计用，输出各状态静态图标的 2×/8× 位图（PNG）
if let index = arguments.firstIndex(of: "--render-icon-states") {
    let output = index + 1 < arguments.count ? arguments[index + 1] : "/tmp/icon-state-audit"
    _ = NSApplication.shared
    do {
        try PreviewRenderer.renderIconStateAudit(to: URL(fileURLWithPath: output))
        print("icon state audit written to \(output)")
        exit(0)
    } catch {
        FileHandle.standardError.write(Data(("render-icon-states failed: \(error)\n").utf8))
        exit(1)
    }
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

let app = NSApplication.shared
// 调试/截图：DSH_STATUS_APPEARANCE=light|dark 强制界面外观（不影响系统设置）。
if let appearance = ProcessInfo.processInfo.environment["DSH_STATUS_APPEARANCE"] {
    app.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

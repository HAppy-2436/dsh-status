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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

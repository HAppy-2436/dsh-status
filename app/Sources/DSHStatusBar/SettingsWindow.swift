import AppKit
import SwiftUI

/// 设置窗口：与系统设置（System Settings）一致的标准窗口 chrome。
///
/// - 标准 `NSWindow`（titled / closable / miniaturizable / resizable），标题「DSH Status 设置」；
/// - 默认内容尺寸 540×640，最小内容尺寸 500×480，可缩放；
/// - `setFrameAutosaveName("DSHStatusSettings")` 记住大小与位置，首次打开居中；
/// - 关闭不退出 App（`isReleasedWhenClosed = false`），再次打开复用同一窗口；
/// - 打开时 activate + makeKeyAndOrderFront。
final class SettingsWindowController {
    private let settings: AppSettings
    private let model: AppModel
    private var window: NSWindow?

    private static let autosaveName = "DSHStatusSettings"

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - 窗口构建

    private func makeWindow() -> NSWindow {
        let root = SettingsView(settings: settings, model: model)
        let hosting = NSHostingController(rootView: root)

        let window = NSWindow(contentViewController: hosting)
        window.title = "DSH Status 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: Theme.Metrics.settingsWidth,
                                     height: Theme.Metrics.settingsHeight))
        window.contentMinSize = NSSize(width: Theme.Metrics.settingsMinWidth,
                                       height: Theme.Metrics.settingsMinHeight)
        window.isReleasedWhenClosed = false
        // 设置窗口必须是「不透明中性灰」：不然 SwiftUI grouped Form 的玻璃底会跟随桌面/窗口振动，
        // 聚焦时被壁纸染成偏蓝，失去与系统设置一致的观感。
        window.isOpaque = true
        window.backgroundColor = Theme.dynamicNSColor(dark: (0.122, 0.125, 0.141),
                                                      light: (0.949, 0.949, 0.965))
        window.isRestorable = false
        window.tabbingMode = .disallowed

        makeWindowTitleBarNative(window)
        restoreFrame(of: window)

        return window
    }

    /// 标准 title bar：不加自定义工具栏/按钮；内容延伸到标题栏下方由系统按版本决定。
    private func makeWindowTitleBarNative(_ window: NSWindow) {
        window.toolbar = nil
        window.titlebarAppearsTransparent = false
        window.titleVisibility = .visible
        window.isMovableByWindowBackground = false
    }

    /// 恢复上次的大小/位置；首次打开（没有存档）则居中。
    private func restoreFrame(of window: NSWindow) {
        if !window.setFrameUsingName(Self.autosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Self.autosaveName)
    }
}

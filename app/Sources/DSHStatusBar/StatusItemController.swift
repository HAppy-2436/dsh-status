import AppKit

/// 菜单栏图标 + 点击/右键菜单（docs/app-design.md §2/§3）。
final class StatusItemController: NSObject {
    let statusItem: NSStatusItem
    private unowned let model: AppModel

    var onTogglePopover: (() -> Void)?
    var onOpenDSH: (() -> Void)?
    var onQuit: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private var appearanceObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?
    /// 运行中彗星弧的图层动画。
    private let cometAnimator = CometAnimator()
    private var lastImageSignature: String = ""

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.toolTip = "DSH 状态"
            cometAnimator.attach(to: button)
        }
        refresh()

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
        if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) }
    }

    // MARK: 图标刷新

    func refresh() {
        guard let button = statusItem.button else { return }
        let iconModel = model.iconModel
        // 用 NSApp.effectiveAppearance（比按钮的 effectiveAppearance 稳定）：
        // 切换桌面/全屏时后者可能瞬时解析成另一种外观，导致图标闪一下深色版。
        let appearance = NSApp.effectiveAppearance
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let animate = shouldAnimate(iconModel)

        let imageSignature = "\(iconModel.statuses.map(\.rawValue).joined(separator: ","))|\(iconModel.connected)|\(iconModel.numberMode.rawValue)|\(dark)|\(animate)"
        if imageSignature != lastImageSignature {
            lastImageSignature = imageSignature
            let image: NSImage
            if animate {
                // 静态层不含彗星弧（彗星由图层动画绘制）
                image = MenuBarIconRenderer.staticImage(for: iconModel, appearance: appearance)
            } else {
                // 静态模式：整张图（含固定角度的彗星弧）
                image = MenuBarIconRenderer.image(for: iconModel, appearance: appearance)
            }
            button.image = image
            button.imageScaling = .scaleNone
        }

        cometAnimator.update(model: iconModel, appearance: appearance, animate: animate)
        button.toolTip = MenuBarIconRenderer.tooltip(for: iconModel)
        button.setAccessibilityLabel(MenuBarIconRenderer.tooltip(for: iconModel))
    }

    // MARK: 动画开关

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func shouldAnimate(_ iconModel: IconModel) -> Bool {
        iconModel.connected
            && iconModel.runningCount > 0
            && model.settings.runAnimation
            && !reduceMotion
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    // MARK: 点击

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showMenu()
            return
        }
        onTogglePopover?()
    }

    private func showMenu() {
        let menu = NSMenu()

        let open = NSMenuItem(title: "打开 DSH", action: #selector(menuOpenDSH), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settings = NSMenuItem(title: "设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 DSH Status", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpenDSH() { onOpenDSH?() }
    @objc private func menuQuit() { onQuit?() }
    @objc private func menuOpenSettings() { onOpenSettings?() }

}

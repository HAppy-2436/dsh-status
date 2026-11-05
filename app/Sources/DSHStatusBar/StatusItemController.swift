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
    /// Core Animation 版本的图标视图（静态层 + 彗星弧图层）。
    private var iconView: AnimatedIconView?

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.length = 26
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.toolTip = "DSH 状态"

            // 用自定义视图承载图层动画；视图不拦截点击
            let view = AnimatedIconView(frame: NSRect(x: 0, y: 0,
                                                      width: AnimatedIconView.pointSize,
                                                      height: AnimatedIconView.pointSize))
            view.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
            button.addSubview(view)
            iconView = view
        }
        layoutIconView()
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
        let iconModel = model.iconModel
        layoutIconView()
        if let button = statusItem.button, let iconView {
            iconView.update(model: iconModel, appearance: button.effectiveAppearance,
                            animate: shouldAnimate(iconModel))
            button.toolTip = MenuBarIconRenderer.tooltip(for: iconModel)
            button.setAccessibilityLabel(MenuBarIconRenderer.tooltip(for: iconModel))
        }
    }

    /// 图标视图保持 22pt 并居中在状态栏按钮内。
    private func layoutIconView() {
        guard let button = statusItem.button, let iconView else { return }
        let size = AnimatedIconView.pointSize
        iconView.frame = NSRect(x: (button.bounds.width - size) / 2,
                                y: (button.bounds.height - size) / 2,
                                width: size, height: size)
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

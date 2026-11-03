import AppKit

/// 菜单栏图标 + 点击/右键菜单（docs/app-design.md §2/§3）。
final class StatusItemController: NSObject {
    let statusItem: NSStatusItem
    private unowned let model: AppModel

    var onTogglePopover: (() -> Void)?
    var onOpenDSH: (() -> Void)?
    var onQuit: (() -> Void)?
    var onStyleChange: ((IconStyle) -> Void)?

    private var style: IconStyle
    private var appearanceObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        let raw = UserDefaults.standard.string(forKey: "iconStyle") ?? IconStyle.fish.rawValue
        self.style = IconStyle(rawValue: raw) ?? .fish
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
            button.toolTip = "DSH 状态"
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
        let model = self.model.iconModel
        let appearance = button.effectiveAppearance
        let image = MenuBarIconRenderer.image(for: model, style: style, appearance: appearance)
        button.image = image
        button.imageScaling = .scaleNone
        button.toolTip = MenuBarIconRenderer.tooltip(for: model)
        button.setAccessibilityLabel(MenuBarIconRenderer.tooltip(for: model))
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

        menu.addItem(.separator())

        let styleItem = NSMenuItem(title: "图标样式", action: nil, keyEquivalent: "")
        let styleMenu = NSMenu()
        for candidate in IconStyle.allCases {
            let item = NSMenuItem(title: candidate.label, action: #selector(menuPickStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = candidate.rawValue
            item.state = candidate == style ? .on : .off
            styleMenu.addItem(item)
        }
        styleItem.submenu = styleMenu
        menu.addItem(styleItem)

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

    @objc private func menuPickStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let newStyle = IconStyle(rawValue: raw) else { return }
        style = newStyle
        UserDefaults.standard.set(newStyle.rawValue, forKey: "iconStyle")
        onStyleChange?(newStyle)
        refresh()
    }
}

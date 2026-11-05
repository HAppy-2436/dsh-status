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
    private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0
    private var lastTick = Date()
    /// 动画一圈的时长。
    private let animationPeriod: TimeInterval = 1.8

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
        animationTimer?.invalidate()
        if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
        if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) }
    }

    // MARK: 图标刷新

    func refresh() {
        guard let button = statusItem.button else { return }
        var iconModel = model.iconModel
        iconModel.animationPhase = animationPhase
        let appearance = button.effectiveAppearance
        let image = MenuBarIconRenderer.image(for: iconModel, appearance: appearance)
        button.image = image
        button.imageScaling = .scaleNone
        button.toolTip = MenuBarIconRenderer.tooltip(for: iconModel)
        button.setAccessibilityLabel(MenuBarIconRenderer.tooltip(for: iconModel))
        updateAnimation(for: iconModel)
    }

    // MARK: 运行中动画

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updateAnimation(for iconModel: IconModel) {
        let shouldAnimate = iconModel.connected
            && iconModel.runningCount > 0
            && model.settings.runAnimation
            && !reduceMotion
        if shouldAnimate, animationTimer == nil {
            lastTick = Date()
            let timer = Timer(timeInterval: 1.0 / 18.0, repeats: true) { [weak self] _ in
                guard let self else { return }
                let now = Date()
                let delta = now.timeIntervalSince(self.lastTick)
                self.lastTick = now
                self.animationPhase = (self.animationPhase + CGFloat(delta / self.animationPeriod * 360))
                    .truncatingRemainder(dividingBy: 360)
                self.refreshIconOnly()
            }
            timer.tolerance = 1.0 / 90.0
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !shouldAnimate {
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    /// 只重画图标，避免每帧重复管理定时器。
    private func refreshIconOnly() {
        guard let button = statusItem.button else { return }
        var iconModel = model.iconModel
        iconModel.animationPhase = animationPhase
        button.image = MenuBarIconRenderer.image(for: iconModel, appearance: button.effectiveAppearance)
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

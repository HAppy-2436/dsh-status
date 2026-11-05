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
    /// 状态变化时的一次性过渡动画。
    private var transitionTimer: Timer?
    private var transitionFrames: [NSImage] = []
    private var transitionIndex = 0
    private var lastModelSignature: String?
    private let transitionFPS: Double = 18
    private let transitionFrameCount = 10

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
        transitionTimer?.invalidate()
        if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
        if let themeObserver { DistributedNotificationCenter.default().removeObserver(themeObserver) }
    }

    // MARK: 图标刷新

    func refresh() {
        guard let button = statusItem.button else { return }
        let iconModel = model.iconModel
        let appearance = button.effectiveAppearance
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let signature = "\(iconModel.statuses.map(\.rawValue).joined(separator: ","))|\(iconModel.connected)|\(iconModel.numberMode.rawValue)"

        let modelChanged = lastModelSignature != nil && lastModelSignature != signature
        lastModelSignature = signature

        button.imageScaling = .scaleNone
        button.toolTip = MenuBarIconRenderer.tooltip(for: iconModel)
        button.setAccessibilityLabel(MenuBarIconRenderer.tooltip(for: iconModel))

        if modelChanged, shouldPlayTransition {
            playTransition(model: iconModel, appearance: appearance, dark: dark)
        } else {
            cancelTransition()
            button.image = MenuBarIconRenderer.image(for: iconModel, appearance: appearance)
        }
    }

    // MARK: 状态变化动效（一次性，播完即停）

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var shouldPlayTransition: Bool {
        model.settings.runAnimation
            && !reduceMotion
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func cancelTransition() {
        transitionTimer?.invalidate()
        transitionTimer = nil
        transitionFrames = []
        transitionIndex = 0
    }

    /// 播放一次过渡：10 帧 × 1/18s ≈ 0.55s，之后回到静态图（0% CPU）。
    private func playTransition(model iconModel: IconModel, appearance: NSAppearance, dark: Bool) {
        cancelTransition()
        let total = transitionFrameCount
        var frames: [NSImage] = []
        frames.reserveCapacity(total)
        for index in 0..<total {
            let progress = CGFloat(index) / CGFloat(total - 1)
            frames.append(MenuBarIconRenderer.image(for: iconModel, appearance: appearance, transition: progress))
        }
        transitionFrames = frames
        transitionIndex = 0
        statusItem.button?.image = frames[0]

        let timer = Timer(timeInterval: 1.0 / transitionFPS, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.transitionIndex += 1
            if self.transitionIndex >= self.transitionFrames.count {
                timer.invalidate()
                self.transitionTimer = nil
                // 收尾：固定到稳定帧
                if let button = self.statusItem.button {
                    button.image = MenuBarIconRenderer.image(for: self.model.iconModel, appearance: button.effectiveAppearance)
                }
                self.transitionFrames = []
                return
            }
            self.statusItem.button?.image = self.transitionFrames[self.transitionIndex]
        }
        timer.tolerance = 1.0 / 120.0
        RunLoop.main.add(timer, forMode: .common)
        transitionTimer = timer
        _ = dark
    }

    /// 调试：手动播放一次状态变化动效。
    func playTransitionForTesting() {
        guard let button = statusItem.button else { return }
        playTransition(model: model.iconModel, appearance: button.effectiveAppearance, dark: false)
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

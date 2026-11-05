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
    private var animationTime: TimeInterval = 0
    private var lastTick = Date()
    /// 预渲染的动画帧（一次生成、逐帧切换），以及对应的缓存键。
    private var animationFrames: [NSImage] = []
    private var animationFrameIndex = 0
    private var animationFramesKey = ""
    /// 帧率与总帧数（4.8s 一轮：旋转 2 圈 @2.4s/圈 + 呼吸 1 个周期，首尾无缝）。
    private let animationFPS: Double = 12
    private let animationCycle: TimeInterval = 4.8
    private var animationFrameCount: Int { Int((animationCycle * animationFPS).rounded()) }
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
        iconModel.animationTime = animationTime
        let appearance = button.effectiveAppearance
        let animating = shouldAnimate(iconModel)
        let image: NSImage
        if animating {
            let key = staticLayerKey(iconModel, appearance: appearance)
            if animationFramesKey != key || animationFrames.isEmpty {
                buildAnimationFrames(baseModel: iconModel, appearance: appearance, key: key)
                animationFrameIndex = 0
            }
            image = animationFrames.isEmpty
                ? MenuBarIconRenderer.image(for: iconModel, appearance: appearance)
                : animationFrames[min(animationFrameIndex, animationFrames.count - 1)]
        } else {
            animationFrames = []
            animationFramesKey = ""
            animationFrameIndex = 0
            image = MenuBarIconRenderer.image(for: iconModel, appearance: appearance)
        }
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

    /// 静态层缓存键：所有不随动画变化的输入。
    private func staticLayerKey(_ iconModel: IconModel, appearance: NSAppearance) -> String {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let statuses = iconModel.statuses.map(\.rawValue).joined(separator: ",")
        return "\(statuses)|\(iconModel.connected)|\(iconModel.numberMode.rawValue)|\(dark)"
    }

    private func shouldAnimate(_ iconModel: IconModel) -> Bool {
        iconModel.connected
            && iconModel.runningCount > 0
            && model.settings.runAnimation
            && !reduceMotion
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    /// 一次性把整轮动画渲染成帧序列；之后每帧只做一次图片切换。
    private func buildAnimationFrames(baseModel: IconModel, appearance: NSAppearance, key: String) {
        let total = animationFrameCount
        guard total > 0 else { return }
        let frameDuration = animationCycle / Double(total)
        let breathingCycle: TimeInterval = animationCycle
        var frames: [NSImage] = []
        frames.reserveCapacity(total)
        var phase: CGFloat = 0
        for index in 0..<total {
            let time = Double(index) * frameDuration
            if index > 0 {
                // 转速节奏：伸长期略快、收缩期略慢
                let t = time.truncatingRemainder(dividingBy: breathingCycle) / breathingCycle
                let eased = 0.5 - 0.5 * cos(t * 2 * .pi)
                let speed = 0.82 + 0.36 * eased
                phase += CGFloat(frameDuration / 2.4 * 360 * speed)
                phase = phase.truncatingRemainder(dividingBy: 360)
            }
            var frameModel = baseModel
            frameModel.animationPhase = phase
            frameModel.animationTime = time
            frames.append(MenuBarIconRenderer.image(for: frameModel, appearance: appearance))
        }
        animationFrames = frames
        animationFramesKey = key
    }

    private func updateAnimation(for iconModel: IconModel) {
        let shouldAnimate = shouldAnimate(iconModel)
        if shouldAnimate, animationTimer == nil {
            let timer = Timer(timeInterval: 1.0 / animationFPS, repeats: true) { [weak self] _ in
                guard let self, !self.animationFrames.isEmpty else { return }
                self.animationFrameIndex = (self.animationFrameIndex + 1) % self.animationFrames.count
                self.statusItem.button?.image = self.animationFrames[self.animationFrameIndex]
            }
            timer.tolerance = 1.0 / 90.0
            RunLoop.main.add(timer, forMode: .common)
            animationTimer = timer
        } else if !shouldAnimate {
            animationTimer?.invalidate()
            animationTimer = nil
        }
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

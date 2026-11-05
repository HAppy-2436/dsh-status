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
    private var lastRingColor: NSColor?
    private var hasRenderedOnce = false
    /// 过渡进行中：暂停彗星弧，避免和外环扫入叠在一起。
    private var transitionInFlight = false

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
        let ringColor = MenuBarIconRenderer.ringColor(for: iconModel, appearance: appearance)
        let ringChanged = hasRenderedOnce && (ringColor != lastRingColor)

        if imageSignature != lastImageSignature {
            lastImageSignature = imageSignature
            if ringChanged, shouldPlayRingTransition {
                // 过渡：先隐藏外环（稍后由图层扫入），扫完再换成完整静态图
                playRingTransition(to: ringColor, model: iconModel, appearance: appearance, animate: animate)
            } else {
                applyStaticImage(model: iconModel, appearance: appearance, animate: animate)
            }
        }

        if !transitionInFlight {
            cometAnimator.update(model: iconModel, appearance: appearance, animate: animate)
        }
        button.toolTip = MenuBarIconRenderer.tooltip(for: iconModel)
        button.setAccessibilityLabel(MenuBarIconRenderer.tooltip(for: iconModel))
        lastRingColor = ringColor
        hasRenderedOnce = true
    }

    // MARK: 状态切换过渡

    private var shouldPlayRingTransition: Bool {
        model.settings.transitionAnimation
            && !reduceMotion
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private func applyStaticImage(model iconModel: IconModel, appearance: NSAppearance, animate: Bool) {
        guard let button = statusItem.button else { return }
        let image: NSImage
        if animate {
            image = MenuBarIconRenderer.staticImage(for: iconModel, appearance: appearance)
        } else {
            image = MenuBarIconRenderer.image(for: iconModel, appearance: appearance)
        }
        button.image = image
        button.imageScaling = .scaleNone
    }

    private func finishRingTransition(appearance: NSAppearance, animate: Bool) {
        guard transitionInFlight else { return }
        transitionInFlight = false
        applyStaticImage(model: model.iconModel, appearance: appearance, animate: animate)
        cometAnimator.update(model: model.iconModel, appearance: appearance, animate: animate, force: true)
    }

    /// 调试：手动播一次外环过渡（不改变真实状态）。
    func debugPlayRingTransition() {
        guard let button = statusItem.button else { return }
        let appearance = NSApp.effectiveAppearance
        let color = Theme.statusNSColor(.waiting, dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        playRingTransition(to: color, model: model.iconModel, appearance: appearance,
                           animate: shouldAnimate(model.iconModel))
    }

    /// 外环变化时的过渡：隐藏外环的静态图打底 → 图层扫一圈（颜色渐变）→ 换回完整静态图。
    private func playRingTransition(to ringColor: NSColor?, model iconModel: IconModel,
                                    appearance: NSAppearance, animate: Bool) {
        guard let button = statusItem.button else { return }
        transitionInFlight = true
        cometAnimator.cancelRingTransition()

        let base = MenuBarIconRenderer.staticImage(for: iconModel, appearance: appearance, includeRing: false)
        button.image = base
        button.imageScaling = .scaleNone
        cometAnimator.suspendComet()

        cometAnimator.playRingTransition(from: lastRingColor, to: ringColor) { [weak self] in
            self?.finishRingTransition(appearance: appearance, animate: animate)
        }
        // 兜底：CA 完成回调异常时也能恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            guard let self, self.transitionInFlight else { return }
            self.finishRingTransition(appearance: appearance, animate: animate)
        }
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

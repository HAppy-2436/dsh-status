import AppKit

/// 菜单栏图标 + 点击/右键菜单（docs/app-design.md §2/§3）。
///
/// 状态切换动效由 `IconAnimator` 执行；本类负责：
///   · 每帧算出目标 `IconModel`（来源：桥数据 / 调试脚本）；
///   · 与「当前画面上的图标」比较，用 `IconTransitionPlan` 规划一次过渡；
///   · 过渡进行中到达的新状态先挂起，结束后再补一次（合并，不排队、不互相打断）；
///   · 首帧 / 外观切换 / 动效关闭时直接落静态图。
final class StatusItemController: NSObject {
    let statusItem: NSStatusItem
    private unowned let model: AppModel

    var onTogglePopover: (() -> Void)?
    var onOpenDSH: (() -> Void)?
    var onQuit: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onRequestNotificationPermission: (() -> Void)?
    var onOpenNotificationSettings: (() -> Void)?

    private var appearanceObserver: NSObjectProtocol?
    private var themeObserver: NSObjectProtocol?
    private let animator = IconAnimator()

    /// 当前画面上（或正在过渡到的）图标模型：过渡起点由它决定。
    private var displayedModel: IconModel?
    private var displayedCometAnimated = false
    private var lastAppearanceKey = ""
    private var hasRenderedOnce = false
    /// 过渡期间到达的新状态：结束后再算一次（合并中间态，避免动画反复被打断）。
    private var hasQueuedUpdate = false

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
            animator.attach(to: button)
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
        animator.attach(to: button)

        let iconModel = debugIconOverride ?? model.iconModel
        let appearance = NSApp.effectiveAppearance
        let appearanceKey = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        let cometAnimated = shouldAnimate(iconModel)

        button.toolTip = MenuBarIconRenderer.tooltip(for: iconModel)
        button.setAccessibilityLabel(MenuBarIconRenderer.tooltip(for: iconModel))

        guard hasRenderedOnce, appearanceKey == lastAppearanceKey else {
            // 首帧 / 外观切换：直接落静态图，不播过渡（深浅色变化不是状态变化）。
            hasRenderedOnce = true
            lastAppearanceKey = appearanceKey
            displayedModel = iconModel
            displayedCometAnimated = cometAnimated
            hasQueuedUpdate = false
            animator.snapTo(model: iconModel, appearance: appearance, cometAnimated: cometAnimated)
            return
        }

        if animator.isTransitioning {
            if visualChanged(target: iconModel, cometAnimated: cometAnimated) {
                hasQueuedUpdate = true
            }
            return
        }

        advance(to: iconModel, appearance: appearance, cometAnimated: cometAnimated)
        animator.updateComet(model: iconModel, appearance: appearance, animate: cometAnimated)
    }

    /// 从「当前画面」过渡到目标模型；视觉无变化时只同步持续动画。
    private func advance(to target: IconModel, appearance: NSAppearance, cometAnimated: Bool) {
        guard let current = displayedModel else {
            displayedModel = target
            displayedCometAnimated = cometAnimated
            animator.snapTo(model: target, appearance: appearance, cometAnimated: cometAnimated)
            return
        }

        guard let plan = IconTransitionPlan.plan(
            from: current, to: target,
            oldCometAnimated: displayedCometAnimated,
            newCometAnimated: cometAnimated
        ) else { return }

        displayedModel = target
        displayedCometAnimated = cometAnimated

        guard transitionEnabled else {
            animator.snapTo(model: target, appearance: appearance, cometAnimated: cometAnimated)
            return
        }

        animator.performTransition(from: current, to: target, plan: plan, appearance: appearance) { [weak self] in
            self?.transitionDidFinish()
        }
    }

    /// 一次过渡结束：若有挂起的新状态就立刻补一次（从刚落地的新状态出发）。
    private func transitionDidFinish() {
        if hasQueuedUpdate {
            hasQueuedUpdate = false
            refresh()
            return
        }
        guard let displayedModel else { return }
        animator.updateComet(model: displayedModel, appearance: NSApp.effectiveAppearance,
                             animate: displayedCometAnimated, force: true)
    }

    private func visualChanged(target: IconModel, cometAnimated: Bool) -> Bool {
        guard let displayedModel else { return true }
        return IconVisualState(model: displayedModel) != IconVisualState(model: target)
            || displayedCometAnimated != cometAnimated
    }

    // MARK: 动画开关

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// 状态切换动效总开关：设置项 + 减弱动态效果 + 低电量模式；调试脚本下强制开启。
    private var transitionEnabled: Bool {
        if debugIconOverride != nil { return !reduceMotion }
        return model.settings.transitionAnimation && !reduceMotion && !lowPowerMode
    }

    /// 彗星弧是否处于「会动」模式（决定它是图层动画还是烘进静态图）。
    private func shouldAnimate(_ iconModel: IconModel) -> Bool {
        guard iconModel.connected, iconModel.runningCount > 0 else { return false }
        if debugIconOverride != nil { return !reduceMotion }
        return model.settings.runAnimation && !reduceMotion && !lowPowerMode
    }

    // MARK: 调试：脚本化回放全部状态迁移

    /// `--test-icon-transitions[=<起始步>,<步数>]`：依次回放全部状态迁移，便于真机逐帧核对。
    /// 每一步打印到 stderr（含相对时间与状态项屏幕坐标），配合 `DSH_STATUS_ANIM_SCALE` 放慢。
    /// 回放结束后自动退出（方便外部捕获脚本判断结束）。
    func debugRunIconTransitionScript(startIndex: Int = 0, count: Int? = nil) {
        guard let button = statusItem.button else { return }
        let scale = AppConfig.animationScale
        let start = Date()

        func log(_ message: String) {
            let now = Date()
            let line = String(format: "[icon-transition] %.3f @%.3f %@\n",
                              now.timeIntervalSince(start), now.timeIntervalSince1970, message)
            FileHandle.standardError.write(Data(line.utf8))
        }

        if let window = button.window {
            let screenRect = window.convertToScreen(button.convert(button.bounds, to: nil))
            log("button-frame \(Int(screenRect.origin.x.rounded())) \(Int(screenRect.origin.y.rounded())) "
                + "\(Int(screenRect.width.rounded())) \(Int(screenRect.height.rounded()))")
            // 供外部 screencapture 捕获的「左上角原点」矩形（含 6pt 边距，已夹在屏幕内）。
            if let screen = window.screen ?? NSScreen.main {
                let pad: CGFloat = 6
                let topLeftY = screen.frame.maxY - screenRect.maxY
                let x = max(0, screenRect.minX - pad)
                let y = max(0, topLeftY - pad)
                let width = min(screen.frame.width - x, screenRect.width + pad * 2)
                let height = min(screen.frame.height - y, screenRect.height + pad * 2)
                log("capture-rect \(Int(x.rounded())) \(Int(y.rounded())) "
                    + "\(Int(width.rounded())) \(Int(height.rounded()))")
            }
        }

        // 后台 App 的 dispatch 定时器会被系统合并（实测每步漂移 0.3–0.8s），
        // 回放期间声明 user-initiated activity，保证 step 时间线可对齐、可复现。
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "dsh-status icon transition debug replay")

        let allSteps = Self.debugTransitionSteps
        let safeStart = min(max(0, startIndex), max(0, allSteps.count - 1))
        let upper = min(allSteps.count, safeStart + (count ?? allSteps.count))
        let steps = Array(allSteps[safeStart..<upper])
        guard !steps.isEmpty else { return }

        // 起点直接落静态图（不播过渡），随后逐步回放。
        debugSnap(to: steps[0].model)
        log("step \(safeStart) \(steps[0].name)")

        var time = 0.75 * scale
        for (offset, step) in steps.enumerated().dropFirst() {
            let index = safeStart + offset
            let stepTime = time
            DispatchQueue.main.asyncAfter(deadline: .now() + stepTime) { [weak self] in
                guard let self else { return }
                self.debugIconOverride = step.model
                self.refresh()
                log("step \(index) \(step.name)")
            }
            // 一次过渡最长 0.45s；留观察窗口，放慢倍数同步放大。
            time += 1.15 * scale
        }

        // 最后一步过渡结束后自动退出。
        let exitTime = time + 0.2 * scale
        DispatchQueue.main.asyncAfter(deadline: .now() + exitTime) { [weak self] in
            guard self != nil else { return }
            log("script end")
            ProcessInfo.processInfo.endActivity(activity)
            NSApp.terminate(nil)
        }
    }

    /// 调试：直接把图标落到目标模型（不播过渡），并作为后续过渡的起点。
    private func debugSnap(to iconModel: IconModel) {
        debugIconOverride = iconModel
        let appearance = NSApp.effectiveAppearance
        let key = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        hasRenderedOnce = true
        lastAppearanceKey = key
        displayedModel = iconModel
        displayedCometAnimated = shouldAnimate(iconModel)
        hasQueuedUpdate = false
        animator.snapTo(model: iconModel, appearance: appearance,
                        cometAnimated: displayedCometAnimated)
    }

    /// 调试覆盖模型：为 nil 时走真实桥数据。
    private var debugIconOverride: IconModel?

    private struct DebugStep {
        let name: String
        let model: IconModel
    }

    private static func debugModel(_ statuses: [SessionStatus],
                                   connected: Bool = true) -> IconModel {
        IconModel(statuses: statuses, connected: connected, numberMode: .all)
    }

    /// 覆盖全部语义迁移：空闲/待办/运行中/双层/换色/数字增减/断连/恢复连接。
    private static let debugTransitionSteps: [DebugStep] = [
        DebugStep(name: "idle", model: debugModel([])),
        DebugStep(name: "idle→attention(waiting×1) 黄环扫入 + 数字 1",
                  model: debugModel([.waiting])),
        DebugStep(name: "attention(waiting)→attention(stopped) 黄→红 recolor",
                  model: debugModel([.stopped])),
        DebugStep(name: "attention→running×2 环收回 + 彗星出现 + 数字 2",
                  model: debugModel([.running, .running])),
        DebugStep(name: "running→both(+completed) 绿环扫入 + 彗星外→内 + 数字隐去",
                  model: debugModel([.running, .running, .completed])),
        DebugStep(name: "both 绿→红 recolor（运行中保持）",
                  model: debugModel([.running, .running, .stopped])),
        DebugStep(name: "both→attention(stopped) 环收回 + 彗星消失 + 数字 1",
                  model: debugModel([.stopped])),
        DebugStep(name: "attention(stopped)→attention(waiting) 红→黄 recolor",
                  model: debugModel([.waiting])),
        DebugStep(name: "attention→idle 环收回 + 鲸鱼淡入",
                  model: debugModel([])),
        DebugStep(name: "idle→disconnected 内容淡出 + 虚线环淡入",
                  model: debugModel([], connected: false)),
        DebugStep(name: "disconnected→idle 虚线环淡出 + 鲸鱼淡入",
                  model: debugModel([])),
        DebugStep(name: "idle→attention(completed×3) 绿环扫入 + 数字 3",
                  model: debugModel([.completed, .completed, .completed])),
        DebugStep(name: "attention 数字 3→2 同色滚动",
                  model: debugModel([.completed, .completed])),
        DebugStep(name: "attention→disconnected 彩色环淡成虚线环",
                  model: debugModel([], connected: false)),
        DebugStep(name: "disconnected→both(running + waiting) 黄环扫入 + 彗星内层",
                  model: debugModel([.running, .waiting])),
        DebugStep(name: "both→running 环收回 + 彗星内→外 + 数字 1",
                  model: debugModel([.running])),
        DebugStep(name: "running→disconnected 彗星淡出 + 彩色淡成虚线环",
                  model: debugModel([], connected: false)),
        DebugStep(name: "disconnected→idle 收尾",
                  model: debugModel([])),
    ]

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

        // 通知未开启时给一个入口（面板本身只显示会话，不再放提示条）。
        switch model.notificationPermission {
        case .denied, .notDetermined:
            let notify = NSMenuItem(title: "通知未开启，点此开启…",
                                    action: #selector(menuNotificationPermission),
                                    keyEquivalent: "")
            notify.target = self
            menu.addItem(notify)
        default:
            break
        }

        let dnd = NSMenuItem(title: "勿扰模式", action: #selector(menuToggleDoNotDisturb), keyEquivalent: "")
        dnd.target = self
        dnd.state = model.settings.doNotDisturb ? .on : .off
        menu.addItem(dnd)

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
    @objc private func menuToggleDoNotDisturb() { model.settings.doNotDisturb.toggle() }

    @objc private func menuNotificationPermission() {
        if model.notificationPermission == .notDetermined {
            onRequestNotificationPermission?()
        } else {
            onOpenNotificationSettings?()
        }
    }
}

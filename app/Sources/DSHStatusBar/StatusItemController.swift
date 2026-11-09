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
    /// 菜单栏实际外观（`NSStatusBarButton.effectiveAppearance`）的 KVO 观察。
    private var buttonAppearanceObservation: NSKeyValueObservation?
    private var reduceMotionObserver: NSObjectProtocol?
    private var powerObserver: NSObjectProtocol?
    private let animator = IconAnimator()

    /// 当前画面上（或正在过渡到的）图标模型：过渡起点由它决定。
    private var displayedModel: IconModel?
    private var displayedCometAnimated = false
    private var lastAppearanceKey = ""
    private var hasRenderedOnce = false
    /// 过渡期间到达的新状态：结束后再算一次（合并中间态，避免动画反复被打断）。
    private var hasQueuedUpdate = false
    /// 下一次刷新强制「落静态帧」：屏幕参数变化/状态项按钮被系统重建时使用（不做过渡）。
    private var forceSnapNext = false

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
            observeMenuBarAppearance(button)
        }
        refresh()

        appearanceObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            // 屏幕参数变化不是状态迁移：不播过渡，直接落最新静态帧（与 docs/icon-transitions.md §5.2 一致）。
            self?.forceSnapNext = true
            self?.refresh()
        }
        // 「减弱动态效果」/「低电量」开关变化时立即降级（不必等下一次状态推送）。
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let appearanceObserver { NotificationCenter.default.removeObserver(appearanceObserver) }
        buttonAppearanceObservation?.invalidate()
        if let reduceMotionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver)
        }
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
    }

    // MARK: 菜单栏外观

    /// 图标应按**菜单栏自身的实际外观**绘制，而不是 App 的 `NSApp.effectiveAppearance`。
    ///
    /// `NSStatusBarButton.effectiveAppearance` 由菜单栏解析（vibrant 外观名，例如
    /// `vibrantDark` / `vibrantLight`），在「系统浅色 + 深色壁纸」等情况下，菜单栏实际是深色的、
    /// 系统/模板图标按深色菜单栏显示为浅色，而 `NSApp.effectiveAppearance` 仍是浅色 —— 两者会不一致。
    /// Status Trio 对菜单栏图标同样读取 status-item button 的 effective appearance
    /// （其 `StatusBarController.observeAppearanceChanges()` / `appearanceProvider`），这里采用同一信号。
    private var menuBarAppearance: NSAppearance {
        statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
    }

    /// 观察菜单栏外观变化并重绘；状态项被系统重建后需要重新挂到新的 button 上。
    private func observeMenuBarAppearance(_ button: NSStatusBarButton) {
        buttonAppearanceObservation?.invalidate()
        buttonAppearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.forceSnapNext = true
                self.refresh()
            }
        }
    }

    /// 调试：`--dump-appearance` 打印 App 外观与菜单栏实际外观，供深浅色识别核对。
    func dumpAppearanceDebug() {
        func describe(_ appearance: NSAppearance) -> String {
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return "\(appearance.name.rawValue) (\(dark ? "dark" : "light"))"
        }
        print("[dsh-status] appearance app=\(describe(NSApp.effectiveAppearance)) "
              + "menubar=\(describe(menuBarAppearance)) used=\(describe(menuBarAppearance))")
    }

    // MARK: 图标刷新

    func refresh() {
        guard let button = statusItem.button else { return }
        let buttonReplaced = animator.attach(to: button)
        if buttonReplaced { observeMenuBarAppearance(button) }

        let iconModel = debugIconOverride ?? model.iconModel
        let appearance = menuBarAppearance
        let appearanceKey = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? "dark" : "light"
        let cometAnimated = shouldAnimate(iconModel)

        button.toolTip = MenuBarIconRenderer.tooltip(for: iconModel)
        button.setAccessibilityLabel(MenuBarIconRenderer.tooltip(for: iconModel))

        // 强制落静态帧的场景：首帧 / 外观切换 / 屏幕参数变化 / 状态项按钮被系统重建。
        let mustSnap = !hasRenderedOnce || appearanceKey != lastAppearanceKey
            || forceSnapNext || buttonReplaced
        forceSnapNext = false
        if mustSnap {
            hasRenderedOnce = true
            lastAppearanceKey = appearanceKey
            displayedModel = iconModel
            displayedCometAnimated = cometAnimated
            hasQueuedUpdate = false
            animator.snapTo(model: iconModel, appearance: appearance, cometAnimated: cometAnimated)
            return
        }

        if animator.isTransitioning {
            // 过渡途中把「状态切换动效」关掉：立即落静态帧，不等当前过渡播完（§5.1 瞬时）。
            if !transitionEnabled {
                displayedModel = iconModel
                displayedCometAnimated = cometAnimated
                hasQueuedUpdate = false
                animator.snapTo(model: iconModel, appearance: appearance, cometAnimated: cometAnimated)
                return
            }
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
        ) else {
            // 视觉上没有可播的变化（如 >99 时 100→101 渲染文本相同）：仍要更新「当前画面」记录，
            // 否则下一次比较会拿过期的数字当起点。
            displayedModel = target
            displayedCometAnimated = cometAnimated
            return
        }

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
        animator.updateComet(model: displayedModel, appearance: menuBarAppearance,
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

    /// 状态切换动效总开关：设置项 + 减弱动态效果 + 低电量模式；
    /// 调试脚本下强制开启（`DSH_STATUS_DISABLE_TRANSITIONS=1` 可强制关闭，用于验收降级路径）。
    private var transitionEnabled: Bool {
        if reduceMotion || lowPowerMode || debugDisableTransitions { return false }
        if debugIconOverride != nil { return true }
        return model.settings.transitionAnimation
    }

    /// 彗星弧是否处于「会动」模式（决定它是图层动画还是烘进静态图）。
    private func shouldAnimate(_ iconModel: IconModel) -> Bool {
        guard iconModel.connected, iconModel.runningCount > 0 else { return false }
        if reduceMotion || lowPowerMode || debugDisableRunAnimation { return false }
        if debugIconOverride != nil { return true }
        return model.settings.runAnimation
    }

    /// 调试/验收降级路径：`DSH_STATUS_DISABLE_TRANSITIONS=1` / `DSH_STATUS_DISABLE_RUN_ANIMATION=1`。
    private var debugDisableTransitions: Bool {
        ProcessInfo.processInfo.environment["DSH_STATUS_DISABLE_TRANSITIONS"] == "1"
    }
    private var debugDisableRunAnimation: Bool {
        ProcessInfo.processInfo.environment["DSH_STATUS_DISABLE_RUN_ANIMATION"] == "1"
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
            // 一次过渡最长 0.60s（M9）；留观察窗口，放慢倍数同步放大。
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
        let appearance = menuBarAppearance
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
                                   connected: Bool = true,
                                   numberMode: CenterNumberMode = .all) -> IconModel {
        IconModel(statuses: statuses, connected: connected, numberMode: numberMode)
    }

    /// 覆盖全部 18 类语义迁移（M1–M18，见 docs/icon-transitions.md §3）+ 数字边界：
    /// 空闲/待办/运行中/双层之间每一种迁移、换色、数字增减、字形数变化、99+ 文本相同边界、断连/恢复。
    /// 顺序即回放顺序；`--test-icon-transitions=<起始步>,<步数>` 可只跑其中一段。
    private static let debugTransitionSteps: [DebugStep] = [
        // —— 起点 ——
        DebugStep(name: "idle（起点，直接落静态帧）", model: debugModel([])),
        // —— M1/M2：空闲 ↔ 待办 ——
        DebugStep(name: "M1 idle→attention(waiting×1) 黄环扫入 + 数字 1",
                  model: debugModel([.waiting])),
        // —— M7：待办内部换色 ——
        DebugStep(name: "M7 attention(waiting)→attention(stopped) 黄→红 recolor",
                  model: debugModel([.stopped])),
        // —— M8：待办 → 运行中（同轨交接）——
        DebugStep(name: "M8 attention→running×2 环收回 + 彗星出现 + 数字 2",
                  model: debugModel([.running, .running])),
        // —— M9：运行中 → 待办（最常见：任务完成）——
        DebugStep(name: "M9 running→attention(completed) 绿环扫入 + 彗星淡出 + 数字 2→1",
                  model: debugModel([.completed])),
        DebugStep(name: "M8 attention→running×2 回程：环收回 + 彗星淡入 + 数字 1→2",
                  model: debugModel([.running, .running])),
        // —— M12/M13：运行 ↔ 双层（彗星半径迁移）——
        DebugStep(name: "M12 running→both(+completed) 绿环扫入 + 彗星外→内 + 数字隐去",
                  model: debugModel([.running, .running, .completed])),
        DebugStep(name: "M7 both 绿→红 recolor（运行中保持）",
                  model: debugModel([.running, .running, .stopped])),
        // —— M11：双层 → 待办 ——
        DebugStep(name: "M11 both→attention(stopped) 环收回 + 彗星消失 + 数字 1",
                  model: debugModel([.stopped])),
        DebugStep(name: "M7 attention(stopped)→attention(waiting) 红→黄 recolor",
                  model: debugModel([.waiting])),
        // —— M2：待办 → 空闲 ——
        DebugStep(name: "M2 attention→idle 环收回 + 鲸鱼淡入",
                  model: debugModel([])),
        // —— M16/M17：断连与恢复 ——
        DebugStep(name: "M16 idle→disconnected 内容淡出 + 虚线环淡入",
                  model: debugModel([], connected: false)),
        DebugStep(name: "M17 disconnected→idle 虚线环淡出 + 鲸鱼淡入",
                  model: debugModel([])),
        DebugStep(name: "M1 idle→attention(completed×3) 绿环扫入 + 数字 3",
                  model: debugModel([.completed, .completed, .completed])),
        // —— M14/M15：数字增多、字形数变化 ——
        DebugStep(name: "M14 attention 数字 3→2 同色滚动",
                  model: debugModel([.completed, .completed])),
        DebugStep(name: "M16 attention→disconnected 彩色环淡成虚线环",
                  model: debugModel([], connected: false)),
        DebugStep(name: "M17 disconnected→both(running + waiting) 黄环扫入 + 彗星内层",
                  model: debugModel([.running, .waiting])),
        DebugStep(name: "M13 both→running 环收回 + 彗星内→外 + 数字 1",
                  model: debugModel([.running])),
        DebugStep(name: "M16 running→disconnected 彗星淡出 + 彩色淡成虚线环",
                  model: debugModel([], connected: false)),
        DebugStep(name: "M17 disconnected→idle 收尾",
                  model: debugModel([])),
        // —— 以下补齐此前回放未覆盖的迁移（M3/M4/M5/M6/M10/M15 与 99+ 边界）——
        DebugStep(name: "M3 idle→running×1 外轨淡入 + 彗星外环淡入 + 数字 1",
                  model: debugModel([.running])),
        DebugStep(name: "M4 running→idle 内容交叉 + 彗星淡出 + 鲸鱼淡入",
                  model: debugModel([])),
        DebugStep(name: "M5 idle→both(completed + running) 绿环扫入 + 内轨 + 彗星内层",
                  model: debugModel([.completed, .running])),
        DebugStep(name: "M6 both→idle 环收回 + 彗星淡出 + 鲸鱼淡入",
                  model: debugModel([])),
        DebugStep(name: "M1 idle→attention(waiting×1)（M10 前置）",
                  model: debugModel([.waiting])),
        DebugStep(name: "M10 attention→both(waiting + running) 内轨/彗星 +0.08s 入场 + 数字淡出",
                  model: debugModel([.waiting, .running])),
        DebugStep(name: "M11 both→attention(waiting×9) 彗星淡出 + 数字 9 淡入",
                  model: debugModel(Array(repeating: SessionStatus.waiting, count: 9))),
        DebugStep(name: "M15 attention 数字 9→10 字形数变化（原地交叉淡化、不滚动）",
                  model: debugModel(Array(repeating: SessionStatus.waiting, count: 10))),
        DebugStep(name: "M2 attention→idle（数字 10 随内容淡出）",
                  model: debugModel([])),
        DebugStep(name: "M1 idle→attention(waiting×100)（数值 100 渲染为 99+）",
                  model: debugModel(Array(repeating: SessionStatus.waiting, count: 100))),
        DebugStep(name: "M14 attention 数字 99+（100→101，渲染文本相同 → 不播过渡）",
                  model: debugModel(Array(repeating: SessionStatus.waiting, count: 101))),
        DebugStep(name: "M2 attention→idle 收尾",
                  model: debugModel([])),
        // —— 补齐子变体覆盖：M18 独立迁移 / M10·M11 变色 / M14 增加 / M15 99→100 / M8 数字不变 /
        //    M17→attention·running / M16 from both（见 docs/icon-transitions.md §3、§6.3）——
        DebugStep(name: "M1 idle→attention(waiting×1)（M18 前置）",
                  model: debugModel([.waiting])),
        DebugStep(name: "M18 attention(waiting×1) 数字 1→nil（numberMode all→hidden，原地淡出）",
                  model: debugModel([.waiting], numberMode: .hidden)),
        DebugStep(name: "M18 attention(waiting×1) 数字 nil→1（numberMode hidden→all，原地淡入）",
                  model: debugModel([.waiting])),
        DebugStep(name: "M14 attention(waiting×1)→attention(waiting×2)（+1，向上滚）",
                  model: debugModel([.waiting, .waiting])),
        DebugStep(name: "M14 attention(waiting×2)→attention(waiting×1)（−1，向下滚）",
                  model: debugModel([.waiting])),
        DebugStep(name: "M15 attention 数字 1→99（1 位→2 位字形数变化）",
                  model: debugModel(Array(repeating: SessionStatus.waiting, count: 99))),
        DebugStep(name: "M15 attention 数字 99→100（99→99+，2 位→3 位）",
                  model: debugModel(Array(repeating: SessionStatus.waiting, count: 100))),
        DebugStep(name: "M14 attention 数字 100→1（3 位→1 位，原地交叉淡化）",
                  model: debugModel([.waiting])),
        DebugStep(name: "M10 attention(waiting)→both(stopped + running)（变色 + 彗星内径）",
                  model: debugModel([.stopped, .running])),
        DebugStep(name: "M7 both(stopped+running)→both(waiting+running)（黄环 recolor）",
                  model: debugModel([.waiting, .running])),
        DebugStep(name: "M11 both(waiting+running)→attention(stopped×1)（变色黄→红 + 数字淡入）",
                  model: debugModel([.stopped])),
        DebugStep(name: "M8 attention(stopped×1)→running×1（数字 1 不变，走公共原子层）",
                  model: debugModel([.running])),
        DebugStep(name: "M16 running×1→disconnected（彗星淡出）",
                  model: debugModel([], connected: false)),
        DebugStep(name: "M17 disconnected→attention(stopped×1)（数字随内容淡入）",
                  model: debugModel([.stopped])),
        DebugStep(name: "M16 attention(stopped×1)→disconnected",
                  model: debugModel([], connected: false)),
        DebugStep(name: "M17 disconnected→running×2（彗星延迟 0 变体）",
                  model: debugModel([.running, .running])),
        DebugStep(name: "M12 running×2→both(stopped+running)（红环扫入 + 彗星内移）",
                  model: debugModel([.stopped, .running])),
        DebugStep(name: "M16 both(stopped+running)→disconnected（从 both 断连）",
                  model: debugModel([], connected: false)),
        DebugStep(name: "M17 disconnected→idle 收尾",
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

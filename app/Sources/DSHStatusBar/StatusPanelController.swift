import AppKit
import Combine
import SwiftUI

/// 状态面板：无边框 `NSPanel`（不画 NSPopover 的箭头）。
///
/// 结构与 macOS 26/27 原生菜单栏模块一致，参考 Apache-2.0 开源的 **Status Trio**
/// （`AnchoredStatusPanel` / `StatusPanelContentViewController`，Copyright 2026 lingyired）：
///
/// **本文件是改编版本（Modified from lingyired/status-trio，Apache-2.0）**；
/// 具体修改点见仓库根 `THIRD_PARTY_NOTICES.md`。
/// - 无边框 `NSPanel`，`hasShadow = true`，圆角 16，`level = .statusBar`；
/// - macOS 26+ 用 `NSGlassEffectView(style: .regular)` 做背景，**不设 tint**（保留原生折射/高光），
///   SwiftUI 内容放在 `glass.contentView` 内的一层普通容器里；
/// - 旧系统退回 `NSVisualEffectView(.popover)`；「降低透明度」或用户选实色时用不透明底。
final class StatusPanelController: NSObject {
    private let panel = AnchoredStatusPanel()
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let settings: AppSettings
    private var styleCancellable: AnyCancellable?
    private var themeObserver: NSObjectProtocol?
    private var hostingController: NSHostingController<StatusPanelView>?
    private var contentController: StatusPanelContentViewController?
    /// 面板时钟：只在面板可见且有运行中会话时每秒走一格（见 `PanelClock`）。
    private let clock = PanelClock()
    private var clockTimer: Timer?
    private var localMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMonitor: Any?
    private var anchorScreenRect: NSRect = .zero
    /// 关闭动画进行中（淡出后真正 close）。
    private var isClosing = false
    /// 关闭动画的代际：显示时自增，防止旧的完成回调把新面板关掉。
    private var closeGeneration = 0
    /// 是否对「内容高度变化」做窗口高度动画（仅在面板已经上屏之后）。
    private var animateResize = false

    init(model: AppModel, statusItem: NSStatusItem, settings: AppSettings) {
        self.model = model
        self.statusItem = statusItem
        self.settings = settings
        super.init()
        let hosting = NSHostingController(rootView: StatusPanelView(model: model, clock: clock))
        let content = StatusPanelContentViewController(
            hostingController: hosting,
            backgroundStyle: settings.panelBackgroundStyle
        )
        hostingController = hosting
        contentController = content
        panel.contentViewController = content
        panel.onClose = { [weak self] in
            self?.stopClock()
            self?.removeEventMonitors()
            self?.setStatusItemHighlighted(false)
        }
        self.themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.contentController?.refreshBackground() }
        styleCancellable = settings.$panelBackgroundStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] style in self?.contentController?.applyBackgroundStyle(style) }
    }

    var isShown: Bool { panel.isVisible }

    deinit {
        stopClock()
        if let themeObserver {
            DistributedNotificationCenter.default().removeObserver(themeObserver)
        }
    }

    // MARK: 显示 / 隐藏

    func toggle() {
        if panel.isVisible && !isClosing { close() } else { show() }
    }

    func show() {
        guard let button = statusItem.button else { return }
        closeGeneration += 1
        isClosing = false
        // 显示时先把面板时钟对齐到现在，再按秒驱动运行时长（不依赖桥推送）。
        clock.tick()
        startClock()
        // 取消可能进行中的淡出，重新从透明开始淡入
        panel.alphaValue = 1
        panel.alphaValue = 0
        fitToContent()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        setStatusItemHighlighted(true)
        panel.makeKey()
        positionPanel(button: button)
        panel.invalidateShadow()
        installEventMonitors()

        // 先透明上屏，等一次布局把尺寸校正完再淡入（避免开面板瞬间跳高度）。
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            self.contentController?.view.layoutSubtreeIfNeeded()
            self.animateResize = false
            self.fitToContent()
            self.animateResize = true
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                self.panel.alphaValue = 1
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.06
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                self.panel.animator().alphaValue = 1
            }
        }
    }

    func close() {
        guard panel.isVisible, !isClosing else { return }
        isClosing = true
        stopClock()
        stopHeightAnimation()
        let generation = closeGeneration
        removeEventMonitors()
        // 高亮随关闭立即消失（与原生菜单一致），面板本体做淡出。
        setStatusItemHighlighted(false)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finishClose(generation: generation)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            self.panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.finishClose(generation: generation)
        })
    }

    private func finishClose(generation: Int) {
        guard generation == closeGeneration, isClosing else { return }
        isClosing = false
        panel.close()
    }

    /// 数据更新导致内容高度变化时，保持锚点重新适配。
    func fitIfVisible() {
        guard panel.isVisible, let button = statusItem.button else { return }
        fitToContent()
        // 逐帧高度动画期间不要移动窗口/刷新阴影：每次 setFrameOrigin 都会打断正在跑的
        // 逐帧 resize，invalidateShadow 还会让窗口在动画中途整屏重绘（看起来就是闪）。
        // 收尾统一在 `finishHeightChange()` 里做。
        guard !isAnimatingHeight else { return }
        positionPanel(button: button)
        panel.invalidateShadow()
    }

    /// 语言/主题变化时重建背景材质。
    func refreshBackground() {
        contentController?.refreshBackground()
    }

    // MARK: 状态项高亮（直接用系统自带的高亮）

    /// 系统只在「按下状态项」或「有 NSPopover 锚定在该状态项上」时绘制原生高亮。
    /// 所以这里不自己画，而是用一个 1×1、窗口透明的 NSPopover 锚定到状态项上——
    /// 系统会按原生逻辑绘制按下态高亮（尺寸/材质/圆角/深浅色全由系统决定），
    /// 同时把 popover 窗口 alpha 设为 0，视觉上完全不可见。
    private lazy var highlightPopover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        let controller = NSViewController()
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 1, height: 1)
        return popover
    }()

    private func setStatusItemHighlighted(_ highlighted: Bool) {
        guard let button = statusItem.button else { return }
        if highlighted {
            if !highlightPopover.isShown {
                highlightPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                // 只借系统高亮，popover 本体不可见。
                highlightPopover.contentViewController?.view.window?.alphaValue = 0
            }
        } else if highlightPopover.isShown {
            highlightPopover.performClose(nil)
        }
    }

    // MARK: 尺寸与位置

    private func fitToContent() {
        let previous = panel.frame
        guard let target = measuredContentSize() else { return }
        // 高度动画进行中又收到状态推送：只要目标尺寸没变，就让当前动画继续跑。
        // 之前每次推送都会重启动画（从当前帧重新计时 0.22s），运行中会话的快照一频繁，
        // 展开/收起就会变成一卡一卡、拖到 1s 以上 —— 用户看到的就是「有时抖」。
        if isAnimatingHeight,
           abs(heightTo.width - target.width) <= 0.5,
           abs(heightTo.height - target.height) <= 0.5 {
            return
        }
        guard abs(previous.width - target.width) > 0.5 || abs(previous.height - target.height) > 0.5 else { return }
        // **只有窗口在动**：顶边钉在菜单栏下沿，只让底边向下/向上长，底边位移做 0.22s 动画。
        // 内容侧不参与高度动画（`StatusPanelView` 里已移除 ScrollView 的高度动画、根视图顶部对齐），
        // 否则「窗口瞬间变高 + 内容自己在 0.24s 里长高」两套时间线打架，内容会在窗口里上下漂。
        let rect = NSRect(x: previous.minX,
                          y: previous.minY + previous.height - target.height,
                          width: target.width,
                          height: target.height)
        guard animateResize,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(rect, display: true)
            finishHeightChange()
            return
        }
        // 自己按 60fps 逐帧 setFrame，而不是 `animator().setFrame`：
        // AppKit 的窗口 frame 动画走「快照缩放」快路径，动画期间窗口内容/阴影是被拉伸的位图，
        // 玻璃与圆角在拉伸时会在左右两侧投出「抖动/闪烁」的重影。
        // 逐帧真实 resize（display: true）每次都重新渲染，代价是 13 帧 × 一次重绘，观感更干净。
        startHeightAnimation(from: previous, to: rect)
    }

    // MARK: 高度动画（自绘 60fps 逐帧 resize）

    private var heightTimer: Timer?
    private var heightStart: CFTimeInterval = 0
    private var heightFrom: NSRect = .zero
    private var heightTo: NSRect = .zero
    /// 动画期间跳过 `positionPanel` / `invalidateShadow`（会打断逐帧 resize 并可能闪一帧）。
    private var isAnimatingHeight: Bool { heightTimer != nil }

    private func startHeightAnimation(from: NSRect, to: NSRect) {
        stopHeightAnimation()
        heightFrom = from
        heightTo = to
        heightStart = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.stepHeightAnimation()
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        heightTimer = timer
        stepHeightAnimation()
    }

    private func stepHeightAnimation() {
        guard let timer = heightTimer else { return }
        let duration = max(Theme.Motion.panelResizeDuration * AppConfig.animationScale, 0.05)
        let progress = min(1, (CACurrentMediaTime() - heightStart) / duration)
        let eased = progress < 0.5
            ? 2 * progress * progress
            : 1 - pow(-2 * progress + 2, 2) / 2      // easeInOutQuad
        let rect = NSRect(
            x: heightFrom.minX,
            y: heightFrom.minY + (heightTo.minY - heightFrom.minY) * eased,
            width: heightFrom.width + (heightTo.width - heightFrom.width) * eased,
            height: heightFrom.height + (heightTo.height - heightFrom.height) * eased
        )
        panel.setFrame(rect, display: true)
        if progress >= 1 {
            timer.invalidate()
            heightTimer = nil
            panel.setFrame(heightTo, display: true)
            finishHeightChange()
        }
    }

    private func stopHeightAnimation() {
        heightTimer?.invalidate()
        heightTimer = nil
    }

    /// 高度动画结束（或瞬时尺寸变化）后统一收尾：重新对齐锚点 + 刷新阴影，只做一次。
    private func finishHeightChange() {
        guard panel.isVisible, let button = statusItem.button else { return }
        positionPanel(button: button)
        panel.invalidateShadow()
    }

    /// 量内容尺寸：宽度由 SwiftUI 根视图固定（`Theme.Metrics.panelWidth`），这里只关心高度。
    private func measuredContentSize() -> NSSize? {
        guard let content = contentController else { return nil }
        content.loadViewIfNeededCompat()
        content.view.layoutSubtreeIfNeeded()
        let height = ceil(max(content.intrinsicContentSize.height, 1))
        guard height > 0 else { return nil }
        return NSSize(width: Theme.Metrics.panelWidth, height: height)
    }

    /// 首次上屏前（还没显示过）直接把窗口设成目标尺寸，不做动画。
    private func applyContentSize() {
        guard let target = measuredContentSize() else { return }
        if abs(panel.frame.width - target.width) > 0.5 || abs(panel.frame.height - target.height) > 0.5 {
            panel.setContentSize(target)
        }
    }

    private func positionPanel(button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchorRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        anchorScreenRect = anchorRect
        let size = panel.frame.size
        // 左对齐：系统按下态高亮 = item 宽 + 4（左右各外扩 2），所以高亮左缘 = 按钮左缘 - 2。
        var x = anchorRect.minX - 2
        // 上移：面板顶边完全贴住菜单栏下沿（visibleFrame.maxY 就是菜单栏下沿）。
        var y = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame.maxY ?? anchorRect.minY
        y -= size.height

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            if y < visible.minY + 8 { y = visible.minY + 8 }
            if y + size.height > visible.maxY { y = visible.maxY - size.height }
        }
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: 面板时钟（每秒刷新运行时长）

    /// 只有面板可见、已连接且有可见的运行中会话时才走表：
    /// 要让秒数动的是「已运行 m:ss」，空闲/全部跑完时没必要每秒重绘。
    private func startClock() {
        guard clockTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self,
                  self.panel.isVisible,
                  self.model.connected,
                  self.model.orderedSessions.contains(where: { $0.statusKind == .running })
            else { return }
            self.clock.tick()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func stopClock() {
        clockTimer?.invalidate()
        clockTimer = nil
    }

    // MARK: 事件

    private func installEventMonitors() {
        removeEventMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return }
            let location = NSEvent.mouseLocation
            if self.isMenuBarPoint(location) {
                // 点自己图标：交给状态项 action 的 toggle（避免 mousedown 先关、mouseup 又开）
                if self.isStatusItemIconPoint(location) { return }
                // 点菜单栏其它图标/菜单：关闭面板
                self.close()
                return
            }
            if event.window != self.panel { self.close() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53, self.panel.isVisible {
                self.close()
                return nil
            }
            return event
        }
        // 点击 DSH 主窗口等本应用内其他窗口时也要关闭面板
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.window === self.panel { return event }
            let location = NSEvent.mouseLocation
            if event.window === self.statusItem.button?.window {
                if self.isStatusItemIconPoint(location) { return event }
            }
            if self.isMenuBarPoint(location) {
                if self.isStatusItemIconPoint(location) { return event }
                self.close()
                return event
            }
            if NSMouseInRect(location, self.anchorScreenRect.insetBy(dx: -8, dy: -8), false) {
                return event
            }
            self.close()
            return event
        }
    }

    /// 是否点在我们自己的状态项图标上（含一点容差）。
    private func isStatusItemIconPoint(_ point: NSPoint) -> Bool {
        guard let button = statusItem.button,
              let window = button.window else { return false }
        let iconRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSMouseInRect(point, iconRect.insetBy(dx: -8, dy: -8), false)
    }

    /// 状态项位于菜单栏；真实鼠标点击的 mousedown 可能没有 window，必须按菜单栏区域放过，
    /// 否则监听到 mousedown 先 close、mouseup 的 button action 又 toggle 成 show → 闪一下。
    private func isMenuBarPoint(_ point: NSPoint) -> Bool {
        for screen in NSScreen.screens where screen.frame.contains(point) {
            return point.y >= screen.visibleFrame.maxY - 0.5
        }
        return false
    }

    private func removeEventMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
    }
}

// MARK: - 面板窗口

/// 与 Status Trio 的 `AnchoredStatusPanel` 同构：无边框、非激活、可成为 key、系统窗口阴影。
///
/// 圆角阶梯（`Theme.Metrics`，全部 continuous 超椭圆曲线）：
/// - 窗口/背景本体 16pt（与原生天气模块一致）；
/// - 内容内距 8pt → 行 hover 8pt（= 16 − 8，内外曲率对齐）→ 行尾胶囊 5pt（= 8 − 3，随行内距收小）。
final class AnchoredStatusPanel: NSPanel {
    static let cornerRadius: CGFloat = Theme.Metrics.panelCornerRadius
    var onClose: (() -> Void)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        isMovable = false
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }

    override func close() {
        guard isVisible else { return }
        super.close()
        onClose?()
    }
}

// MARK: - 内容容器（材质 + SwiftUI，结构同 Status Trio）

final class StatusPanelContentViewController: NSViewController {
    private let hostingController: NSViewController
    private var backgroundStyle: PanelBackgroundStyle
    private var backgroundView: NSView?

    init(hostingController: NSViewController, backgroundStyle: PanelBackgroundStyle) {
        self.hostingController = hostingController
        self.backgroundStyle = backgroundStyle
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        view = container

        addChild(hostingController)
        contentHost.attach(hostingController.view)
        installBackground(in: container)
    }

    /// 内容宿主：**固定画布、顶部对齐、超出部分裁切**。
    /// 面板高度做窗口动画时内容本身不动，窗口只负责「向下揭幕」；
    /// 画布高度固定为最大面板高度，宿主（窗口）比它矮时只裁切、不做垂直居中，
    /// 避免展开/收起第一帧内容整体偏移（见 `TopAlignedContentHost`）。
    private let contentHost = TopAlignedContentHost()

    func loadViewIfNeededCompat() {
        _ = view
    }

    var intrinsicContentSize: NSSize {
        hostingController.view.fittingSize
    }

    func applyBackgroundStyle(_ style: PanelBackgroundStyle) {
        guard style != backgroundStyle else { return }
        backgroundStyle = style
        guard isViewLoaded else { return }
        installBackground(in: view)
    }

    func refreshBackground() {
        guard isViewLoaded else { return }
        installBackground(in: view)
    }

    private var effectiveBackgroundStyle: PanelBackgroundStyle {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? .solid
            : backgroundStyle
    }

    private func installBackground(in container: NSView) {
        backgroundView?.removeFromSuperview()
        backgroundView = nil
        contentHost.removeFromSuperview()

        let background = makeBackgroundView(in: container)
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        backgroundView = background

        // 玻璃路径把内容装进 glass.contentView；其它材质直接叠在背景之上。
        let host: NSView
        if #available(macOS 26.0, *), let glass = background as? NSGlassEffectView,
           let glassContent = glass.contentView {
            host = glassContent
        } else {
            host = container
        }
        contentHost.autoresizingMask = [.width, .height]
        contentHost.frame = host.bounds
        host.addSubview(contentHost)
    }

    private func makeBackgroundView(in container: NSView) -> NSView {
        switch effectiveBackgroundStyle {
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: container.bounds)
                glass.style = .regular
                glass.cornerRadius = AnchoredStatusPanel.cornerRadius
                // NSGlassEffectView 没有 cornerCurve API：把超椭圆曲线打在它的图层上（玻璃会读图层圆角）。
                glass.wantsLayer = true
                glass.layer?.cornerCurve = .continuous
                // 不设 tintColor：保留 Liquid Glass 的原生折射与高光（这是"液态玻璃质感"的来源）。
                let glassContent = NSView(frame: glass.bounds)
                glassContent.autoresizingMask = [.width, .height]
                glass.contentView = glassContent
                return glass
            }
            return makeClassicMaterialBackground(in: container)
        case .classicMaterial:
            return makeClassicMaterialBackground(in: container)
        case .solid:
            return makeSolidBackground(in: container)
        }
    }

    private func makeClassicMaterialBackground(in container: NSView) -> NSView {
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        return effect
    }

    private func makeSolidBackground(in container: NSView) -> NSView {
        let solid = NSView(frame: container.bounds)
        solid.wantsLayer = true
        solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        solid.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        solid.layer?.cornerCurve = .continuous
        solid.layer?.masksToBounds = true
        return solid
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let host: NSView
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView,
           let glassContent = glass.contentView {
            host = glassContent
        } else {
            host = view
        }
        if let current = contentHost.superview, current !== host {
            contentHost.removeFromSuperview()
            host.addSubview(contentHost)
        }
        contentHost.frame = host.bounds
    }
}

// MARK: - 顶部对齐的内容宿主

/// 把 SwiftUI 内容固定在一块「最大面板高度」的画布顶部：
/// - 宿主本身铺满窗口（圆角裁切由外层容器负责），窗口变高/变矮都不改变内容的布局位置；
/// - 画布高度固定（= 面板最大内容高度），内容比窗口高时从底部被裁掉，窗口长高时自然向下揭幕；
/// - 关键是画布永远不矮于 SwiftUI 根视图：否则 `NSHostingView` 会把根视图在宿主里**垂直居中**，
///   展开/收起后的第一帧内容会整体上下偏半个高度差（画面闪一下）。
final class TopAlignedContentHost: NSView {
    /// 内容画布高度 = 面板最大高度；比窗口高时由宿主/窗口裁切。
    private static let canvasHeight = Theme.Metrics.maxContentHeight

    private var content: NSView?

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(_ view: NSView) {
        content?.removeFromSuperview()
        content = view
        addSubview(view)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let content else { return }
        content.frame = NSRect(x: 0, y: 0,
                               width: bounds.width,
                               height: max(Self.canvasHeight, bounds.height))
    }
}

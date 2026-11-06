import AppKit
import Combine
import SwiftUI

/// 状态面板：无边框 `NSPanel`（不画 NSPopover 的箭头）。
///
/// 结构与 macOS 26/27 原生菜单栏模块一致，参考 Apache-2.0 开源的 **Status Trio**
/// （`AnchoredStatusPanel` / `StatusPanelContentViewController`，Copyright 2026 lingyired）：
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
    private var localMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMonitor: Any?
    private var anchorScreenRect: NSRect = .zero
    /// 关闭动画进行中（淡出后真正 close）。
    private var isClosing = false
    /// 关闭动画的代际：显示时自增，防止旧的完成回调把新面板关掉。
    private var closeGeneration = 0

    init(model: AppModel, statusItem: NSStatusItem, settings: AppSettings) {
        self.model = model
        self.statusItem = statusItem
        self.settings = settings
        super.init()
        let hosting = NSHostingController(rootView: StatusPanelView(model: model))
        let content = StatusPanelContentViewController(
            hostingController: hosting,
            backgroundStyle: settings.panelBackgroundStyle
        )
        hostingController = hosting
        contentController = content
        panel.contentViewController = content
        panel.onClose = { [weak self] in
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
            self.fitToContent()
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
        guard let content = contentController else { return }
        content.loadViewIfNeededCompat()
        content.view.layoutSubtreeIfNeeded()
        let size = content.intrinsicContentSize
        guard size.width > 0, size.height > 0 else { return }
        let target = NSSize(width: ceil(size.width), height: ceil(size.height))
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

/// 与 Status Trio 的 `AnchoredStatusPanel` 同构：无边框、非激活、可成为 key、系统窗口阴影、圆角 16。
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
        container.layer?.masksToBounds = true
        view = container

        addChild(hostingController)
        installBackground(in: container)
    }

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
        hostingController.view.removeFromSuperview()

        let background = makeBackgroundView(in: container)
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        backgroundView = background

        // 玻璃路径已把内容嵌进自己的普通容器；其它路径把内容直接放在背景之上。
        if hostingController.view.superview == nil {
            hostingController.view.frame = container.bounds
            hostingController.view.autoresizingMask = [.width, .height]
            container.addSubview(hostingController.view)
        }
    }

    private func makeBackgroundView(in container: NSView) -> NSView {
        switch effectiveBackgroundStyle {
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: container.bounds)
                glass.style = .regular
                glass.cornerRadius = AnchoredStatusPanel.cornerRadius
                // 不设 tintColor：保留 Liquid Glass 的原生折射与高光（这是"液态玻璃质感"的来源）。
                let glassContent = NSView(frame: glass.bounds)
                glassContent.autoresizingMask = [.width, .height]
                hostingController.view.frame = glassContent.bounds
                hostingController.view.autoresizingMask = [.width, .height]
                glassContent.addSubview(hostingController.view)
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
        effect.layer?.masksToBounds = true
        return effect
    }

    private func makeSolidBackground(in container: NSView) -> NSView {
        let solid = NSView(frame: container.bounds)
        solid.wantsLayer = true
        solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        solid.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        solid.layer?.masksToBounds = true
        return solid
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let container: NSView
        if #available(macOS 26.0, *), let glass = backgroundView as? NSGlassEffectView {
            container = hostingController.view.superview ?? glass
        } else {
            container = view
        }
        hostingController.view.frame = container.bounds
    }
}

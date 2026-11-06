import AppKit
import Combine
import SwiftUI

/// 状态面板：无边框 `NSPanel`（不画 NSPopover 的箭头）。
///
/// 关键结构（对齐 macOS 26/27 原生菜单栏模块，如「天气」）：
/// - 窗口比可见面板四周大 `shadowMargin`，透明边距用来放**自绘阴影**（系统窗口阴影会在玻璃边缘
///   勒出一圈深色描边，看起来"边框很粗"）；
/// - `NSGlassEffectView` 放在**可成为 key 的窗口**里（官方 Liquid Glass 的折射/高光只有在这种
///   渲染状态下才完整）——之前把它放到非 key 子窗口会导致玻璃变成"平的模糊"，没有液态玻璃质感；
/// - 圆角/内边距/描边/阴影按原生天气模块实测值调校。
final class StatusPanelController: NSObject {
    private let panel = AnchoredStatusPanel()
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let settings: AppSettings
    private var styleCancellable: AnyCancellable?
    private var themeObserver: NSObjectProtocol?
    private var hostingController: NSHostingController<StatusPanelView>?
    private var contentController: StatusPanelContentViewController?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMonitor: Any?
    private var anchorScreenRect: NSRect = .zero

    /// 窗口四周留给阴影的透明边距（可见面板外侧）。
    private static var shadowMargin: CGFloat { StatusPanelContentViewController.shadowMargin }

    init(model: AppModel, statusItem: NSStatusItem, settings: AppSettings) {
        self.model = model
        self.statusItem = statusItem
        self.settings = settings
        super.init()
        let hosting = NSHostingController(rootView: StatusPanelView(model: model))
        let content = StatusPanelContentViewController(hostingController: hosting,
                                                      backgroundStyle: settings.panelBackgroundStyle)
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
        if panel.isVisible { close() } else { show() }
    }

    func show() {
        guard let button = statusItem.button else { return }
        fitToContent()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        setStatusItemHighlighted(true)
        panel.makeKey()
        positionPanel(button: button)
        panel.invalidateShadow()
        installEventMonitors()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.panel.animator().alphaValue = 1
        }
    }

    func close() {
        guard panel.isVisible else { return }
        removeEventMonitors()
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

    // MARK: 状态项高亮（面板打开时，与原生菜单栏项一致）

    private var selectionView: NSView?

    private func setStatusItemHighlighted(_ highlighted: Bool) {
        guard let button = statusItem.button else { return }
        if highlighted {
            if selectionView?.superview !== button {
                // 原生菜单栏 extra（如天气模块）在面板打开时是「胶囊」高亮：
                // 高度≈24（几乎占满 29pt 菜单栏的可点击区）、宽度≈item 宽、圆角=高度/2。
                let frame = button.bounds.insetBy(dx: 1, dy: 0.5)
                let view = PassthroughView(frame: frame)
                view.wantsLayer = true
                view.layer?.cornerRadius = frame.height / 2
                view.layer?.cornerCurve = .continuous
                view.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
                view.autoresizingMask = [.width, .height]
                button.addSubview(view, positioned: .below, relativeTo: nil)
                selectionView = view
            }
            selectionView?.isHidden = false
        } else {
            selectionView?.isHidden = true
        }
    }

    // MARK: 尺寸与位置

    private var visiblePanelSize: NSSize {
        guard let content = contentController else { return .zero }
        content.loadViewIfNeededCompat()
        content.view.layoutSubtreeIfNeeded()
        let size = content.intrinsicContentSize
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func fitToContent() {
        let size = visiblePanelSize
        guard size.width > 0, size.height > 0 else { return }
        let m = Self.shadowMargin
        let target = NSSize(width: size.width + m * 2, height: size.height + m * 2)
        if abs(panel.frame.width - target.width) > 0.5 || abs(panel.frame.height - target.height) > 0.5 {
            panel.setContentSize(target)
        }
    }

    /// 可见面板在屏幕上的 rect（窗口 frame 去掉阴影边距）。
    private func visiblePanelRect() -> NSRect {
        panel.frame.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin)
    }

    private func positionPanel(button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let anchorRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        anchorScreenRect = anchorRect
        let size = visiblePanelSize
        let m = Self.shadowMargin
        let gap: CGFloat = 6
        var x = anchorRect.midX - size.width / 2
        var y = anchorRect.minY - gap - size.height

        if let screen = buttonWindow.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
            if y < visible.minY + 8 { y = visible.minY + 8 }
            if y + size.height > visible.maxY { y = visible.maxY - size.height }
        }
        panel.setFrameOrigin(NSPoint(x: x - m, y: y - m))
    }

    // MARK: 事件

    private func installEventMonitors() {
        removeEventMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            guard let self else { return }
            if self.isMenuBarPoint(NSEvent.mouseLocation) { return }
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
        // 点击面板外（含本 App 其它窗口、以及面板窗口的透明阴影边距）时关闭
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.window === self.panel {
                let point = event.locationInWindow
                if self.visiblePanelRect().contains(NSPoint(x: point.x + self.panel.frame.minX,
                                                            y: point.y + self.panel.frame.minY)) {
                    return event
                }
                self.close()
                return event
            }
            if event.window === self.statusItem.button?.window { return event }
            let location = NSEvent.mouseLocation
            if self.isMenuBarPoint(location) { return event }
            if NSMouseInRect(location, self.anchorScreenRect.insetBy(dx: -8, dy: -8), false) {
                return event
            }
            self.close()
            return event
        }
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

/// 不参与命中测试的装饰视图（状态项高亮背景，不能抢走按钮点击）。
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

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
        // 阴影由内容视图自绘（系统窗口阴影会在玻璃边缘产生深色描边）。
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
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

// MARK: - 内容容器（玻璃 + SwiftUI，留出阴影边距）

/// 可见面板 = 窗口内容 inset `shadowMargin`；四周透明边距用于图层自绘阴影。
final class StatusPanelContentViewController: NSViewController {
    static let shadowMargin: CGFloat = 24

    private let hostingController: NSViewController
    private var backgroundStyle: PanelBackgroundStyle
    private var backgroundView: NSView?
    private var rimView: NSView?
    private var glassContainer: NSView?

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
        let root = NSView(frame: .zero)
        root.wantsLayer = true
        view = root

        let container = NSView(frame: .zero)
        container.wantsLayer = true
        container.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        container.layer?.cornerCurve = .continuous
        // 参考原生天气面板实测的阴影衰减（2pt 处约暗 4%，15pt 内归零）
        container.layer?.shadowColor = NSColor.black.cgColor
        container.layer?.shadowOpacity = 0.50
        container.layer?.shadowRadius = 18
        container.layer?.shadowOffset = CGSize(width: 0, height: -9)
        root.addSubview(container)
        glassContainer = container

        installBackground(in: container)

        addChild(hostingController)
        hostingController.view.frame = container.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        container.addSubview(hostingController.view)

        // 原生玻璃边缘有一圈 1px 的高光描边（实测天气面板顶边亮度比内部高 ~56/255）。
        let rim = NSView(frame: container.bounds)
        rim.wantsLayer = true
        rim.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        rim.layer?.cornerCurve = .continuous
        rim.layer?.borderWidth = 0.5
        rim.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        rim.autoresizingMask = [.width, .height]
        container.addSubview(rim)
        rimView = rim
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard let container = glassContainer else { return }
        let m = Self.shadowMargin
        container.frame = view.bounds.insetBy(dx: m, dy: m)
        let radius = AnchoredStatusPanel.cornerRadius
        container.layer?.shadowPath = CGPath(roundedRect: container.bounds,
                                             cornerWidth: radius,
                                             cornerHeight: radius,
                                             transform: nil)
        backgroundView?.frame = container.bounds
        rimView?.frame = container.bounds
        hostingController.view.frame = container.bounds
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

    private func installBackground(in container: NSView) {
        backgroundView?.removeFromSuperview()
        backgroundView = nil
        let background = makeBackgroundView(in: container)
        background.autoresizingMask = [.width, .height]
        background.frame = container.bounds
        if let first = container.subviews.first {
            container.addSubview(background, positioned: .below, relativeTo: first)
        } else {
            container.addSubview(background)
        }
        backgroundView = background
        rimView?.frame = container.bounds
    }

    private func makeBackgroundView(in container: NSView) -> NSView {
        let style = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? PanelBackgroundStyle.solid
            : backgroundStyle
        switch style {
        case .solid:
            return solidBackground(in: container)
        case .classicMaterial:
            return classicMaterialBackground(in: container)
        case .liquidGlass:
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView(frame: container.bounds)
                glass.style = .regular
                glass.cornerRadius = AnchoredStatusPanel.cornerRadius
                glass.tintColor = Theme.panelGlassTint
                if #available(macOS 27.0, *) {
                    // 保留交互式玻璃（原生模块同款的高光/折射反馈）
                    glass.effectIsInteractive = true
                }
                let glassContent = NSView(frame: glass.bounds)
                glassContent.autoresizingMask = [.width, .height]
                glass.contentView = glassContent
                return glass
            }
            return classicMaterialBackground(in: container)
        }
    }

    private func classicMaterialBackground(in container: NSView) -> NSView {
        let effect = NSVisualEffectView(frame: container.bounds)
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        effect.layer?.masksToBounds = true
        return effect
    }

    private func solidBackground(in container: NSView) -> NSView {
        let solid = NSView(frame: container.bounds)
        solid.wantsLayer = true
        solid.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        solid.layer?.cornerRadius = AnchoredStatusPanel.cornerRadius
        solid.layer?.masksToBounds = true
        solid.autoresizingMask = [.width, .height]
        return solid
    }
}

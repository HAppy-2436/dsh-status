import AppKit
import Combine
import SwiftUI

/// 状态面板：参考 Status Trio 的 `AnchoredStatusPanel`——
/// 无边框 `NSPanel`（不画 NSPopover 的箭头），16pt 连续圆角，
/// macOS 26+ 使用 Liquid Glass（`NSGlassEffectView`），旧系统退回
/// `NSVisualEffectView(.popover)`，开启「降低透明度」时退回实色。
final class StatusPanelController: NSObject {
    private let panel = AnchoredStatusPanel()
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let settings: AppSettings
    private var styleCancellable: AnyCancellable?
    private var themeObserver: NSObjectProtocol?
    private var hostingController: NSHostingController<StatusPanelView>?
    private var contentController: StatusPanelContentViewController?
    /// 材质背景单独放在一个永不成为 key 的子窗口里（见 PanelGlassWindow 注释）。
    private let glassWindow = PanelGlassWindow()
    private var glassController: StatusPanelGlassViewController?
    private var outsideMonitor: Any?
    private var localMonitor: Any?
    private var localMouseMonitor: Any?
    private var globalMonitor: Any?
    private var anchorScreenRect: NSRect = .zero

    init(model: AppModel, statusItem: NSStatusItem, settings: AppSettings) {
        self.model = model
        self.statusItem = statusItem
        self.settings = settings
        super.init()
        let hosting = NSHostingController(rootView: StatusPanelView(model: model))
        let content = StatusPanelContentViewController(hostingController: hosting)
        let glass = StatusPanelGlassViewController(backgroundStyle: settings.panelBackgroundStyle)
        hostingController = hosting
        contentController = content
        glassController = glass
        panel.contentViewController = content
        glassWindow.contentViewController = glass
        panel.addChildWindow(glassWindow, ordered: .below)
        panel.onClose = { [weak self] in
            self?.removeEventMonitors()
            self?.setStatusItemHighlighted(false)
            self?.glassWindow.orderOut(nil)
        }
        self.themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main
        ) { [weak self] _ in self?.glassController?.refreshBackground() }
        styleCancellable = settings.$panelBackgroundStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] style in self?.glassController?.applyBackgroundStyle(style) }
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
        positionPanel(button: button)
        syncGlassWindow()
        panel.alphaValue = 0
        glassWindow.alphaValue = 0
        panel.orderFrontRegardless()
        panel.addChildWindow(glassWindow, ordered: .below)
        // 与原生菜单栏项一致：面板展示期间图标保持高亮（系统 highlight() 在非激活面板下不生效）
        setStatusItemHighlighted(true)
        // 非激活面板也让它成为 key window：Esc/键盘可用（玻璃材质用低透明度 tint 保持半透明）
        panel.makeKey()
        panel.invalidateShadow()
        glassWindow.invalidateShadow()
        installEventMonitors()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.alphaValue = 1
            glassWindow.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            self.panel.animator().alphaValue = 1
            self.glassWindow.animator().alphaValue = 1
        }
    }

    func close() {
        guard panel.isVisible else { return }
        removeEventMonitors()
        glassWindow.orderOut(nil)
        panel.close()
    }

    /// 数据更新导致内容高度变化时，保持锚点重新适配。
    func fitIfVisible() {
        guard panel.isVisible, let button = statusItem.button else { return }
        fitToContent()
        positionPanel(button: button)
        syncGlassWindow()
        panel.invalidateShadow()
        glassWindow.invalidateShadow()
    }

    /// 材质窗口与内容窗口保持同 frame（子窗口随父窗口移动，但尺寸变化要手动同步）。
    private func syncGlassWindow() {
        glassWindow.setFrame(panel.frame, display: false)
        glassWindow.invalidateShadow()
    }

    // MARK: 状态项高亮（面板打开时，与原生菜单栏项一致）

    private var selectionView: NSView?

    private func setStatusItemHighlighted(_ highlighted: Bool) {
        guard let button = statusItem.button else { return }
        if highlighted {
            if selectionView?.superview !== button {
                let view = PassthroughView(frame: button.bounds.insetBy(dx: 1, dy: 3))
                view.wantsLayer = true
                view.layer?.cornerRadius = 6
                view.layer?.cornerCurve = .continuous
                view.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.14).cgColor
                view.autoresizingMask = [.width, .height]
                button.addSubview(view, positioned: .below, relativeTo: nil)
                selectionView = view
            }
            selectionView?.isHidden = false
        } else {
            selectionView?.isHidden = true
        }
    }

    /// 语言/主题变化时重建背景材质。
    func refreshBackground() {
        glassController?.refreshBackground()
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
        let gap: CGFloat = 6
        var x = anchorRect.midX - size.width / 2
        var y = anchorRect.minY - gap - size.height

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
        // 点击 DSH 主窗口等本应用内其他窗口时也要关闭面板
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.window === self.panel { return event }
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

// MARK: - 面板窗口（内容层）

/// 不参与命中测试的装饰视图（状态项高亮背景，不能抢走按钮点击）。
private final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 内容窗口：只承载 SwiftUI 内容，自身透明；可以成为 key window（Esc / 键盘 / active 文本渲染）。
/// 材质背景放在下面同位置的 `PanelGlassWindow` 里——这样玻璃始终按「非 key」状态渲染（半透明液态玻璃）。
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

// MARK: - 材质窗口（玻璃层）

/// 只画材质的独立窗口，**永远不成为 key window**。
///
/// 背景：`NSGlassEffectView` 在窗口为 key 时会叠加一层提亮/实色观感（点开面板时），
/// 而失焦时（点开其它菜单栏菜单）才是用户想要的半透明液态玻璃。把材质放在永不 key 的
/// 子窗口里，就能让「常态」始终等于「失焦态」的玻璃观感；内容窗口仍然 key，Esc/键盘不受影响。
final class PanelGlassWindow: NSPanel {
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
        isMovable = false
        animationBehavior = .none
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 内容容器（透明，仅 SwiftUI）

final class StatusPanelContentViewController: NSViewController {
    private let hostingController: NSViewController

    init(hostingController: NSViewController) {
        self.hostingController = hostingController
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
        hostingController.view.frame = container.bounds
        hostingController.view.autoresizingMask = [.width, .height]
        container.addSubview(hostingController.view)
    }

    func loadViewIfNeededCompat() {
        _ = view
    }

    var intrinsicContentSize: NSSize {
        hostingController.view.fittingSize
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        hostingController.view.frame = view.bounds
    }
}

// MARK: - 材质容器（玻璃/磨砂/实色）

final class StatusPanelGlassViewController: NSViewController {
    private var backgroundStyle: PanelBackgroundStyle
    private var backgroundView: NSView?

    init(backgroundStyle: PanelBackgroundStyle) {
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
        installBackground(in: container)
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
        container.addSubview(background)
        backgroundView = background
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
                    glass.effectIsInteractive = false
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

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
                context.duration = 0.08
                context.allowsImplicitAnimation = true
                self.panel.animator().alphaValue = 1
            }
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

    // MARK: 状态项高亮（完全对齐系统「按下状态」的高亮）

    /// 状态项自己的窗口只有 item 宽度，画不出系统按下态那种 42pt 宽的胶囊；
    /// 用一个透明覆盖窗口在菜单栏上画，尺寸/颜色/位置按本机实测的按下高亮复刻：
    /// 宽度 = item 宽 + 4、高 26.5、圆角 10.75、白色 28%、顶部距菜单栏顶 2.5。
    private let highlightWindow = StatusItemHighlightWindow()

    private func setStatusItemHighlighted(_ highlighted: Bool) {
        guard let button = statusItem.button,
              let itemWindow = button.window else {
            highlightWindow.orderOut(nil)
            return
        }
        if highlighted {
            let buttonRect = itemWindow.convertToScreen(button.convert(button.bounds, to: nil))
            // 按下态高亮实测（相对按钮）：左右各外扩 2、顶部比按钮顶高 1、底部比按钮底低 3（合计高 26.5）。
            let width = buttonRect.width + 4
            let height: CGFloat = 26.5
            let capsule = NSRect(x: buttonRect.midX - width / 2,
                                 y: buttonRect.maxY + 1 - height,
                                 width: width,
                                 height: height)
            let frame = capsule
            highlightWindow.setFrame(frame, display: false)
            highlightWindow.orderFrontRegardless()
        } else {
            highlightWindow.orderOut(nil)
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

// MARK: - 面板窗口

/// 与 Status Trio 的 `AnchoredStatusPanel` 同构：无边框、非激活、可成为 key、系统窗口阴影、圆角 16。
/// 菜单栏状态项的「按下态」高亮覆盖窗口：只画一个圆角矩形，忽略鼠标事件。
final class StatusItemHighlightWindow: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 42, height: 26.5),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // 关键：高亮必须画在状态项图标「下面」（.mainMenu 层低于状态项窗口），
        // 否则半透明层会压暗/覆盖图标——这正是之前"效果完全不一样"的原因。
        level = .mainMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        ignoresMouseEvents = true

        // 系统按下态：42×26.5、圆角 13.25 continuous、白色 26%（实测按下填充 114/255#）。
        // 画在图标下面，玻璃/图标都不受影响。
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 42, height: 26.5))
        view.wantsLayer = true
        view.layer?.cornerRadius = 13.25
        view.layer?.cornerCurve = .continuous
        view.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.26).cgColor
        view.autoresizingMask = [.width, .height]
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
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

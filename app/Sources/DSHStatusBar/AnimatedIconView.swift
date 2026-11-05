import AppKit
import QuartzCore

/// 菜单栏图标的 Core Animation 版本：
/// - 静态层（外环 / 轨道 / 数字 / 鲸鱼）渲染成一张 CGImage，只在状态变化时更新；
/// - 运行中的彗星弧用 CAShapeLayer + CABasicAnimation（旋转 + 弧长呼吸），
///   由渲染服务器/GPU 逐帧插值，进程本身不再逐帧重绘。
final class AnimatedIconView: NSView {
    static let pointSize: CGFloat = MenuBarIconRenderer.canvas

    private let staticLayer = CALayer()
    private let cometLayer = CAShapeLayer()
    private var currentModel: IconModel?
    private var currentAppearance: NSAppearance?
    private var cometSpec: MenuBarIconRenderer.CometSpec?

    override var isFlipped: Bool { false }

    /// 不拦截点击：菜单栏按钮仍需接收鼠标事件。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false

        staticLayer.frame = bounds
        staticLayer.contentsScale = 2
        staticLayer.contentsGravity = .resize
        layer?.addSublayer(staticLayer)

        cometLayer.frame = bounds
        cometLayer.fillColor = nil
        cometLayer.lineCap = .round
        cometLayer.strokeStart = 0
        layer?.addSublayer(cometLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        staticLayer.frame = bounds
        cometLayer.frame = bounds
        rebuildCometPath()
        CATransaction.commit()
    }

    // MARK: 更新

    func update(model: IconModel, appearance: NSAppearance, animate: Bool) {
        currentModel = model
        currentAppearance = appearance

        let image = MenuBarIconRenderer.staticImage(for: model, appearance: appearance)
        var proposed = NSRect(origin: .zero, size: image.size)
        let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        staticLayer.frame = bounds
        staticLayer.contents = cgImage
        applyComet(model: model, appearance: appearance, animate: animate)
        CATransaction.commit()
    }

    /// 主题变化时只更新颜色，不重置动画。
    func refreshAppearance(_ appearance: NSAppearance) {
        guard let model = currentModel else { return }
        update(model: model, appearance: appearance, animate: cometLayer.animation(forKey: "spin") != nil)
    }

    // MARK: 彗星弧

    private func rebuildCometPath() {
        guard let spec = cometSpec else { cometLayer.path = nil; return }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = spec.radius * (bounds.width / Self.pointSize)
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius,
                    startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
        cometLayer.path = path
        cometLayer.lineWidth = spec.width * (bounds.width / Self.pointSize)
    }

    private func applyComet(model: IconModel, appearance: NSAppearance, animate: Bool) {
        cometSpec = MenuBarIconRenderer.cometSpec(for: model, appearance: appearance)
        rebuildCometPath()

        guard let spec = cometSpec else {
            cometLayer.removeAllAnimations()
            cometLayer.isHidden = true
            return
        }
        cometLayer.isHidden = false
        cometLayer.strokeColor = spec.color.cgColor
        cometLayer.strokeEnd = 0.35

        cometLayer.removeAllAnimations()
        guard animate else { return }

        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi     // 顺时针
        spin.duration = 2.4
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        cometLayer.add(spin, forKey: "spin")

        let breathe = CABasicAnimation(keyPath: "strokeEnd")
        breathe.fromValue = 0.24
        breathe.toValue = 0.60
        breathe.duration = 1.2
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cometLayer.add(breathe, forKey: "breathe")
    }
}

import AppKit
import QuartzCore

/// 运行中彗星弧的 Core Animation 动画层。
///
/// 设计取舍：
/// - 静态部分（外环 / 轨道 / 数字 / 鲸鱼）继续用 `NSStatusItem.button.image`，
///   这样切换桌面、菜单栏重建时系统总有正确的静态帧可画，不会出现「黑块/空块」；
/// - 只有会动的彗星弧放在按钮的图层上（`CAShapeLayer` + `CABasicAnimation`），
///   动画交给 WindowServer/GPU，进程不逐帧重绘。
final class CometAnimator {
    private let cometLayer = CAShapeLayer()
    private var attachedButton: NSStatusBarButton?
    private var currentSignature: String?
    private var currentBounds: CGRect = .zero

    private let designSize = MenuBarIconRenderer.canvas

    func attach(to button: NSStatusBarButton) {
        guard attachedButton !== button else { return }
        attachedButton = button
        button.wantsLayer = true
        cometLayer.fillColor = nil
        cometLayer.lineCap = .round
        cometLayer.strokeStart = 0
        cometLayer.isHidden = true
        button.layer?.addSublayer(cometLayer)
    }

    /// 更新彗星弧；内部按状态签名去重，避免桥每次推状态就重启动画（会看起来卡顿）。
    func update(model: IconModel, appearance: NSAppearance, animate: Bool, force: Bool = false) {
        guard let button = attachedButton else { return }
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let signature = "\(model.statuses.map(\.rawValue).joined(separator: ","))|\(model.connected)|\(model.runningCount)|\(dark)|\(animate)"
        layout(in: button.bounds)
        guard force || signature != currentSignature else { return }
        currentSignature = signature

        guard let spec = MenuBarIconRenderer.cometSpec(for: model, appearance: appearance) else {
            cometLayer.removeAllAnimations()
            cometLayer.isHidden = true
            return
        }

        cometLayer.isHidden = false
        cometLayer.strokeColor = spec.color.cgColor
        cometLayer.lineWidth = spec.width * scale
        cometLayer.strokeEnd = 0.35
        rebuildPath(radius: spec.radius * scale)
        cometLayer.removeAllAnimations()

        guard animate else { return }

        // 匀速旋转（3.0s/圈，线性）+ 轻柔呼吸（1.8s 单程自动反转，幅度较小）
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi      // 顺时针
        spin.duration = 3.0
        spin.repeatCount = .infinity
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        cometLayer.add(spin, forKey: "spin")

        let breathe = CABasicAnimation(keyPath: "strokeEnd")
        breathe.fromValue = 0.28
        breathe.toValue = 0.52
        breathe.duration = 1.8
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        cometLayer.add(breathe, forKey: "breathe")
    }

    private var scale: CGFloat {
        max(0.5, min(bounds.height / designSize, 1.6))
    }

    private var bounds: CGRect {
        attachedButton?.bounds ?? .zero
    }

    private func layout(in bounds: CGRect) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cometLayer.frame = bounds
        if currentBounds != bounds {
            currentBounds = bounds
            if let spec = currentSpec {
                cometLayer.lineWidth = spec.width * scale
                rebuildPath(radius: spec.radius * scale)
            }
        }
        CATransaction.commit()
    }

    private var currentSpec: MenuBarIconRenderer.CometSpec?

    private func rebuildPath(radius: CGFloat) {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius,
                    startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
        cometLayer.path = path
    }
}

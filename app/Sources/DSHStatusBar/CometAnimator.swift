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

        // 旋转：顺时针，平均 3.0s/圈；速度做 ±32% 的平滑起伏（有节奏但不杂乱）
        // 用数值采样生成关键帧，保证首尾正好整数圈、无缝循环。
        let cycle: Double = 6.0            // 一轮节奏 6s
        let turns: Double = 2              // 6s 转 2 圈（平均 3s/圈）
        let samples = 48
        let dt = cycle / Double(samples)
        let totalAngle = turns * 2 * Double.pi
        let baseSpeed = totalAngle / cycle
        var values: [Double] = []
        var keyTimes: [NSNumber] = []
        var angle: Double = 0
        var t: Double = 0
        for i in 0...samples {
            values.append(angle)                     // 正角度 = 顺时针
            keyTimes.append(NSNumber(value: t / cycle))
            let modulation = 1.0 + 0.32 * sin(2 * Double.pi * t / cycle)
            angle += baseSpeed * modulation * dt
            t += dt
        }
        values[samples] = totalAngle                 // 收尾对齐整数圈

        let spin = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        spin.values = values
        spin.keyTimes = keyTimes
        spin.duration = cycle
        spin.repeatCount = .infinity
        spin.calculationMode = .linear
        cometLayer.add(spin, forKey: "spin")

        let breathe = CABasicAnimation(keyPath: "strokeEnd")
        breathe.fromValue = 0.26
        breathe.toValue = 0.58
        breathe.duration = 1.7
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

import AppKit
import QuartzCore

/// 菜单栏图标的全部动效：
///   1. 持续层：运行中彗星弧（`CAShapeLayer` + CA 旋转/呼吸，GPU 驱动，进程 0 帧重绘）；
///   2. 过渡层：状态切换时按「内容 / 数字 / 外环 / 彗星」四个通道合成一次过渡
///      （计划由 `IconTransitionPlan` 给出，动效参数集中在 `IconMotion`）。
///
/// 设计约束（见 docs/icon-transitions.md）：
/// - 过渡期间 `button.image` 换成透明占位图保持状态项宽度，真实画面全部由图层合成；
///   过渡结束后立刻换回完整静态图 —— 菜单栏重建/切桌面时系统总有正确静态帧可画。
/// - 只动「属性」（透明度 / strokeEnd / path / 位移），不做布局动画，图标内容的目标位置永远不变。
/// - 所有时长统一乘以 `AppConfig.animationScale`（调试时 `DSH_STATUS_ANIM_SCALE=10` 放慢逐帧核对）。
final class IconAnimator {
    private weak var button: NSStatusBarButton?
    private let designSize = MenuBarIconRenderer.canvas

    // MARK: 持续层：彗星弧

    private let cometLayer = CAShapeLayer()
    private var cometSpec: MenuBarIconRenderer.CometSpec?
    private var cometSignature = ""
    private var cometBounds: CGRect = .zero
    private var spinActive = false

    // MARK: 过渡层

    private var transitionLayers: [CALayer] = []
    private var transitionGeneration = 0
    private(set) var isTransitioning = false

    // MARK: - 挂载 / 布局

    func attach(to button: NSStatusBarButton) {
        if self.button === button {
            layout()
            return
        }
        cometLayer.removeFromSuperlayer()
        self.button = button
        button.wantsLayer = true
        cometLayer.fillColor = nil
        cometLayer.lineCap = .round
        cometLayer.strokeStart = 0
        cometLayer.strokeEnd = 0.35
        cometLayer.opacity = 0
        cometLayer.isHidden = true
        cometLayer.zPosition = 100
        button.layer?.addSublayer(cometLayer)
        cometSignature = ""
        cometBounds = .zero
        layout()
    }

    /// 状态项尺寸变化（切桌面/屏幕参数变化）时同步图层；过渡中遇到尺寸变化直接取消（由控制器补静态图）。
    func layout() {
        guard let button else { return }
        let bounds = button.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cometLayer.frame = bounds
        if cometBounds != bounds {
            cometBounds = bounds
            if let spec = cometSpec {
                cometLayer.lineWidth = spec.width * scale
                cometLayer.path = arcPath(radius: spec.radius * scale)
            }
        }
        CATransaction.commit()
    }

    private var scale: CGFloat {
        max(0.5, min(cometBounds.height / designSize, 1.6))
    }

    // MARK: - 持续层（运行中彗星弧）

    /// 同步彗星弧到目标状态（开关/颜色/半径/外观）。`force` 用于过渡结束时落回最终状态。
    func updateComet(model: IconModel, appearance: NSAppearance, animate: Bool, force: Bool = false) {
        guard let button, button.bounds.width > 0 else { return }
        if isTransitioning && !force { return }
        layout()
        let spec = MenuBarIconRenderer.cometSpec(for: model, appearance: appearance)
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let signature = spec.map { "\($0.radius)|\($0.width)|\(dark)|\(animate)" } ?? "none"
        if !force && signature == cometSignature { return }
        cometSignature = signature

        guard let spec, animate else {
            stopComet()
            return
        }
        configureComet(spec: spec)
        cometLayer.opacity = 1
        startSpinIfNeeded()
    }

    private func configureComet(spec: MenuBarIconRenderer.CometSpec) {
        cometSpec = spec
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cometLayer.isHidden = false
        cometLayer.strokeColor = spec.color.cgColor
        cometLayer.lineWidth = spec.width * scale
        cometLayer.path = arcPath(radius: spec.radius * scale)
        CATransaction.commit()
    }

    private func stopComet() {
        cometLayer.removeAllAnimations()
        cometLayer.isHidden = true
        cometLayer.opacity = 0
        cometSpec = nil
        spinActive = false
    }

    /// 旋转 + 弧长呼吸（持续动画，只在首次出现/参数变化时重建，状态推送不会打断它）。
    private func startSpinIfNeeded() {
        guard !spinActive else { return }
        spinActive = true

        // 旋转：顺时针，平均 2.0s/圈；速度做 ±32% 的平滑起伏（有节奏但不杂乱）。
        // 用数值采样生成关键帧，保证首尾正好整数圈、无缝循环。
        let cycle: Double = 6.0            // 一轮节奏 6s
        let turns: Double = 3              // 6s 转 3 圈（平均 2s/圈）
        let samples = 48
        let dt = cycle / Double(samples)
        let totalAngle = turns * 2 * Double.pi
        let baseSpeed = totalAngle / cycle
        var values: [Double] = []
        var keyTimes: [NSNumber] = []
        var angle: Double = 0
        var t: Double = 0
        for _ in 0...samples {
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cometLayer.strokeEnd = 0.35
        CATransaction.commit()
    }

    private func arcPath(radius: CGFloat) -> CGPath {
        let bounds = cometLayer.bounds
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY), radius: radius,
                    startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
        return path
    }

    // MARK: - 静态落点

    /// 直接落到目标状态的静态图（无过渡）：首帧、外观切换、设置关闭动效时使用。
    func snapTo(model: IconModel, appearance: NSAppearance, cometAnimated: Bool) {
        cancelTransition()
        applyStaticImage(model: model, appearance: appearance, cometAnimated: cometAnimated)
        updateComet(model: model, appearance: appearance, animate: cometAnimated, force: true)
    }

    private func applyStaticImage(model: IconModel, appearance: NSAppearance, cometAnimated: Bool) {
        guard let button else { return }
        let image: NSImage
        if cometAnimated {
            image = MenuBarIconRenderer.staticImage(for: model, appearance: appearance)
        } else {
            image = MenuBarIconRenderer.image(for: model, appearance: appearance)
        }
        button.image = image
        button.imageScaling = .scaleNone
    }

    /// 取消进行中的过渡（立即移除所有过渡图层；静态图由调用方补）。
    func cancelTransition() {
        transitionGeneration += 1
        removeTransitionLayers()
        isTransitioning = false
    }

    // MARK: - 状态切换过渡

    func performTransition(from oldModel: IconModel,
                           to newModel: IconModel,
                           plan: IconTransitionPlan,
                           appearance: NSAppearance,
                           completion: @escaping () -> Void) {
        guard let button, button.bounds.width > 0, button.bounds.height > 0 else {
            completion()
            return
        }
        cancelTransition()
        transitionGeneration += 1
        let generation = transitionGeneration
        isTransitioning = true

        let bounds = button.bounds
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let contentDuration = scaled(IconMotion.contentCrossfade)
        let totalDuration = scaled(IconMotion.duration(for: plan)) + 0.03

        // 过渡期间用透明占位图保持状态项宽度；画面由下面的图层合成。
        button.image = MenuBarIconRenderer.blankImage()
        button.imageScaling = .scaleNone

        // ① 内容通道：旧帧 / 新帧整块交叉淡化。
        //    两端都一致的像素淡化前后完全相同（不会发灰），只有鲸鱼/轨道/虚线环等变化处会显影。
        let oldContent = MenuBarIconRenderer.staticImage(
            for: oldModel, appearance: appearance,
            includeRing: plan.includesRingInContent,
            includeNumber: plan.includesNumberInContent,
            includeComet: !plan.oldCometAnimated)
        let newContent = MenuBarIconRenderer.staticImage(
            for: newModel, appearance: appearance,
            includeRing: plan.includesRingInContent,
            includeNumber: plan.includesNumberInContent,
            includeComet: !plan.newCometAnimated)
        let oldLayer = imageLayer(oldContent, bounds: bounds, zPosition: 10)
        let newLayer = imageLayer(newContent, bounds: bounds, zPosition: 11)
        addTransitionLayer(oldLayer)
        addTransitionLayer(newLayer)
        oldLayer.opacity = 1
        newLayer.opacity = 0
        animate(oldLayer, keyPath: "opacity", from: 1, to: 0,
                duration: contentDuration, easeInEaseOut: true)
        animate(newLayer, keyPath: "opacity", from: 0, to: 1,
                duration: contentDuration, easeInEaseOut: true)
        oldLayer.opacity = 0
        newLayer.opacity = 1

        // ② 数字通道：旧数字上移淡出，新数字从下方浮入（里程表感）。
        if let roll = plan.numberRoll {
            addNumberRoll(roll, oldModel: oldModel, newModel: newModel,
                          appearance: appearance, bounds: bounds)
        }

        // ③ 外环通道：出现 = 顺时针扫入；消散 = 逆时针收回；换色 = 旧环打底 + 新色顺时针覆盖。
        addRingTransition(plan: plan, appearance: appearance, dark: dark,
                          bounds: bounds, duration: scaled(IconMotion.ringSweep))

        // ④ 彗星弧通道：淡入 / 淡出 / 内外半径变形。
        addCometTransition(plan: plan, oldModel: oldModel, newModel: newModel,
                           appearance: appearance)

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            guard let self, self.isTransitioning, self.transitionGeneration == generation else { return }
            self.removeTransitionLayers()
            self.isTransitioning = false
            self.applyStaticImage(model: newModel, appearance: appearance,
                                  cometAnimated: plan.newCometAnimated)
            self.updateComet(model: newModel, appearance: appearance,
                             animate: plan.newCometAnimated, force: true)
            completion()
        }
    }

    // MARK: 通道实现

    private func addNumberRoll(_ roll: IconTransitionPlan.NumberRoll,
                               oldModel: IconModel, newModel: IconModel,
                               appearance: NSAppearance, bounds: CGRect) {
        let duration = scaled(IconMotion.numberRoll)
        let stagger = scaled(IconMotion.numberStagger)
        let slide = IconMotion.numberSlide

        if roll.from != nil,
           let image = MenuBarIconRenderer.numberImage(for: oldModel, appearance: appearance) {
            let layer = imageLayer(image, bounds: bounds, zPosition: 20)
            addTransitionLayer(layer)
            layer.opacity = 1
            animate(layer, keyPath: "opacity", from: 1, to: 0,
                    duration: duration, easeInEaseOut: false)
            animate(layer, keyPath: "transform",
                    from: CATransform3DIdentity,
                    to: CATransform3DMakeTranslation(0, slide, 0),
                    duration: duration, easeInEaseOut: false)
            layer.opacity = 0
            layer.transform = CATransform3DMakeTranslation(0, slide, 0)
        }
        if roll.to != nil,
           let image = MenuBarIconRenderer.numberImage(for: newModel, appearance: appearance) {
            let layer = imageLayer(image, bounds: bounds, zPosition: 21)
            addTransitionLayer(layer)
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
            animate(layer, keyPath: "opacity", from: 0, to: 1,
                    duration: duration, easeInEaseOut: false, delay: stagger)
            animate(layer, keyPath: "transform",
                    from: CATransform3DMakeTranslation(0, -slide, 0),
                    to: CATransform3DIdentity,
                    duration: duration, easeInEaseOut: false, delay: stagger)
        }
    }

    private func addRingTransition(plan: IconTransitionPlan, appearance: NSAppearance,
                                   dark: Bool, bounds: CGRect, duration: CFTimeInterval) {
        func ringLayer(for status: SessionStatus) -> CAShapeLayer {
            let layer = CAShapeLayer()
            layer.frame = bounds
            layer.fillColor = nil
            layer.lineCap = .round
            layer.lineWidth = MenuBarIconRenderer.ringGeometry.width * scale
            layer.strokeStart = 0
            layer.zPosition = 30
            let path = CGMutablePath()
            path.addArc(center: CGPoint(x: bounds.midX, y: bounds.midY),
                        radius: MenuBarIconRenderer.ringGeometry.radius * scale,
                        startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
            layer.path = path
            layer.strokeColor = Theme.statusNSColor(status, dark: dark).cgColor
            return layer
        }

        switch plan.ringMode {
        case .appear:
            guard let status = plan.newRing else { return }
            let layer = ringLayer(for: status)
            layer.strokeEnd = 0
            addTransitionLayer(layer)
            animate(layer, keyPath: "strokeEnd", from: 0, to: 1,
                    duration: duration, easeInEaseOut: true)
            layer.strokeEnd = 1

        case .disappear:
            guard let status = plan.oldRing else { return }
            let layer = ringLayer(for: status)
            layer.strokeEnd = 1
            addTransitionLayer(layer)
            animate(layer, keyPath: "strokeEnd", from: 1, to: 0,
                    duration: duration, easeInEaseOut: true)
            layer.strokeEnd = 0

        case .recolor:
            guard let oldStatus = plan.oldRing, let newStatus = plan.newRing else { return }
            let base = ringLayer(for: oldStatus)
            base.strokeEnd = 1
            addTransitionLayer(base)
            let sweep = ringLayer(for: newStatus)
            sweep.strokeEnd = 0
            sweep.zPosition = 31
            addTransitionLayer(sweep)
            animate(sweep, keyPath: "strokeEnd", from: 0, to: 1,
                    duration: duration, easeInEaseOut: true)
            sweep.strokeEnd = 1

        case .none, .crossfade:
            break
        }
    }

    private func addCometTransition(plan: IconTransitionPlan,
                                    oldModel: IconModel, newModel: IconModel,
                                    appearance: NSAppearance) {
        switch plan.cometMode {
        case .none:
            break

        case .appear:
            guard let spec = MenuBarIconRenderer.cometSpec(for: newModel, appearance: appearance) else { return }
            configureComet(spec: spec)
            cometLayer.opacity = 1
            startSpinIfNeeded()
            animate(cometLayer, keyPath: "opacity", from: 0, to: 1,
                    duration: scaled(IconMotion.cometFade), easeInEaseOut: true)
            cometLayer.opacity = 1

        case .disappear:
            guard let spec = MenuBarIconRenderer.cometSpec(for: oldModel, appearance: appearance) else { return }
            configureComet(spec: spec)
            cometLayer.opacity = 1
            startSpinIfNeeded()
            animate(cometLayer, keyPath: "opacity", from: 1, to: 0,
                    duration: scaled(IconMotion.cometFade), easeInEaseOut: true)
            cometLayer.opacity = 0

        case .moveInward, .moveOutward:
            guard let oldSpec = MenuBarIconRenderer.cometSpec(for: oldModel, appearance: appearance),
                  let newSpec = MenuBarIconRenderer.cometSpec(for: newModel, appearance: appearance) else { return }
            configureComet(spec: oldSpec)
            cometLayer.opacity = 1
            startSpinIfNeeded()
            let duration = scaled(IconMotion.cometMorph)
            let oldPath = arcPath(radius: oldSpec.radius * scale)
            let newPath = arcPath(radius: newSpec.radius * scale)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            cometLayer.path = newPath
            cometLayer.lineWidth = newSpec.width * scale
            CATransaction.commit()
            animate(cometLayer, keyPath: "path", from: oldPath, to: newPath,
                    duration: duration, easeInEaseOut: true)
            animate(cometLayer, keyPath: "lineWidth",
                    from: oldSpec.width * scale, to: newSpec.width * scale,
                    duration: duration, easeInEaseOut: true)
            cometSpec = newSpec
        }
    }

    // MARK: 工具

    private func scaled(_ duration: CFTimeInterval) -> CFTimeInterval {
        duration * AppConfig.animationScale
    }

    private func addTransitionLayer(_ layer: CALayer) {
        button?.layer?.addSublayer(layer)
        transitionLayers.append(layer)
    }

    private func removeTransitionLayers() {
        for layer in transitionLayers { layer.removeFromSuperlayer() }
        transitionLayers.removeAll()
    }

    private func imageLayer(_ image: NSImage, bounds: CGRect, zPosition: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: bounds.size)
        layer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        layer.contentsScale = 2
        layer.contentsGravity = .center
        layer.magnificationFilter = .linear
        layer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        layer.zPosition = zPosition
        return layer
    }

    /// 给图层加一次性显式动画（显式动画默认不会自动移除，由过渡结束统一清层）。
    private func animate(_ layer: CALayer, keyPath: String,
                         from: Any?, to: Any?,
                         duration: CFTimeInterval,
                         easeInEaseOut: Bool,
                         delay: CFTimeInterval = 0) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = max(0.001, duration)
        animation.timingFunction = CAMediaTimingFunction(name: easeInEaseOut ? .easeInEaseOut : .easeOut)
        animation.fillMode = .backwards
        animation.beginTime = CACurrentMediaTime() + delay
        layer.add(animation, forKey: keyPath)
    }
}

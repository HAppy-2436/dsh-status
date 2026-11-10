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

    /// 返回是否换了新的状态项按钮（系统重建菜单栏时会发生）。换实例后调用方必须补静态图，
    /// 否则新按钮没有 `image`，会一直空着直到下一次视觉/外观变化。
    @discardableResult
    func attach(to button: NSStatusBarButton) -> Bool {
        if self.button === button {
            layout()
            return false
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
        return true
    }

    /// 状态项尺寸变化（切桌面/屏幕参数变化）时同步图层；过渡中遇到尺寸变化由控制器强制落静态帧。
    func layout() {
        guard let button else { return }
        let bounds = button.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        // 尺寸没变时不做任何事：这个方法每次 refresh 都会调用，重复写 frame 会打扰渲染服务器。
        if cometLayer.superlayer != nil, cometBounds == bounds { return }
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

    /// 图层几何与静态图共用同一坐标系（22pt 画布，1pt = 1 单位）。
    /// 不能用按钮高度推导缩放：`button.image` 是 22×22pt 且 `imageScaling = .scaleNone`，
    /// 菜单栏厚度 ≠22pt 时按比例放大 CA 几何会导致过渡结束瞬间尺寸跳变。
    private var scale: CGFloat { 1 }

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
        setModel(opacity: 1) { cometLayer.opacity = $0 }
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
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cometLayer.isHidden = true
        cometLayer.opacity = 0
        CATransaction.commit()
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

    // MARK: 静态图缓存

    /// 决定 `button.image` 内容的全部输入。状态/外观没变时直接复用同一张 NSImage：
    ///   · 不必重复跑位图渲染（数字阴影走高斯模糊，单次约 0.5–1ms）；
    ///   · 不重复给 `button.image` 赋新对象 —— macOS 27 上重复设图会触发 `NSStatusItem`
    ///     快照重绘，是「外观 KVO 自激循环」的另一半放大点。
    private struct StaticImageKey: Equatable {
        let statuses: [SessionStatus]
        let connected: Bool
        let numberMode: CenterNumberMode
        let idleStyle: MenuBarIdleStyle
        let dark: Bool
        let cometAnimated: Bool
    }
    private var lastStaticKey: StaticImageKey?
    private var lastStaticImage: NSImage?

    private func applyStaticImage(model: IconModel, appearance: NSAppearance, cometAnimated: Bool) {
        guard let button else { return }
        let key = StaticImageKey(
            statuses: model.statuses,
            connected: model.connected,
            numberMode: model.numberMode,
            idleStyle: model.idleStyle,
            dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            cometAnimated: cometAnimated
        )
        if key == lastStaticKey, let image = lastStaticImage {
            // 画面内容没变：复用缓存图；只有按钮当前不是这张图时才补设（例如刚取消过渡、按钮仍是占位图）。
            if button.image !== image {
                button.image = image
                button.imageScaling = .scaleNone
            }
            return
        }
        let image: NSImage
        if cometAnimated {
            image = MenuBarIconRenderer.staticImage(for: model, appearance: appearance)
        } else {
            image = MenuBarIconRenderer.image(for: model, appearance: appearance)
        }
        lastStaticKey = key
        lastStaticImage = image
        button.image = image
        button.imageScaling = .scaleNone
    }

    /// 取消进行中的过渡（立即移除所有过渡图层；静态图由调用方补）。
    /// 常驻彗星层上的过渡动画（opacity / path / lineWidth）也一并清掉，
    /// 避免取消后残留动画继续把彗星带到中间态（旋转/呼吸保留，不重启）。
    func cancelTransition() {
        transitionGeneration += 1
        removeTransitionLayers()
        for key in ["opacity", "path", "lineWidth"] {
            cometLayer.removeAnimation(forKey: key)
        }
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

        // ① 内容通道：只让「变了的内容原子」交叉淡化；两端相同的内容原子走一张静态公共层。
        //    旧做法无条件双图淡化，会让相同像素在 t=0.5 处叠成 75% 不透明度（环/数字闪一下）。
        let cometAnimationChanged = plan.oldCometAnimated != plan.newCometAnimated
        if !plan.contentAtomChanged && cometAnimationChanged {
            // 罕见：仅「播放运行动画」开关变化。旧弧是旋转图层、新弧是静态弧，
            // 用一次性交叉淡化把两者接上（其余原子本来就不动，可接受这 0.24s 的轻微淡化）。
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
            addContentCrossfade(old: oldContent, new: newContent,
                                bounds: bounds, duration: contentDuration)
        } else if !plan.contentAtomChanged {
            // 内容原子不变：环/数字/轨道/鲸鱼/静态弧都直接静态落位，不淡化（不产生亮度凹陷）。
            let common = MenuBarIconRenderer.staticImage(
                for: newModel, appearance: appearance,
                includeRing: plan.includesRingInContent,
                includeNumber: plan.includesNumberInContent,
                includeComet: !plan.newCometAnimated)
            let layer = imageLayer(common, bounds: bounds, zPosition: 10)
            addTransitionLayer(layer)
            setModel(opacity: 1, for: layer)
        } else {
            // 内容原子变化：公共原子（同色环 / 未变的数字）单独一张静态层；旧/新内容原子交叉淡化。
            if plan.ringCommon || plan.numberCommon {
                let common = MenuBarIconRenderer.staticImage(
                    for: newModel, appearance: appearance,
                    includeRing: plan.ringCommon,
                    includeNumber: plan.numberCommon,
                    includeComet: false,
                    includeContent: false)
                let layer = imageLayer(common, bounds: bounds, zPosition: 10)
                addTransitionLayer(layer)
                setModel(opacity: 1, for: layer)
            }
            // 环只有「断连交叉淡化」时才随内容淡；数字只有连接性变化时才随内容淡（其余由各自通道处理）。
            let oldDelta = MenuBarIconRenderer.staticImage(
                for: oldModel, appearance: appearance,
                includeRing: plan.includesRingInContent && !plan.ringCommon,
                includeNumber: plan.connectivityChanged,
                includeComet: !plan.oldCometAnimated,
                includeContent: true)
            let newDelta = MenuBarIconRenderer.staticImage(
                for: newModel, appearance: appearance,
                includeRing: plan.includesRingInContent && !plan.ringCommon,
                includeNumber: plan.connectivityChanged,
                includeComet: !plan.newCometAnimated,
                includeContent: true)
            addContentCrossfade(old: oldDelta, new: newDelta,
                                bounds: bounds, duration: contentDuration)
        }

        // ② 数字通道：旧数字上移淡出，新数字从下方浮入（里程表感）。
        if let roll = plan.numberRoll {
            addNumberRoll(roll, oldModel: oldModel, newModel: newModel,
                          appearance: appearance, bounds: bounds,
                          delay: scaled(plan.numberDelay))
        }

        // ③ 外环通道：出现 = 顺时针扫入；消散 = 逆时针收回；换色 = 旧环打底 + 新色顺时针覆盖。
        addRingTransition(plan: plan, appearance: appearance, dark: dark,
                          bounds: bounds, duration: scaled(plan.ringDuration),
                          delay: scaled(plan.ringDelay))

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

    /// 内容通道：旧/新两张内容位图做交叉淡化（只用于「内容原子真的变了」的两端）。
    private func addContentCrossfade(old: NSImage, new: NSImage,
                                     bounds: CGRect, duration: CFTimeInterval) {
        let oldLayer = imageLayer(old, bounds: bounds, zPosition: 10)
        let newLayer = imageLayer(new, bounds: bounds, zPosition: 11)
        addTransitionLayer(oldLayer)
        addTransitionLayer(newLayer)
        setModel(opacity: 0, for: oldLayer)
        setModel(opacity: 1, for: newLayer)
        animate(oldLayer, keyPath: "opacity", from: 1, to: 0,
                duration: duration, easeInEaseOut: true)
        animate(newLayer, keyPath: "opacity", from: 0, to: 1,
                duration: duration, easeInEaseOut: true)
    }

    private func addNumberRoll(_ roll: IconTransitionPlan.NumberRoll,
                               oldModel: IconModel, newModel: IconModel,
                               appearance: NSAppearance, bounds: CGRect,
                               delay: CFTimeInterval) {
        let duration = scaled(IconMotion.numberRoll)
        let stagger = scaled(IconMotion.numberStagger)
        let slide = IconMotion.numberSlide
        // CALayer 在本状态项里是 y 轴朝下（实测 +y 在屏幕上向下），因此：
        // 增加 = 旧值向上出（-y）、新值从下方进（+y → 0）；减少反之。
        // 字形数变化（9→10、99→99+）时槽宽同时改变：不滚动，原地交叉淡化（避免宽度变化 + 位移一起抖）。
        // 判位数用**渲染文本**（>99 都是「99+」），避免数值位数与显示位数不一致。
        let glyphCountChanged: Bool = {
            guard let from = roll.from, let to = roll.to else { return false }
            return MenuBarIconRenderer.numberText(for: from).count
                != MenuBarIconRenderer.numberText(for: to).count
        }()
        let direction = glyphCountChanged ? 0 : roll.direction
        // direction: +1 增加 / -1 减少 / 0 出现、消失或字形数变化（原地淡入淡出）
        let oldExitY = direction > 0 ? -slide : (direction < 0 ? slide : 0)
        let newEnterY = direction > 0 ? slide : (direction < 0 ? -slide : 0)

        if roll.from != nil,
           let image = MenuBarIconRenderer.numberImage(for: oldModel, appearance: appearance) {
            let layer = imageLayer(image, bounds: bounds, zPosition: 20)
            addTransitionLayer(layer)
            setModel(opacity: 0, transform: CATransform3DMakeTranslation(0, oldExitY, 0),
                     for: layer)
            animate(layer, keyPath: "opacity", from: 1, to: 0,
                    duration: duration, easeInEaseOut: false, delay: delay)
            if direction != 0 {
                animate(layer, keyPath: "transform",
                        from: CATransform3DIdentity,
                        to: CATransform3DMakeTranslation(0, oldExitY, 0),
                        duration: duration, easeInEaseOut: false, delay: delay)
            }
        }
        if roll.to != nil,
           let image = MenuBarIconRenderer.numberImage(for: newModel, appearance: appearance) {
            let layer = imageLayer(image, bounds: bounds, zPosition: 21)
            addTransitionLayer(layer)
            setModel(opacity: 1, transform: CATransform3DIdentity, for: layer)
            // 滚动（有方向）才用 0.05s 错峰；出现/消失/字形数变化是原地交叉淡化，不叠加错峰
            //（否则新值比文档晚 0.05s 入场，M1/M18 的 0.10→0.28 会变成 0.15→0.33）。
            let enterDelay = direction != 0 ? delay + stagger : delay
            if direction != 0 {
                animate(layer, keyPath: "opacity", from: 0, to: 1,
                        duration: duration, easeInEaseOut: false, delay: enterDelay)
                animate(layer, keyPath: "transform",
                        from: CATransform3DMakeTranslation(0, newEnterY, 0),
                        to: CATransform3DIdentity,
                        duration: duration, easeInEaseOut: false, delay: enterDelay)
            } else {
                // 出现（nil → n）：原地淡入，不做位移（槽位是空的，没有「滚动」语义）。
                animate(layer, keyPath: "opacity", from: 0, to: 1,
                        duration: duration, easeInEaseOut: true, delay: enterDelay)
            }
        }
    }

    private func addRingTransition(plan: IconTransitionPlan, appearance: NSAppearance,
                                   dark: Bool, bounds: CGRect, duration: CFTimeInterval,
                                   delay: CFTimeInterval) {
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
            setModel(strokeEnd: 1, for: layer)
            addTransitionLayer(layer)
            animate(layer, keyPath: "strokeEnd", from: 0, to: 1,
                    duration: duration, easeInEaseOut: true, delay: delay)

        case .disappear:
            guard let status = plan.oldRing else { return }
            let layer = ringLayer(for: status)
            setModel(strokeEnd: 0, for: layer)
            addTransitionLayer(layer)
            animate(layer, keyPath: "strokeEnd", from: 1, to: 0,
                    duration: duration, easeInEaseOut: true, delay: delay)

        case .recolor:
            guard let oldStatus = plan.oldRing, let newStatus = plan.newRing else { return }
            let base = ringLayer(for: oldStatus)
            setModel(strokeEnd: 1, for: base)
            addTransitionLayer(base)
            let sweep = ringLayer(for: newStatus)
            setModel(strokeEnd: 1, for: sweep)
            sweep.zPosition = 31
            addTransitionLayer(sweep)
            animate(sweep, keyPath: "strokeEnd", from: 0, to: 1,
                    duration: duration, easeInEaseOut: true, delay: delay)

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
            setModel(opacity: 1) { cometLayer.opacity = $0 }
            startSpinIfNeeded()
            animate(cometLayer, keyPath: "opacity", from: 0, to: 1,
                    duration: scaled(IconMotion.cometFade), easeInEaseOut: true,
                    delay: scaled(plan.cometDelay))

        case .disappear:
            guard let spec = MenuBarIconRenderer.cometSpec(for: oldModel, appearance: appearance) else { return }
            configureComet(spec: spec)
            startSpinIfNeeded()
            animate(cometLayer, keyPath: "opacity", from: 1, to: 0,
                    duration: scaled(IconMotion.cometFade), easeInEaseOut: true,
                    delay: scaled(plan.cometDelay))
            setModel(opacity: 0) { cometLayer.opacity = $0 }

        case .moveInward, .moveOutward:
            guard let oldSpec = MenuBarIconRenderer.cometSpec(for: oldModel, appearance: appearance),
                  let newSpec = MenuBarIconRenderer.cometSpec(for: newModel, appearance: appearance) else { return }
            configureComet(spec: oldSpec)
            setModel(opacity: 1) { cometLayer.opacity = $0 }
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
                    duration: duration, easeInEaseOut: true,
                    delay: scaled(plan.cometDelay))
            animate(cometLayer, keyPath: "lineWidth",
                    from: oldSpec.width * scale, to: newSpec.width * scale,
                    duration: duration, easeInEaseOut: true,
                    delay: scaled(plan.cometDelay))
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

    /// 关闭隐式动画地写模型值：避免「设置终值」触发 0.25s 隐式动画把显式动画顶掉。
    private func setModel(opacity: Float, for layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
    }

    private func setModel(opacity: Float, transform: CATransform3D, for layer: CALayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        layer.transform = transform
        CATransaction.commit()
    }

    private func setModel(strokeEnd: CGFloat, for layer: CAShapeLayer) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.strokeEnd = strokeEnd
        CATransaction.commit()
    }

    private func setModel(opacity: Float, _ apply: (Float) -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        apply(opacity)
        CATransaction.commit()
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

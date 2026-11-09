import AppKit
import CoreText

// MARK: - 菜单栏图标 v4：双层环
//
//  · 空闲（没有任何非空闲任务）：纯白（浅色菜单栏为近黑）DeepSeek 鲸鱼 Logo
//  · 只有「运行中」：整个圆环是一段**动态旋转弧**（菜单栏前景色），中心显示运行中数量
//  · 只有「需要介入」（待回答 / 已停止 / 已完成）：圆环按数量比例合并同色，
//    相邻颜色**渐变过渡**，中心显示关注数
//  · 「运行中」+「需要介入」同时存在：外层 = 彩色渐变环，内层 = 动态旋转弧（不放数字）
//  · 未连接：灰色虚线环 + 短横
//
//  颜色只代表「需要你介入」：黄 = 待回答、红 = 已停止、绿 = 已完成。
//  运行中改用中性色动态弧，因此不再与蓝色壁纸撞色。

struct IconModel: Equatable {
    /// 非空闲任务（会话）状态，已按设置过滤。
    var statuses: [SessionStatus] = []
    var connected = true
    var numberMode: CenterNumberMode = .attention
    /// 空闲时显示的品牌图标（鲸鱼 / 虚线双环）；默认鲸鱼。
    var idleStyle: MenuBarIdleStyle = .whale
    /// 运行中动态弧的相位（角度）；由 StatusItemController 定时推进。
    var animationPhase: CGFloat = 0
    /// 动画累计时间（秒），用于让弧长做呼吸变化。
    var animationTime: TimeInterval = 0

    var waitingCount: Int { statuses.filter { $0 == .waiting }.count }
    var runningCount: Int { statuses.filter { $0 == .running }.count }
    var completedCount: Int { statuses.filter { $0 == .completed }.count }
    var stoppedCount: Int { statuses.filter { $0 == .stopped }.count }
    /// 需要介入的数量。
    var attentionCount: Int { waitingCount + stoppedCount + completedCount }
    var isEmpty: Bool { statuses.isEmpty }

    /// 当前优先级最高的待办状态（红 > 黄 > 绿）；没有任何待办则为 nil。
    var topPriorityStatus: SessionStatus? {
        if stoppedCount > 0 { return .stopped }
        if waitingCount > 0 { return .waiting }
        if completedCount > 0 { return .completed }
        return nil
    }

    /// 实际画在图标中心的数字（nil = 不显示）。
    /// 未连接/空闲不画；双层环（外环 + 内层彗星）时 22pt 放不下第三层，也不画。
    var visibleCenterNumber: Int? {
        guard connected, !isEmpty else { return nil }
        if topPriorityStatus != nil && runningCount > 0 { return nil }
        return centerNumber
    }

    /// 中心数字（nil = 不显示）。双层环时由渲染层省略。
    var centerNumber: Int? {
        guard !statuses.isEmpty else { return nil }
        switch numberMode {
        case .hidden:
            return nil
        case .all:
            return statuses.count
        case .attention:
            if attentionCount > 0 { return attentionCount }
            return runningCount > 0 ? runningCount : nil
        case .matched:
            if let top = topPriorityStatus {
                switch top {
                case .stopped: return stoppedCount
                case .waiting: return waitingCount
                case .completed: return completedCount
                default: break
                }
            }
            return runningCount > 0 ? runningCount : nil
        }
    }
}

enum MenuBarIconRenderer {
    static let canvas: CGFloat = 22
    private static let center = NSPoint(x: 11, y: 11)
    private static let outerRadius: CGFloat = 7.9
    private static let outerWidth: CGFloat = 2.1
    private static let innerRadius: CGFloat = 4.95
    private static let innerWidth: CGFloat = 1.4

    // MARK: 对外入口

    /// 渲染完整图标（含彗星弧的静态帧），用于预览/截图/降级。
    static func image(for model: IconModel, appearance: NSAppearance) -> NSImage {
        render(width: canvas, height: canvas, appearance: appearance) { _ in
            draw(model: model, appearance: appearance, includeComet: true, cometSweep: nil)
        }
    }

    /// 只渲染静态层（外环/轨道/数字/鲸鱼/虚线），供 Core Animation 图层复用。
    /// `includeRing == false` 时不画外层彩色环（状态切换过渡用：环由独立图层扫入/收回）。
    /// `includeNumber == false` 时不画中心数字（数字切换用独立图层做滚动）。
    static func staticImage(for model: IconModel, appearance: NSAppearance,
                            includeRing: Bool = true,
                            includeNumber: Bool = true,
                            includeComet: Bool = false,
                            includeContent: Bool = true) -> NSImage {
        render(width: canvas, height: canvas, appearance: appearance) { _ in
            draw(model: model, appearance: appearance, includeComet: includeComet, cometSweep: nil,
                 includeRing: includeRing, includeNumber: includeNumber, includeContent: includeContent)
        }
    }

    /// 中心数字的渲染文本（>99 统一显示 `99+`）。绘制与过渡状态判定共用同一事实来源，
    /// 避免「数值变了但渲染文本相同」（100→101）仍被当成数字变化播放滚动。
    static func numberText(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    /// 只画中心数字（透明底），供数字滚动过渡单独做图层。
    static func numberImage(for model: IconModel, appearance: NSAppearance) -> NSImage? {
        guard let number = model.visibleCenterNumber else { return nil }
        return render(width: canvas, height: canvas, appearance: appearance) { _ in
            drawCount(number, dark: isDark(appearance))
        }
    }

    /// 完全透明的占位图：过渡期间临时替换 `button.image`，保持状态项宽度不变
    /// （真正的画面由 Core Animation 图层合成；结束后换回完整静态图）。
    static func blankImage() -> NSImage {
        render(width: canvas, height: canvas,
               appearance: NSAppearance(named: .darkAqua)!) { _ in }
    }

    /// 彗星弧的几何参数（半径/线宽）与颜色。返回 nil 表示当前状态没有运行中动画。
    struct CometSpec {
        let radius: CGFloat
        let width: CGFloat
        let color: NSColor
    }

    static func cometSpec(for model: IconModel, appearance: NSAppearance) -> CometSpec? {
        guard model.connected, !model.isEmpty, model.runningCount > 0 else { return nil }
        let dark = isDark(appearance)
        let hasOuter = model.topPriorityStatus != nil
        let color = (dark ? NSColor.white : NSColor(hex: 0x1F1F23)).withAlphaComponent(0.92)
        return CometSpec(radius: hasOuter ? innerRadius : outerRadius,
                         width: hasOuter ? innerWidth : outerWidth,
                         color: color)
    }

    static var canvasCenter: CGPoint { center }

    /// 外环的半径/线宽（点）。
    static var ringGeometry: (radius: CGFloat, width: CGFloat) { (outerRadius, outerWidth) }

    /// 当前状态外环的颜色；nil 表示无外环（空闲 / 未连接）。
    static func ringColor(for model: IconModel, appearance: NSAppearance) -> NSColor? {
        guard model.connected, let top = model.topPriorityStatus else { return nil }
        return Theme.statusNSColor(top, dark: isDark(appearance))
    }

    static func tooltip(for model: IconModel) -> String {
        guard model.connected else { return "DSH 未连接" }
        guard !model.isEmpty else { return "DSH：全部空闲" }
        var parts: [String] = []
        if model.waitingCount > 0 { parts.append("\(model.waitingCount) 待回答") }
        if model.runningCount > 0 { parts.append("\(model.runningCount) 运行中") }
        if model.completedCount > 0 { parts.append("\(model.completedCount) 已完成") }
        if model.stoppedCount > 0 { parts.append("\(model.stoppedCount) 已停止") }
        return "DSH：" + parts.joined(separator: " · ")
    }

    // MARK: 绘制

    /// - Parameters:
    ///   - includeContent: 是否画「内容原子」（鲸鱼 / 轨道 / 未连接虚线环）。状态过渡时用来拆出
    ///     **不变的公共原子**（单独做静态层，避免双图交叉淡化把它压到 75% 亮度）与**变化的内容原子**。
    private static func draw(model: IconModel, appearance: NSAppearance,
                             includeComet: Bool,
                             cometSweep: (start: CGFloat, sweep: CGFloat)?,
                             includeRing: Bool = true,
                             includeNumber: Bool = true,
                             includeContent: Bool = true) {
        let dark = isDark(appearance)

        guard model.connected else {
            if includeContent { drawDisconnected(dark: dark) }
            return
        }

        if model.isEmpty {
            if includeContent {
                switch model.idleStyle {
                case .whale: drawWhale(dark: dark)
                case .dashedDoubleRing: drawDashedDoubleRing(dark: dark)
                }
            }
            return
        }

        // 外环：始终一整圈，颜色 = 当前最高优先级的待办状态（红 > 黄 > 绿）
        let top = model.topPriorityStatus
        let hasOuter = top != nil

        if let top, includeRing {
            Theme.statusNSColor(top, dark: dark).setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(
                x: center.x - outerRadius,
                y: center.y - outerRadius,
                width: outerRadius * 2,
                height: outerRadius * 2
            ))
            ring.lineWidth = outerWidth
            ring.stroke()
        }

        if model.runningCount > 0 {
            if includeContent {
                if hasOuter {
                    // 双层：内层细轨道；CA 模式下彗星弧由图层绘制
                    drawSpinnerTrack(dark: dark, radius: innerRadius, width: innerWidth)
                } else {
                    // 只有运行中：轨道 + （可选）静态彗星弧
                    drawSpinnerTrack(dark: dark, radius: outerRadius, width: outerWidth)
                }
            }
            if includeComet {
                let radius = hasOuter ? innerRadius : outerRadius
                let width = hasOuter ? innerWidth : outerWidth
                let sweep = cometSweep ?? (start: 90, sweep: 120)
                drawActivityArc(dark: dark, radius: radius, width: width,
                                startAngle: sweep.start, sweep: sweep.sweep, alpha: 1)
            }
        }

        // 中心数字：双层时省略（22pt 放不下第三层）
        if includeNumber, !(hasOuter && model.runningCount > 0), let number = model.centerNumber {
            drawCount(number, dark: dark)
        }
    }

    /// 只有运行中时的活动弧（静止时固定在右上，过渡时扫入）。
    private static func drawActivityArc(dark: Bool, radius: CGFloat, width: CGFloat,
                                        startAngle: CGFloat, sweep: CGFloat, alpha: CGFloat) {
        guard alpha > 0.01 else { return }
        let base = dark ? NSColor.white : NSColor(hex: 0x1F1F23)
        base.withAlphaComponent(0.92 * alpha).setStroke()
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: startAngle, endAngle: startAngle - sweep, clockwise: true)
        arc.lineWidth = width
        arc.lineCapStyle = .round
        arc.stroke()
    }

    // MARK: 空闲：鲸鱼

    private static func drawWhale(dark: Bool) {
        let logoRect = NSRect(
            x: center.x - 9.4,
            y: center.y - 9.4 * WhaleLogo.viewBoxHeight / WhaleLogo.viewBoxWidth,
            width: 18.8,
            height: 18.8 * WhaleLogo.viewBoxHeight / WhaleLogo.viewBoxWidth
        )
        let path = WhaleLogo.path(fitting: logoRect)
        (dark ? NSColor.white : NSColor(hex: 0x1F1F23)).setFill()
        path.fill()
    }

    /// 空闲可选的品牌「双层环」线稿：外环虚线 + 内环细实线，单色、中性。
    ///
    /// 与「未连接」的单环 + 短横区分：这里是**两层同心环**，且不使用状态色；
    /// 深浅色仍由菜单栏实际外观决定（`isDark`）。
    private static func drawDashedDoubleRing(dark: Bool) {
        let ink = dark ? NSColor.white : NSColor(hex: 0x1F1F23)

        // 外环：粗一点的圆头虚线，22pt 下保持 2–3 段 dash 可辨。
        ink.withAlphaComponent(dark ? 0.94 : 0.88).setStroke()
        let outer = NSBezierPath(ovalIn: NSRect(
            x: center.x - outerRadius, y: center.y - outerRadius,
            width: outerRadius * 2, height: outerRadius * 2
        ))
        outer.lineWidth = 1.9
        outer.lineCapStyle = .round
        outer.setLineDash([2.8, 2.4], count: 2, phase: 0)
        outer.stroke()

        // 内环：细实线，形成「双层」结构（品牌双环）。
        ink.withAlphaComponent(dark ? 0.62 : 0.55).setStroke()
        let inner = NSBezierPath(ovalIn: NSRect(
            x: center.x - innerRadius, y: center.y - innerRadius,
            width: innerRadius * 2, height: innerRadius * 2
        ))
        inner.lineWidth = 1.15
        inner.lineCapStyle = .round
        inner.stroke()
    }

    // MARK: 运行中动态弧

    /// 轨道：淡色整环，始终同心、静止。
    private static func drawSpinnerTrack(dark: Bool, radius: CGFloat, width: CGFloat) {
        let base = dark ? NSColor.white : NSColor(hex: 0x1F1F23)
        base.withAlphaComponent(0.16).setStroke()
        let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                                width: radius * 2, height: radius * 2))
        track.lineWidth = width
        track.stroke()
    }

    // MARK: 未连接

    private static func drawDisconnected(dark: Bool) {
        let color = NSColor.labelColor.withAlphaComponent(dark ? 0.42 : 0.36)
        color.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - outerRadius,
            y: center.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        ))
        ring.lineWidth = 1.6
        ring.lineCapStyle = .round
        ring.setLineDash([2.2, 3.2], count: 2, phase: 0)
        ring.stroke()

        color.setFill()
        let minus = NSRect(x: center.x - 3.0, y: center.y - 0.7, width: 6.0, height: 1.4)
        NSBezierPath(roundedRect: minus, xRadius: 0.7, yRadius: 0.7).fill()
    }

    // MARK: 中心数字

    private static func drawCount(_ count: Int, dark: Bool) {
        let text = numberText(for: count)
        let size: CGFloat
        switch text.count {
        case 1: size = 10.4
        case 2: size = 9.0
        default: size = 6.4
        }
        let font = roundedFont(size: size, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dark ? NSColor.white : NSColor(hex: 0x0F1115),
            .kern: 0.1
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let centroidX = lineAreaCentroidX(line)
        guard let context = NSGraphicsContext.current?.cgContext else {
            let textSize = attributed.size()
            attributed.draw(at: NSPoint(x: center.x - textSize.width / 2,
                                        y: center.y - textSize.height / 2 + 0.3))
            return
        }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -0.3), blur: 1.0,
                          color: (dark ? NSColor.black.withAlphaComponent(0.35)
                                       : NSColor.black.withAlphaComponent(0.16)).cgColor)
        // 1–2 位数字：按字形轮廓面积质心做水平居中（对「1」这类重心偏右的字形做视觉居中）。
        // 3 位（只有「99+」）：带一个「+」号，面积质心会把它整体推右、压到外环内缘（实测右侧越界 1.9pt），
        // 改用 ink bbox 居中；字号也收到 6.4pt 保证左右各留 ≥0.4pt 余量。
        let anchorX = text.count >= 3 ? ink.midX : (centroidX ?? ink.midX)
        context.textPosition = CGPoint(x: center.x - anchorX, y: center.y - ink.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// 按字形轮廓面积质心计算水平中心（对「1」这类重心偏右的字形做视觉居中）。
    private static func lineAreaCentroidX(_ line: CTLine) -> CGFloat? {
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        var totalArea: CGFloat = 0
        var totalMoment: CGFloat = 0
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            for i in 0..<count {
                guard let path = CTFontCreatePathForGlyph(runFont, glyphs[i], nil) else { continue }
                let (area, moment) = pathAreaMomentX(path, offsetX: positions[i].x)
                totalArea += area
                totalMoment += moment
            }
        }
        guard abs(totalArea) > 0.0001 else { return nil }
        return totalMoment / totalArea
    }

    /// 返回 (有向面积, ∫x dA)；轮廓按 0.05 步长采样，精度足够 icon 尺寸。
    private static func pathAreaMomentX(_ path: CGPath, offsetX: CGFloat) -> (CGFloat, CGFloat) {
        var totalArea: CGFloat = 0
        var totalMoment: CGFloat = 0
        var points: [CGPoint] = []

        func flush() {
            guard points.count > 2 else { points = []; return }
            var area: CGFloat = 0
            var moment: CGFloat = 0
            var j = points.count - 1
            for i in 0..<points.count {
                let a = points[j], b = points[i]
                let cross = a.x * b.y - b.x * a.y
                area += cross
                moment += (a.x + b.x) * cross
                j = i
            }
            area *= 0.5
            if abs(area) > 0.000001 {
                totalArea += area
                totalMoment += moment / 6
            }
            points = []
        }

        path.applyWithBlock { element in
            let p = element.pointee
            switch p.type {
            case .moveToPoint:
                flush()
                points = [CGPoint(x: p.points[0].x + offsetX, y: p.points[0].y)]
            case .addLineToPoint:
                points.append(CGPoint(x: p.points[0].x + offsetX, y: p.points[0].y))
            case .addQuadCurveToPoint:
                let s = points.last ?? CGPoint(x: p.points[0].x + offsetX, y: p.points[0].y)
                let c = CGPoint(x: p.points[0].x + offsetX, y: p.points[0].y)
                let e = CGPoint(x: p.points[1].x + offsetX, y: p.points[1].y)
                for t in stride(from: CGFloat(0.05), through: 1.0, by: 0.05) {
                    let mt = 1 - t
                    points.append(CGPoint(x: mt * mt * s.x + 2 * mt * t * c.x + t * t * e.x,
                                          y: mt * mt * s.y + 2 * mt * t * c.y + t * t * e.y))
                }
            case .addCurveToPoint:
                let s = points.last ?? CGPoint(x: p.points[0].x + offsetX, y: p.points[0].y)
                let c1 = CGPoint(x: p.points[0].x + offsetX, y: p.points[0].y)
                let c2 = CGPoint(x: p.points[1].x + offsetX, y: p.points[1].y)
                let e = CGPoint(x: p.points[2].x + offsetX, y: p.points[2].y)
                for t in stride(from: CGFloat(0.05), through: 1.0, by: 0.05) {
                    let mt = 1 - t
                    points.append(CGPoint(
                        x: mt * mt * mt * s.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * e.x,
                        y: mt * mt * mt * s.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * e.y
                    ))
                }
            case .closeSubpath:
                flush()
            @unknown default:
                break
            }
        }
        flush()
        return (totalArea, totalMoment)
    }

    private static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if let descriptor = base.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: descriptor, size: size) {
            return font
        }
        return base
    }

    static func render(width: CGFloat, height: CGFloat, appearance: NSAppearance,
                       draw: (NSRect) -> Void) -> NSImage {
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(ceil(width * scale))),
            pixelsHigh: max(1, Int(ceil(height * scale))),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return NSImage(size: NSSize(width: width, height: height))
        }
        rep.size = NSSize(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return NSImage(size: NSSize(width: width, height: height))
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            draw(NSRect(x: 0, y: 0, width: width, height: height))
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }
}

// MARK: - App 图标（原创「状态环」，菜单栏空闲态鲸鱼保持不变）

/// App / 通知 / 退出确认弹窗共用的应用图标：原创「双层环」品牌标识。
///
/// 设计寓意（不含任何 DeepSeek / DSH 官方素材；菜单栏空闲态的鲸鱼 glyph 见 WhaleLogo）：
/// - **深色圆角方底**：按 macOS App 图标栅格绘制（1024 画布内 824 的 Squircle），带投影、
///   顶部柔光、底部暗角与内描边高光；浅色/深色背景和通知横幅里都是完整、独立的 App 图标。
/// - **双层环**：外环品牌绿、内环冷白，直接对应菜单栏图标里最有辨识度的「双层环」状态
///   （外环 = 待办优先级、内层 = 运行中），把产品的状态语言做成了品牌标识。
///
/// 缩放说明：几何全部按 1024 设计稿等比缩放；16/32/64/128/256/512/1024 逐尺寸可辨
/// （构建 .icns 时由 1024 源图下采样）。
enum AppIconRenderer {
    // MARK: 调色板
    // App 图标用比 22pt 菜单栏调色更亮的同源状态色（小尺寸菜单栏需要压暗，大图标需要更鲜艳）。
    private static let baseTop = NSColor(hex: 0x2C3756)
    private static let baseBottom = NSColor(hex: 0x0B0F18)
    private static let baseGlow = NSColor(hex: 0x34C759)

    // MARK: 几何（1024 设计稿基准，按 size 等比缩放）
    private static let design: CGFloat = 1024
    /// macOS App 图标栅格：1024 画布内圆角方形边长 824（四周各留 100 给投影/呼吸空间）。
    private static let baseRatio: CGFloat = 824 / design
    /// 底板超椭圆指数（2 = 圆，越大越方；≈5 观感接近 macOS Squircle）。
    private static let baseExponent: CGFloat = 5
    private static let ringRadius: CGFloat = 294
    private static let ringWidth: CGFloat = 84
    /// 四段环之间的视觉缝隙（度）。圆头端点本身会吃掉 / 补上一部分，故用几何角度反推。
    private static let ringGap: CGFloat = 2.5
    private static let centerDotRadius: CGFloat = 56

    /// 渲染 App 图标。`size` 为点数：1024 → 构建 .icns 的源图，72 → 退出确认弹窗。
    /// 返回值按需重绘（不预先栅格化），在不同屏幕 scale 下都保持清晰。
    static func image(size: CGFloat) -> NSImage {
        let side = max(1, size)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let scale = side / design
            let baseSide = side * baseRatio
            drawBase(in: NSRect(x: (side - baseSide) / 2, y: (side - baseSide) / 2,
                                width: baseSide, height: baseSide),
                     scale: scale)
            let center = NSPoint(x: side / 2, y: side / 2)
            drawDoubleRing(center: center, scale: scale)
            return true
        }
    }

    // MARK: 底板

    private static func drawBase(in rect: NSRect, scale: CGFloat) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        let path = squircleCGPath(in: rect)

        // 投影：先画一层黑色 Squircle，随后被不透明渐变底完全盖住，只在边缘外留下阴影
        NSGraphicsContext.saveGraphicsState()
        cg.addPath(path)
        cg.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 32 * scale,
                     color: NSColor.black.withAlphaComponent(0.45).cgColor)
        cg.setFillColor(NSColor.black.cgColor)
        cg.fillPath(using: .winding)
        NSGraphicsContext.restoreGraphicsState()

        // 底板：深色渐变 + 环心冷光 + 顶部柔光 + 底部暗角
        NSGraphicsContext.saveGraphicsState()
        cg.addPath(path)
        cg.clip()
        NSGradient(colors: [baseBottom, baseTop])?.draw(in: rect, angle: 90)
        let glowSide = rect.width * 0.9
        NSGradient(colors: [baseGlow.withAlphaComponent(0.10), baseGlow.withAlphaComponent(0)])?
            .draw(in: NSRect(x: rect.midX - glowSide / 2, y: rect.midY - glowSide / 2,
                             width: glowSide, height: glowSide),
                  relativeCenterPosition: .zero)
        NSGradient(colors: [NSColor.white.withAlphaComponent(0.09), NSColor.white.withAlphaComponent(0)])?
            .draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height * 0.5),
                  angle: -90)
        NSGradient(colors: [NSColor.black.withAlphaComponent(0.20), NSColor.black.withAlphaComponent(0)])?
            .draw(in: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.4),
                  angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        // 内描边高光：把底板「托」起来一层
        fillStrokedPath(squircleCGPath(in: rect.insetBy(dx: 2 * scale, dy: 2 * scale)),
                        lineWidth: 3.6 * scale, in: rect,
                        colors: [NSColor.white.withAlphaComponent(0.03),
                                 NSColor.white.withAlphaComponent(0.30)],
                        angle: 90)
    }

    // MARK: 品牌「双层环」

    /// 品牌标识 = 双层环：外环品牌绿、内环冷白。
    /// 对应菜单栏图标里最具特色的「双层环」状态（外环 = 待办优先级、内层 = 运行中），
    /// 作为 App / 通知 / 退出弹窗图标；不含任何 DeepSeek 品牌素材。
    private static let innerRingRadius: CGFloat = 168
    private static let innerRingWidth: CGFloat = 42
    private static let brandGreenTop = NSColor(hex: 0x3DDC6A)
    private static let brandGreenBottom = NSColor(hex: 0x1FA84C)
    private static let innerRingTop = NSColor(hex: 0xFFFFFF)
    private static let innerRingBottom = NSColor(hex: 0xC9D7F2)

    private static func circlePath(center: NSPoint, radius: CGFloat) -> CGPath {
        CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                 width: radius * 2, height: radius * 2), transform: nil)
    }

    private static func drawDoubleRing(center: NSPoint, scale: CGFloat) {
        let outerRadius = ringRadius * scale
        let outerWidth = ringWidth * scale
        let outerPath = circlePath(center: center, radius: outerRadius)
        let outerBounds = NSRect(x: center.x - outerRadius - outerWidth,
                                 y: center.y - outerRadius - outerWidth,
                                 width: (outerRadius + outerWidth) * 2,
                                 height: (outerRadius + outerWidth) * 2)

        // 外环绿色柔光：让环从深色底上「浮」起来
        NSGraphicsContext.saveGraphicsState()
        if let cg = NSGraphicsContext.current?.cgContext {
            cg.addPath(outerPath)
            cg.setLineWidth(outerWidth)
            cg.setLineCap(.round)
            cg.replacePathWithStrokedPath()
            cg.setShadow(offset: CGSize(width: 0, height: -6 * scale), blur: 26 * scale,
                         color: brandGreenTop.withAlphaComponent(0.30).cgColor)
            cg.fillPath(using: .winding)
        }
        NSGraphicsContext.restoreGraphicsState()

        // 外环：上亮下暗的绿色渐变 + 内缘暗线 / 外缘高光
        fillStrokedPath(outerPath, lineWidth: outerWidth, in: outerBounds,
                        colors: [brandGreenBottom, brandGreenTop], angle: 90)
        fillStrokedPath(circlePath(center: center, radius: outerRadius - outerWidth / 2 + 2 * scale),
                        lineWidth: 4 * scale, in: outerBounds,
                        colors: [NSColor.black.withAlphaComponent(0.06),
                                 NSColor.black.withAlphaComponent(0.20)], angle: 90)
        fillStrokedPath(circlePath(center: center, radius: outerRadius + outerWidth / 2 - 2 * scale),
                        lineWidth: 4 * scale, in: outerBounds,
                        colors: [NSColor.white.withAlphaComponent(0.05),
                                 NSColor.white.withAlphaComponent(0.22)], angle: 90)
        fillStrokedPath(outerPath, lineWidth: outerWidth, in: outerBounds,
                        colors: [NSColor.white.withAlphaComponent(0),
                                 NSColor.white.withAlphaComponent(0),
                                 NSColor.white.withAlphaComponent(0.16)], angle: -90)

        // 内环：冷白、略细，带轻微投影
        let innerRadius = innerRingRadius * scale
        let innerWidth = innerRingWidth * scale
        let innerPath = circlePath(center: center, radius: innerRadius)
        let innerBounds = NSRect(x: center.x - innerRadius - innerWidth,
                                 y: center.y - innerRadius - innerWidth,
                                 width: (innerRadius + innerWidth) * 2,
                                 height: (innerRadius + innerWidth) * 2)
        NSGraphicsContext.saveGraphicsState()
        if let cg = NSGraphicsContext.current?.cgContext {
            cg.addPath(innerPath)
            cg.setLineWidth(innerWidth)
            cg.replacePathWithStrokedPath()
            cg.setShadow(offset: CGSize(width: 0, height: -4 * scale), blur: 14 * scale,
                         color: NSColor.black.withAlphaComponent(0.35).cgColor)
            cg.fillPath(using: .winding)
        }
        NSGraphicsContext.restoreGraphicsState()
        fillStrokedPath(innerPath, lineWidth: innerWidth, in: innerBounds,
                        colors: [innerRingBottom, innerRingTop], angle: 90)
        fillStrokedPath(circlePath(center: center, radius: innerRadius - innerWidth / 2 + 1.5 * scale),
                        lineWidth: 3 * scale, in: innerBounds,
                        colors: [NSColor.black.withAlphaComponent(0.14),
                                 NSColor.black.withAlphaComponent(0.04)], angle: 90)
    }

    // MARK: 绘制工具

    /// 超椭圆（Squircle）路径：|x/a|^5 + |y/b|^5 = 1 的参数化采样（≈ macOS 图标圆角）。
    private static func squircleCGPath(in rect: NSRect) -> CGPath {
        let a = rect.width / 2
        let b = rect.height / 2
        let path = CGMutablePath()
        let steps = 720
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = rect.midX + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / baseExponent)
            let y = rect.midY + b * (st < 0 ? -1 : 1) * pow(abs(st), 2 / baseExponent)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }

    /// 先用 `lineWidth` 描边 `path` 再裁切，然后在裁切区内画渐变——得到「带渐变的描边」。
    private static func fillStrokedPath(_ path: CGPath, lineWidth: CGFloat, in bounds: NSRect,
                                        colors: [NSColor], angle: CGFloat) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        NSGraphicsContext.saveGraphicsState()
        cg.addPath(path)
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.round)
        cg.replacePathWithStrokedPath()
        cg.clip()
        NSGradient(colors: colors)?.draw(in: bounds, angle: angle)
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - 颜色工具

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

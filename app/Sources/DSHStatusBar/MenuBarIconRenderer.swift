import AppKit
import CoreText

// MARK: - 菜单栏图标 v3：鲸鱼 + 分段圆环
//
//  · 空闲（没有任何非空闲任务）：纯白 DeepSeek 鲸鱼 Logo，无圆环
//  · 非空闲：圆环按任务数等分，每段一个任务，颜色 = 该任务状态
//      待回答=黄 / 运行中=蓝 / 已完成=绿 / 已停止=红
//    N=1 时是完整圆环；N=2 对半分；N=3 三等分……
//  · 圆环中心：待回答+已完成+已停止 的数量（即需要关注的数量）；
//    只有运行中时按需求不显示数字，只留蓝色分段环。
//  · 未连接：灰色虚线环 + 短横。

struct IconModel: Equatable {
    /// 非空闲任务（会话）状态，已按优先级排序、已按设置过滤。空数组 = 空闲。
    var statuses: [SessionStatus] = []
    var connected = true
    /// 0 = 不限；>0 时圆环最多画这么多段。
    var segmentCap: Int = 0
    var numberMode: CenterNumberMode = .attention

    var attention: Int { statuses.filter { $0 != .running }.count }
    var runningCount: Int { statuses.filter { $0 == .running }.count }
    var isEmpty: Bool { statuses.isEmpty }

    /// 圆环实际绘制的段（受上限约束）。
    var drawnSegments: [SessionStatus] {
        guard segmentCap > 0 else { return statuses }
        return Array(statuses.prefix(segmentCap))
    }

    /// 中心数字（nil = 不显示）。
    var centerNumber: Int? {
        switch numberMode {
        case .hidden:
            return nil
        case .attention:
            let value = attention
            return value > 0 ? value : nil
        case .nonIdle:
            return statuses.isEmpty ? nil : statuses.count
        }
    }
}

enum MenuBarIconRenderer {
    static let canvas: CGFloat = 22
    private static let center = NSPoint(x: 11, y: 11)
    private static let ringRadius: CGFloat = 8.05
    private static let ringWidth: CGFloat = 2.4

    // MARK: 对外入口

    static func image(for model: IconModel, appearance: NSAppearance) -> NSImage {
        render(width: canvas, height: canvas, appearance: appearance) { _ in
            draw(model: model, appearance: appearance)
        }
    }

    static func tooltip(for model: IconModel) -> String {
        guard model.connected else { return "DSH 未连接" }
        guard !model.isEmpty else { return "DSH：全部空闲" }
        var parts: [String] = []
        let waiting = model.statuses.filter { $0 == .waiting }.count
        let running = model.runningCount
        let completed = model.statuses.filter { $0 == .completed }.count
        let stopped = model.statuses.filter { $0 == .stopped }.count
        if waiting > 0 { parts.append("\(waiting) 待回答") }
        if running > 0 { parts.append("\(running) 运行中") }
        if completed > 0 { parts.append("\(completed) 已完成") }
        if stopped > 0 { parts.append("\(stopped) 已停止") }
        return "DSH：" + parts.joined(separator: " · ")
    }

    // MARK: 绘制

    private static func draw(model: IconModel, appearance: NSAppearance) {
        let dark = isDark(appearance)

        guard model.connected else {
            drawDisconnected(dark: dark)
            return
        }

        if model.isEmpty {
            drawWhale(dark: dark)
            return
        }

        drawSegmentRing(statuses: model.drawnSegments, dark: dark)

        if let number = model.centerNumber {
            drawCount(number, dark: dark)
        }
    }

    // MARK: 空闲：纯白鲸鱼

    private static func drawWhale(dark: Bool) {
        let logoRect = NSRect(
            x: center.x - 9.4,
            y: center.y - 9.4 * WhaleLogo.viewBoxHeight / WhaleLogo.viewBoxWidth,
            width: 18.8,
            height: 18.8 * WhaleLogo.viewBoxHeight / WhaleLogo.viewBoxWidth
        )
        let path = WhaleLogo.path(fitting: logoRect)
        // 深色菜单栏 = 纯白；浅色菜单栏自动用近黑，保证可见
        (dark ? NSColor.white : NSColor(hex: 0x1F1F23)).setFill()
        path.fill()
    }

    // MARK: 分段圆环

    private static func drawSegmentRing(statuses: [SessionStatus], dark: Bool) {
        let count = statuses.count
        guard count > 0 else { return }

        let colors = statuses.map { statusColor($0, dark: dark) }

        if count == 1 {
            colors[0].setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            ))
            ring.lineWidth = ringWidth
            ring.stroke()
            return
        }

        let step = 360.0 / CGFloat(count)
        // 圆头端点会「吃掉」一部分视觉间隔：按线宽换算成角度后，保证约 4°–8° 的可见缝隙
        let capAngle = (ringWidth / 2) / ringRadius * 180 / .pi
        let desired = max(capAngle * 2 + 8, min(30, step * 0.40))
        let gap = min(desired, step * 0.55)
        let sweep = step - gap

        for (index, color) in colors.enumerated() {
            let start = 90.0 - CGFloat(index) * step - gap / 2
            let end = start - sweep

            // 柔和外发光
            color.withAlphaComponent(dark ? 0.10 : 0.08).setStroke()
            let halo = NSBezierPath()
            halo.appendArc(withCenter: center, radius: ringRadius,
                           startAngle: start, endAngle: end, clockwise: true)
            halo.lineWidth = ringWidth + 0.8
            halo.lineCapStyle = .round
            halo.stroke()

            // 分段本体（圆头端点，更接近 macOS 的柔和风格）
            color.setStroke()
            let segment = NSBezierPath()
            segment.appendArc(withCenter: center, radius: ringRadius,
                              startAngle: start, endAngle: end, clockwise: true)
            segment.lineWidth = ringWidth
            segment.lineCapStyle = .round
            segment.stroke()
        }
    }

    // MARK: 中心数字

    private static func drawCount(_ count: Int, dark: Bool) {
        let text = count > 99 ? "99+" : "\(count)"
        let size: CGFloat
        switch text.count {
        case 1: size = 10.6
        case 2: size = 9.2
        default: size = 7.6
        }
        let font = roundedFont(size: size, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dark ? NSColor.white : NSColor(hex: 0x0F1115),
            .kern: 0.1
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        // 用字形墨迹（ink bounds）而不是行高来居中，避免数字因上下留白看起来偏上；
        // 水平方向用字形面积质心，修正「1」这类重心偏右的窄数字的视觉偏移。
        let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let centroidX = lineAreaCentroidX(line)
        guard let context = NSGraphicsContext.current?.cgContext else {
            let textSize = attributed.size()
            attributed.draw(at: NSPoint(
                x: center.x - textSize.width / 2,
                y: center.y - textSize.height / 2 + 0.3
            ))
            return
        }
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -0.3),
            blur: 1.0,
            color: (dark ? NSColor.black.withAlphaComponent(0.30)
                         : NSColor.black.withAlphaComponent(0.16)).cgColor
        )
        context.textPosition = CGPoint(
            x: center.x - (centroidX ?? ink.midX),
            y: center.y - ink.midY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    // MARK: 未连接

    private static func drawDisconnected(dark: Bool) {
        let color = NSColor.labelColor.withAlphaComponent(dark ? 0.36 : 0.30)
        color.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - ringRadius,
            y: center.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))
        ring.lineWidth = 1.6
        ring.lineCapStyle = .round
        ring.setLineDash([2.0, 3.0], count: 2, phase: 0)
        ring.stroke()

        color.setFill()
        let minus = NSRect(x: center.x - 3.0, y: center.y - 0.7, width: 6.0, height: 1.4)
        NSBezierPath(roundedRect: minus, xRadius: 0.7, yRadius: 0.7).fill()
    }

    // MARK: 状态色

    private static func statusColor(_ status: SessionStatus, dark: Bool) -> NSColor {
        Theme.statusNSColor(status, dark: dark)
    }

    // MARK: 工具

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

// MARK: - App 图标 / 弹窗图标（菜单栏同款鲸鱼，无底色）

enum AppIconRenderer {
    /// App 图标的鲸鱼主色（#6485FC）。
    static let brandColor = NSColor(hex: 0x6485FC)

    /// 透明底 + 品牌蓝鲸鱼（轻微投影，深浅背景都可见）。
    /// 与菜单栏空闲态同一 glyph，不放圆角方块，避免和 DeepSeek Harness 官方图标混淆。
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let whaleWidth = size * 0.80
            let whaleHeight = whaleWidth * WhaleLogo.viewBoxHeight / WhaleLogo.viewBoxWidth
            let whaleRect = NSRect(
                x: (size - whaleWidth) / 2,
                y: (size - whaleHeight) / 2,
                width: whaleWidth,
                height: whaleHeight
            )
            let path = WhaleLogo.path(fitting: whaleRect)

            // 轻微投影：浅色背景上也能看清轮廓；不添加任何底色/描边
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
            shadow.shadowBlurRadius = size * 0.030
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.008)
            shadow.set()

            brandColor.setFill()
            path.fill()
            return true
        }
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

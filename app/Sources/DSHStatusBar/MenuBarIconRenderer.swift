import AppKit

// MARK: - 菜单栏图标 v3：鲸鱼 + 分段圆环
//
//  · 空闲（没有任何非空闲任务）：纯白 DeepSeek 鲸鱼 Logo，无圆环
//  · 非空闲：圆环按任务数等分，每段一个任务，颜色 = 该任务状态
//      待回答=红 / 运行中=蓝 / 已完成=绿 / 已停止=橙
//    N=1 时是完整圆环；N=2 对半分；N=3 三等分……
//  · 圆环中心：待回答+已完成+已停止 的数量（即需要关注的数量）；
//    只有运行中时按需求不显示数字，只留蓝色分段环。
//  · 未连接：灰色虚线环 + 短横。

struct IconModel: Equatable {
    /// 非空闲任务（会话）状态，已按优先级排序。空数组 = 空闲。
    var statuses: [SessionStatus] = []
    var connected = true

    var attention: Int { statuses.filter { $0 != .running }.count }
    var runningCount: Int { statuses.filter { $0 == .running }.count }
    var isEmpty: Bool { statuses.isEmpty }
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

        drawSegmentRing(model: model, dark: dark)

        if model.attention > 0 {
            drawCount(model.attention, dark: dark)
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
        (dark ? NSColor.white : NSColor(hex: 0x0F1115)).setFill()
        path.fill()
    }

    // MARK: 分段圆环

    private static func drawSegmentRing(model: IconModel, dark: Bool) {
        let statuses = model.statuses
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
        let gap = min(9.0, step * 0.22)
        let sweep = step - gap

        for (index, color) in colors.enumerated() {
            let start = 90.0 - CGFloat(index) * step - gap / 2
            let end = start - sweep

            // 外发光（让深色菜单栏上更有层次）
            color.withAlphaComponent(dark ? 0.13 : 0.10).setStroke()
            let halo = NSBezierPath()
            halo.appendArc(withCenter: center, radius: ringRadius,
                           startAngle: start, endAngle: end, clockwise: true)
            halo.lineWidth = ringWidth + 1.2
            halo.stroke()

            // 分段本体
            color.setStroke()
            let segment = NSBezierPath()
            segment.appendArc(withCenter: center, radius: ringRadius,
                              startAngle: start, endAngle: end, clockwise: true)
            segment.lineWidth = ringWidth
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
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.45 : 0.20)
        shadow.shadowBlurRadius = 1.2
        shadow.shadowOffset = NSSize(width: 0, height: -0.4)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: dark ? NSColor.white : NSColor(hex: 0x0F1115),
            .shadow: shadow,
            .kern: 0.1
        ]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let textSize = attributed.size()
        attributed.draw(at: NSPoint(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2 + 0.3
        ))
    }

    // MARK: 未连接

    private static func drawDisconnected(dark: Bool) {
        let color = NSColor.labelColor.withAlphaComponent(dark ? 0.42 : 0.34)
        color.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - ringRadius,
            y: center.y - ringRadius,
            width: ringRadius * 2,
            height: ringRadius * 2
        ))
        ring.lineWidth = 1.6
        ring.setLineDash([2.2, 2.2], count: 2, phase: 0)
        ring.stroke()

        color.setFill()
        let minus = NSRect(x: center.x - 3.0, y: center.y - 0.7, width: 6.0, height: 1.4)
        NSBezierPath(roundedRect: minus, xRadius: 0.7, yRadius: 0.7).fill()
    }

    // MARK: 状态色

    private static func statusColor(_ status: SessionStatus, dark: Bool) -> NSColor {
        switch status {
        case .waiting:
            return NSColor(hex: dark ? 0xFF5A50 : 0xE01B24)
        case .running:
            return NSColor(hex: dark ? 0x4DA3FF : 0x007AFF)
        case .completed:
            return NSColor(hex: dark ? 0x3DDC6A : 0x28B24B)
        case .stopped:
            return NSColor(hex: dark ? 0xFFB340 : 0xE07800)
        case .idle:
            return NSColor.labelColor.withAlphaComponent(0.3)
        }
    }

    // MARK: 工具

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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

// MARK: - 颜色工具

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

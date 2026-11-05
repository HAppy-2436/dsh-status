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
        // 圆头端点会「吃掉」一部分视觉间隔：按线宽换算成角度后，保证至少 ~5° 的可见缝隙
        let capAngle = (ringWidth / 2) / ringRadius * 180 / .pi
        let desired = max(capAngle * 2 + 5, min(40, step * 0.45))
        let gap = min(desired, step * 0.65)
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
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.30 : 0.16)
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

// MARK: - App 弹窗/关于页用的品牌图标

enum AppIconRenderer {
    /// 深色圆角方底 + 白色鲸鱼，用于 NSAlert 等系统弹窗。
    static func image(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = size * 0.06
            let background = NSRect(x: rect.minX + inset, y: rect.minY + inset,
                                    width: rect.width - inset * 2, height: rect.height - inset * 2)
            let path = NSBezierPath(roundedRect: background,
                                    xRadius: size * 0.23, yRadius: size * 0.23)
            NSColor(hex: 0x1C1C1E).setFill()
            path.fill()
            // 细描边提升质感
            NSColor.white.withAlphaComponent(0.08).setStroke()
            path.lineWidth = max(1, size * 0.012)
            path.stroke()

            let whaleWidth = size * 0.64
            let whaleRect = NSRect(
                x: (size - whaleWidth) / 2,
                y: (size - whaleWidth * WhaleLogo.viewBoxHeight / WhaleLogo.viewBoxWidth) / 2,
                width: whaleWidth,
                height: whaleWidth * WhaleLogo.viewBoxHeight / WhaleLogo.viewBoxWidth
            )
            NSColor.white.setFill()
            WhaleLogo.path(fitting: whaleRect).fill()
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

import AppKit

// MARK: - 菜单栏图标：单圆形徽标（v2）
//
// 所有信息收进一个 22×22 的圆形里，不再横向拼接多个元素：
//   · 圆盘填充 = 需要关注的数量（待回答/已完成/已停止），颜色表示最紧急的原因
//   · 圆盘中央数字 = 关注总数；无关注时中央显示状态图形
//   · 外圈蓝色弧 = 有会话正在运行（不计入数字）
//   · 细环 / 虚线环 = 空闲 / 未连接
//
// 深色模式优先调色：渐变填充 + 顶部高光 + 细描边，避免「贴纸感」。

enum IconVariant: String, CaseIterable {
    case disc
    case ring

    var label: String {
        switch self {
        case .disc: return "圆盘（推荐）"
        case .ring: return "圆环"
        }
    }
}

struct IconModel: Equatable {
    var waiting = 0
    var running = 0
    var completed = 0
    var stopped = 0
    var connected = true

    var attention: Int { waiting + completed + stopped }
    var isQuiet: Bool { attention == 0 && running == 0 }

    static let idle = IconModel()

    static func demo(state: BridgeState) -> IconModel {
        IconModel(
            waiting: state.counts.waiting,
            running: state.counts.running,
            completed: state.counts.completed,
            stopped: state.counts.stopped,
            connected: true
        )
    }
}

enum MenuBarIconRenderer {
    /// 画布 22×22，圆形直径 17.5，菜单栏里保持紧凑的方形占位。
    static let canvas: CGFloat = 22
    private static let discRadius: CGFloat = 8.75
    private static let arcRadius: CGFloat = 9.7

    // MARK: 对外入口

    static func image(for model: IconModel,
                      variant: IconVariant = .disc,
                      appearance: NSAppearance) -> NSImage {
        render(width: canvas, height: canvas, appearance: appearance) { _ in
            draw(model: model, variant: variant, appearance: appearance)
        }
    }

    static func tooltip(for model: IconModel) -> String {
        guard model.connected else { return "DSH 未连接" }
        var parts: [String] = []
        if model.waiting > 0 { parts.append("\(model.waiting) 待回答") }
        if model.running > 0 { parts.append("\(model.running) 运行中") }
        if model.completed > 0 { parts.append("\(model.completed) 已完成") }
        if model.stopped > 0 { parts.append("\(model.stopped) 已停止") }
        return parts.isEmpty ? "DSH：全部空闲" : "DSH：" + parts.joined(separator: " · ")
    }

    // MARK: 绘制

    private static func draw(model: IconModel, variant: IconVariant, appearance: NSAppearance) {
        let center = NSPoint(x: canvas / 2, y: canvas / 2)
        let dark = isDark(appearance)
        let palette = Palette.forModel(model, dark: dark)

        if !model.connected {
            drawDisconnected(center: center, dark: dark)
            return
        }

        switch variant {
        case .disc:
            drawDisc(model: model, center: center, palette: palette, dark: dark)
        case .ring:
            drawRing(model: model, center: center, palette: palette, dark: dark)
        }
    }

    // MARK: 圆盘变体

    private static func drawDisc(model: IconModel, center: NSPoint, palette: Palette, dark: Bool) {
        let discRect = NSRect(
            x: center.x - discRadius,
            y: center.y - discRadius,
            width: discRadius * 2,
            height: discRadius * 2
        )

        if model.attention > 0 {
            // 外圈柔光，让圆盘在深色菜单栏里有层次
            palette.glow.withAlphaComponent(dark ? 0.42 : 0.18).setStroke()
            let glow = NSBezierPath(ovalIn: discRect.insetBy(dx: -1.1, dy: -1.1))
            glow.lineWidth = 1.4
            glow.stroke()

            // 渐变填充 + 顶部高光
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(ovalIn: discRect).addClip()
            NSGradient(starting: palette.fillStart, ending: palette.fillEnd)?
                .draw(in: discRect, angle: -90)
            let highlight = NSBezierPath(ovalIn: NSRect(
                x: discRect.minX + 1.4,
                y: discRect.midY + 0.8,
                width: discRect.width - 2.8,
                height: discRect.height * 0.44
            ))
            NSColor.white.withAlphaComponent(dark ? 0.11 : 0.16).setFill()
            highlight.fill()
            NSGraphicsContext.restoreGraphicsState()

            // 细描边
            if dark {
                NSColor.white.withAlphaComponent(0.20).setStroke()
            } else {
                palette.fillEnd.withAlphaComponent(0.55).setStroke()
            }
            let rim = NSBezierPath(ovalIn: discRect.insetBy(dx: 0.35, dy: 0.35))
            rim.lineWidth = 0.7
            rim.stroke()

            drawNumber(model.attention, center: center, dark: dark)
        } else if model.running > 0 {
            drawRunningOnly(center: center, palette: palette, dark: dark, fillCenter: false)
        } else {
            drawIdle(center: center, dark: dark)
        }

        if model.running > 0 && model.attention > 0 {
            drawRunningArc(center: center, palette: palette, dark: dark)
        }
    }

    // MARK: 圆环变体

    private static func drawRing(model: IconModel, center: NSPoint, palette: Palette, dark: Bool) {
        let radius = discRadius - 0.5
        let rect = NSRect(x: center.x - radius, y: center.y - radius,
                          width: radius * 2, height: radius * 2)

        if model.attention > 0 {
            palette.glow.withAlphaComponent(dark ? 0.36 : 0.22).setStroke()
            let base = NSBezierPath(ovalIn: rect)
            base.lineWidth = 1.6
            base.stroke()

            palette.ring.setStroke()
            let bright = NSBezierPath()
            bright.appendArc(withCenter: center, radius: radius,
                             startAngle: 105, endAngle: 345, clockwise: false)
            bright.lineWidth = 2.1
            bright.lineCapStyle = .round
            bright.stroke()

            drawNumber(model.attention, center: center, dark: dark, useLabelColor: true)
        } else if model.running > 0 {
            drawRunningOnly(center: center, palette: palette, dark: dark, fillCenter: false, ringInset: 0.5)
        } else {
            drawIdle(center: center, dark: dark)
        }

        if model.running > 0 && model.attention > 0 {
            drawRunningArc(center: center, palette: palette, radiusOffset: 0.9, dark: dark)
        }
    }

    // MARK: 数字

    private static func drawNumber(_ count: Int, center: NSPoint, dark: Bool, useLabelColor: Bool = false) {
        let text = count > 99 ? "99+" : "\(count)"
        let size: CGFloat
        switch text.count {
        case 1: size = 10.6
        case 2: size = 9.4
        default: size = 7.9
        }
        let font = roundedFont(size: size, weight: .bold)
        let color: NSColor = useLabelColor ? .labelColor : .white
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.38 : 0.18)
        shadow.shadowBlurRadius = 1.2
        shadow.shadowOffset = NSSize(width: 0, height: -0.4)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
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

    // MARK: 运行中

    private static func drawRunningOnly(center: NSPoint, palette: Palette, dark: Bool,
                                        fillCenter: Bool, ringInset: CGFloat = 0) {
        let radius = discRadius - ringInset
        // 底环
        palette.glow.withAlphaComponent(dark ? 0.32 : 0.22).setStroke()
        let full = NSBezierPath(ovalIn: NSRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        full.lineWidth = 1.6
        full.stroke()

        // 中央等化器
        drawEqualizer(center: center, color: palette.ring)
        // 运行弧
        drawRunningArc(center: center, palette: palette, dark: dark)
    }

    private static func drawRunningArc(center: NSPoint, palette: Palette,
                                       radiusOffset: CGFloat = 0, dark: Bool = true) {
        let radius = arcRadius + radiusOffset
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: radius,
                      startAngle: -62, endAngle: 28, clockwise: false)
        arc.lineWidth = 1.7
        arc.lineCapStyle = .round
        // 运行中始终用蓝色，与关注状态的颜色互不干扰
        Palette.running(dark: dark).ring.setStroke()
        arc.stroke()
    }

    private static func drawEqualizer(center: NSPoint, color: NSColor) {
        color.setFill()
        let heights: [CGFloat] = [3.8, 6.6, 4.8]
        let barWidth: CGFloat = 1.6
        let gap: CGFloat = 1.5
        let totalWidth = barWidth * 3 + gap * 2
        var x = center.x - totalWidth / 2
        for height in heights {
            let rect = NSRect(x: x, y: center.y - height / 2, width: barWidth, height: height)
            NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
            x += barWidth + gap
        }
    }

    private static func drawIdle(center: NSPoint, dark: Bool) {
        let alpha: CGFloat = dark ? 0.34 : 0.30
        NSColor.labelColor.withAlphaComponent(alpha).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - discRadius,
            y: center.y - discRadius,
            width: discRadius * 2,
            height: discRadius * 2
        ))
        ring.lineWidth = 1.2
        ring.stroke()

        if let symbol = tintedSymbol(name: "fish", pointSize: 9, weight: .medium,
                                     color: NSColor.labelColor.withAlphaComponent(dark ? 0.52 : 0.40)) {
            let size = symbol.size
            symbol.draw(in: NSRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2 + 0.4,
                width: size.width,
                height: size.height
            ))
        }
    }

    private static func drawDisconnected(center: NSPoint, dark: Bool) {
        let color = NSColor.labelColor.withAlphaComponent(dark ? 0.30 : 0.26)
        color.setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(
            x: center.x - discRadius,
            y: center.y - discRadius,
            width: discRadius * 2,
            height: discRadius * 2
        ))
        ring.lineWidth = 1.2
        ring.setLineDash([2.0, 2.4], count: 2, phase: 0)
        ring.stroke()

        color.setFill()
        let minus = NSRect(x: center.x - 3.0, y: center.y - 0.6, width: 6.0, height: 1.2)
        NSBezierPath(roundedRect: minus, xRadius: 0.6, yRadius: 0.6).fill()
    }

    // MARK: 调色板

    struct Palette {
        let fillStart: NSColor
        let fillEnd: NSColor
        let ring: NSColor
        let glow: NSColor

        static func forModel(_ model: IconModel, dark: Bool) -> Palette {
            if model.waiting > 0 { return .waiting(dark: dark) }
            if model.stopped > 0 { return .stopped(dark: dark) }
            if model.completed > 0 { return .completed(dark: dark) }
            if model.running > 0 { return .running(dark: dark) }
            return .neutral(dark: dark)
        }

        static func waiting(dark: Bool) -> Palette {
            dark
                ? Palette(fillStart: NSColor(hex: 0xFF6A5E), fillEnd: NSColor(hex: 0xC81A12),
                          ring: NSColor(hex: 0xFF7B72), glow: NSColor(hex: 0xFF453A))
                : Palette(fillStart: NSColor(hex: 0xFF5248), fillEnd: NSColor(hex: 0xC4001A),
                          ring: NSColor(hex: 0xE01B24), glow: NSColor(hex: 0xFF3B30))
        }

        static func stopped(dark: Bool) -> Palette {
            dark
                ? Palette(fillStart: NSColor(hex: 0xFFBE52), fillEnd: NSColor(hex: 0xC25C00),
                          ring: NSColor(hex: 0xFFC46B), glow: NSColor(hex: 0xFF9F0A))
                : Palette(fillStart: NSColor(hex: 0xFFA51F), fillEnd: NSColor(hex: 0xB25000),
                          ring: NSColor(hex: 0xE07800), glow: NSColor(hex: 0xFF9500))
        }

        static func completed(dark: Bool) -> Palette {
            dark
                ? Palette(fillStart: NSColor(hex: 0x45E07A), fillEnd: NSColor(hex: 0x12813D),
                          ring: NSColor(hex: 0x5CEB8C), glow: NSColor(hex: 0x30D158))
                : Palette(fillStart: NSColor(hex: 0x34C759), fillEnd: NSColor(hex: 0x0B7A2C),
                          ring: NSColor(hex: 0x1E9E43), glow: NSColor(hex: 0x28B24B))
        }

        static func running(dark: Bool) -> Palette {
            dark
                ? Palette(fillStart: NSColor(hex: 0x6FB8FF), fillEnd: NSColor(hex: 0x0A5AC2),
                          ring: NSColor(hex: 0x4DA3FF), glow: NSColor(hex: 0x0A84FF))
                : Palette(fillStart: NSColor(hex: 0x3E9BFF), fillEnd: NSColor(hex: 0x0057C2),
                          ring: NSColor(hex: 0x007AFF), glow: NSColor(hex: 0x2E8BFF))
        }

        static func neutral(dark: Bool) -> Palette {
            Palette(fillStart: NSColor.labelColor, fillEnd: NSColor.labelColor,
                    ring: NSColor.labelColor, glow: NSColor.labelColor)
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

    private static func tintedSymbol(name: String, pointSize: CGFloat, weight: NSFont.Weight,
                                     color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return nil }
        let size = symbol.size
        let tinted = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.isTemplate = false
        return tinted
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

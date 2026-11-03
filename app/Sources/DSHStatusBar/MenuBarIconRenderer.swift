import AppKit

// MARK: - 菜单栏图标绘制（docs/app-design.md §2）

enum IconStyle: String, CaseIterable {
    case fish
    case stack
    case nodes

    var label: String {
        switch self {
        case .fish: return "A · fish（推荐）"
        case .stack: return "B · sessions stack"
        case .nodes: return "C · harness nodes"
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
    static let height: CGFloat = 18
    private static let glyphSize: CGFloat = 16
    private static let leftPad: CGFloat = 1
    private static let rightPad: CGFloat = 1
    private static let gap: CGFloat = 3

    // MARK: 对外入口

    static func image(for model: IconModel, style: IconStyle, appearance: NSAppearance) -> NSImage {
        let layout = Layout(model: model)
        return render(width: layout.totalWidth, height: height, appearance: appearance) { _ in
            draw(model: model, style: style, layout: layout)
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

    // MARK: 布局

    private struct Layout {
        let model: IconModel
        let badgeText: String?
        let badgeWidth: CGFloat
        let badgeHeight: CGFloat = 13.5
        let runningBarsWidth: CGFloat
        let showsRunningBars: Bool

        init(model: IconModel) {
            self.model = model
            let count = model.attention
            if model.connected && count > 0 {
                badgeText = count > 99 ? "99+" : "\(count)"
            } else {
                badgeText = nil
            }
            if let text = badgeText {
                let font = Fonts.badge
                let attr = NSAttributedString(string: text, attributes: [.font: font])
                badgeWidth = max(15.5, ceil(attr.size().width) + 9)
            } else {
                badgeWidth = 0
            }
            showsRunningBars = model.connected && model.running > 0
            runningBarsWidth = showsRunningBars ? 7.3 : 0
        }

        var totalWidth: CGFloat {
            var w = MenuBarIconRenderer.leftPad + MenuBarIconRenderer.glyphSize
            if showsRunningBars { w += 2 + runningBarsWidth }
            if badgeText != nil { w += MenuBarIconRenderer.gap + badgeWidth }
            return ceil(w + MenuBarIconRenderer.rightPad)
        }
    }

    // MARK: 绘制

    private static func draw(model: IconModel, style: IconStyle, layout: Layout) {
        let glyphRect = NSRect(
            x: leftPad,
            y: (height - glyphSize) / 2,
            width: glyphSize,
            height: glyphSize
        )
        let glyphColor = NSColor.labelColor.withAlphaComponent(model.connected ? 1.0 : 0.35)
        drawGlyph(style: style, in: glyphRect, color: glyphColor)

        var cursorX = glyphRect.maxX

        if layout.showsRunningBars {
            cursorX += 2
            drawRunningBars(x: cursorX, centerY: height / 2, color: NSColor.systemBlue)
            cursorX += layout.runningBarsWidth
        }

        if let text = layout.badgeText {
            cursorX += gap
            drawBadge(
                text: text,
                x: cursorX,
                size: NSSize(width: layout.badgeWidth, height: layout.badgeHeight),
                fill: badgeColor(model)
            )
        }
    }

    private static func badgeColor(_ model: IconModel) -> NSColor {
        if model.waiting > 0 { return NSColor.systemRed }
        if model.stopped > 0 { return NSColor.systemOrange }
        if model.completed > 0 { return NSColor.systemGreen }
        return NSColor.secondaryLabelColor
    }

    private static func drawRunningBars(x: CGFloat, centerY: CGFloat, color: NSColor) {
        color.setFill()
        let heights: [CGFloat] = [4.0, 7.0, 5.0]
        for (index, height) in heights.enumerated() {
            let barX = x + CGFloat(index) * 2.9
            let rect = NSRect(x: barX, y: centerY - height / 2, width: 1.5, height: height)
            NSBezierPath(roundedRect: rect, xRadius: 0.75, yRadius: 0.75).fill()
        }
    }

    private static func drawBadge(text: String, x: CGFloat, size: NSSize, fill: NSColor) {
        let rect = NSRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height)
        fill.setFill()
        NSBezierPath(roundedRect: rect, xRadius: size.height / 2, yRadius: size.height / 2).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: Fonts.badge,
            .foregroundColor: NSColor.white
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let textSize = attr.size()
        attr.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2))
    }

    // MARK: 三种基础图形

    private static func drawGlyph(style: IconStyle, in rect: NSRect, color: NSColor) {
        switch style {
        case .fish: drawFish(in: rect, color: color)
        case .stack: drawStack(in: rect, color: color)
        case .nodes: drawNodes(in: rect, color: color)
        }
    }

    private static func drawFish(in rect: NSRect, color: NSColor) {
        guard let symbol = tintedSymbol(name: "fish.fill", pointSize: 15, weight: .medium, color: color) else {
            return
        }
        let s = symbol.size
        let scale = min(rect.width / s.width, rect.height / s.height)
        let drawSize = NSSize(width: s.width * scale, height: s.height * scale)
        let drawRect = NSRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        symbol.draw(in: drawRect)
    }

    private static func drawStack(in rect: NSRect, color: NSColor) {
        color.setFill()
        let barHeight: CGFloat = 2.4
        let spacing: CGFloat = 2.2
        let widths: [CGFloat] = [13, 10, 7]
        let top = rect.maxY - 2.2
        for (index, width) in widths.enumerated() {
            let y = top - barHeight - CGFloat(index) * (barHeight + spacing)
            let barRect = NSRect(x: rect.minX + 1, y: y, width: width, height: barHeight)
            NSBezierPath(roundedRect: barRect, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
        }
    }

    private static func drawNodes(in rect: NSRect, color: NSColor) {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let top = NSPoint(x: center.x, y: center.y + 4.6)
        let left = NSPoint(x: center.x - 4.0, y: center.y - 3.8)
        let right = NSPoint(x: center.x + 4.0, y: center.y - 3.8)

        let lineColor = color.withAlphaComponent(0.55)
        lineColor.setStroke()
        for (a, b) in [(top, left), (top, right), (left, right)] {
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            path.move(to: a)
            path.line(to: b)
            path.stroke()
        }
        color.setFill()
        for point in [top, left, right] {
            let dot = NSRect(x: point.x - 1.6, y: point.y - 1.6, width: 3.2, height: 3.2)
            NSBezierPath(ovalIn: dot).fill()
        }
    }

    // MARK: 工具

    private enum Fonts {
        static let badge: NSFont = {
            let base = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
            if let descriptor = base.fontDescriptor.withDesign(.rounded),
               let font = NSFont(descriptor: descriptor, size: 10.5) {
                return font
            }
            return base
        }()
    }

    private static func tintedSymbol(name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
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

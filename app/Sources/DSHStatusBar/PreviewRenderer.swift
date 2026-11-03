import AppKit
import SwiftUI

/// `--render-previews`：离屏渲染图标矩阵与面板预览图。
enum PreviewRenderer {
    static func renderAll(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let light = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        let dark = NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()

        // 深色优先：主预览先出深色
        try renderIconSheet(
            appearance: dark,
            dark: true,
            pageBackground: NSColor(hex: 0x0E0E10),
            menuBarBackground: NSColor(hex: 0x1C1C1E),
            title: "DSH 菜单栏图标 · 深色（主用）",
            to: directory.appendingPathComponent("icon-preview-dark.png")
        )
        try renderIconSheet(
            appearance: light,
            dark: false,
            pageBackground: NSColor(hex: 0xF6F6F8),
            menuBarBackground: NSColor(hex: 0xECECEF),
            title: "DSH 菜单栏图标 · 浅色",
            to: directory.appendingPathComponent("icon-preview-light.png")
        )
        try renderPanelSheet(
            appearance: dark,
            colorScheme: .dark,
            pageBackground: NSColor(hex: 0x0E0E10),
            title: "DSH 面板 · 深色（主用）",
            to: directory.appendingPathComponent("panel-preview-dark.png")
        )
        try renderPanelSheet(
            appearance: light,
            colorScheme: .light,
            pageBackground: NSColor(hex: 0xF6F6F8),
            title: "DSH 面板 · 浅色",
            to: directory.appendingPathComponent("panel-preview-light.png")
        )
        try renderScene(appearance: dark, colorScheme: .dark,
                        to: directory.appendingPathComponent("scene-preview-dark.png"))
    }

    // MARK: - 场景示意（模拟菜单栏 + 打开的面板）

    private static func renderScene(appearance: NSAppearance,
                                    colorScheme: ColorScheme,
                                    to url: URL) throws {
        let width: CGFloat = 1100
        let height: CGFloat = 720
        let menuBarHeight: CGFloat = 26
        let panelWidth: CGFloat = 344

        let demo = AppModel.demo()
        let panelImage = renderPanel(model: demo, width: panelWidth,
                                     appearance: appearance, colorScheme: colorScheme)
        let icon = MenuBarIconRenderer.image(for: IconModel.demo(state: DemoState.state),
                                             variant: .disc, appearance: appearance)
        let iconX: CGFloat = width - 196
        let iconRect = NSRect(x: iconX,
                              y: height - menuBarHeight + (menuBarHeight - icon.size.height) / 2,
                              width: icon.size.width, height: icon.size.height)
        let panelX = iconX + icon.size.width / 2 - panelWidth + 60
        let panelY = height - menuBarHeight - 10 - panelImage.size.height

        try savePNG(width: width, height: height, appearance: appearance, to: url) { rect in
            // 深色壁纸渐变
            NSGradient(starting: NSColor(hex: 0x0B1020), ending: NSColor(hex: 0x123B4A))?
                .draw(in: rect, angle: -70)
            NSGradient(colors: [
                NSColor(hex: 0x2A1E5C, alpha: 0.85),
                NSColor(hex: 0x0E2F44, alpha: 0.0),
            ])?.draw(in: NSRect(x: 0, y: 0, width: width, height: height * 0.8), angle: -20)

            // 菜单栏
            NSColor.black.withAlphaComponent(0.30).setFill()
            NSRect(x: 0, y: height - menuBarHeight, width: width, height: menuBarHeight).fill()
            NSColor.white.withAlphaComponent(0.06).setFill()
            NSRect(x: 0, y: height - menuBarHeight, width: width, height: 0.6).fill()

            // 右侧系统项（示意）
            let menuTop = height - menuBarHeight
            var x = width - 92
            drawText("23:32", font: .systemFont(ofSize: 12, weight: .medium),
                     color: NSColor.white.withAlphaComponent(0.92),
                     at: NSPoint(x: x, y: menuTop + 7))
            x -= 42
            drawSymbol("battery.100", size: 15, color: NSColor.white.withAlphaComponent(0.88),
                       center: NSPoint(x: x, y: menuTop + menuBarHeight / 2))
            x -= 30
            drawSymbol("wifi", size: 14, color: NSColor.white.withAlphaComponent(0.88),
                       center: NSPoint(x: x, y: menuTop + menuBarHeight / 2))

            // 我们的图标
            icon.draw(in: iconRect)

            // 打开的面板
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowBlurRadius = 26
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            NSGraphicsContext.saveGraphicsState()
            shadow.set()
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: panelX, y: panelY,
                                             width: panelWidth, height: panelImage.size.height),
                         xRadius: 12, yRadius: 12).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: NSRect(x: panelX, y: panelY,
                                             width: panelWidth, height: panelImage.size.height),
                         xRadius: 12, yRadius: 12).addClip()
            panelImage.draw(in: NSRect(x: panelX, y: panelY,
                                       width: panelWidth, height: panelImage.size.height))
            NSGraphicsContext.restoreGraphicsState()

            // 描边 + 指向图标的小三角
            NSColor.white.withAlphaComponent(0.10).setStroke()
            let border = NSBezierPath(roundedRect: NSRect(x: panelX + 0.5, y: panelY + 0.5,
                                                          width: panelWidth - 1, height: panelImage.size.height - 1),
                                      xRadius: 12, yRadius: 12)
            border.lineWidth = 1
            border.stroke()

            let arrowX = iconX + icon.size.width / 2
            let panelTop = panelY + panelImage.size.height
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: arrowX - 7, y: panelTop - 1))
            arrow.line(to: NSPoint(x: arrowX, y: panelTop + 7))
            arrow.line(to: NSPoint(x: arrowX + 7, y: panelTop - 1))
            arrow.close()
            NSColor.windowBackgroundColor.setFill()
            arrow.fill()

            drawText("示意图 · 离屏渲染（与真实菜单栏同一套绘制代码）",
                     font: .systemFont(ofSize: 11),
                     color: NSColor.white.withAlphaComponent(0.38),
                     at: NSPoint(x: 30, y: 22))
        }
    }

    private static func drawSymbol(_ name: String, size: CGFloat, color: NSColor, center: NSPoint) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: center.x - symbol.size.width / 2,
                               y: center.y - symbol.size.height / 2,
                               width: symbol.size.width, height: symbol.size.height))
    }

    // MARK: - 圆形图标矩阵

    private static let states: [(String, String, IconModel)] = [
        ("空闲", "无关注 · 无运行", IconModel()),
        ("运行中", "2 个会话运行", IconModel(running: 2)),
        ("已完成", "1 个未读", IconModel(completed: 1)),
        ("已停止", "1 个未读", IconModel(stopped: 1)),
        ("待回答", "1 个问题", IconModel(waiting: 1)),
        ("混合", "3 关注 + 2 运行", IconModel(waiting: 1, running: 2, completed: 1, stopped: 1)),
        ("未连接", "DSH 未运行", IconModel(connected: false)),
    ]

    private static func renderIconSheet(appearance: NSAppearance,
                                        dark: Bool,
                                        pageBackground: NSColor,
                                        menuBarBackground: NSColor,
                                        title: String,
                                        to url: URL) throws {
        let margin: CGFloat = 30
        let labelWidth: CGFloat = 118
        let colWidth: CGFloat = 250
        let rowHeight: CGFloat = 76
        let titleHeight: CGFloat = 64
        let headerHeight: CGFloat = 36
        let stripHeight: CGFloat = 106
        let width = margin * 2 + labelWidth + colWidth * 2
        let height = titleHeight + headerHeight + rowHeight * CGFloat(states.count) + stripHeight + margin
        let secondary = NSColor.labelColor.withAlphaComponent(0.55)

        try savePNG(width: width, height: height, appearance: appearance, to: url) { rect in
            pageBackground.setFill()
            rect.fill()

            drawText(title, font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor,
                     at: NSPoint(x: margin, y: height - margin - 18))
            drawText("单个圆形承载：关注数（数字）× 原因（颜色）× 运行中（外圈蓝弧）",
                     font: .systemFont(ofSize: 11), color: secondary,
                     at: NSPoint(x: margin, y: height - margin - 36))

            // 列标题
            let headerY = height - titleHeight - 18
            for (index, variant) in IconVariant.allCases.enumerated() {
                let x = margin + labelWidth + CGFloat(index) * colWidth
                drawText(variant.label, font: .systemFont(ofSize: 12, weight: .medium),
                         color: secondary, at: NSPoint(x: x, y: headerY))
            }

            // 状态行
            for (rowIndex, state) in states.enumerated() {
                let y = height - titleHeight - headerHeight - CGFloat(rowIndex + 1) * rowHeight
                if rowIndex % 2 == 0 {
                    NSColor.labelColor.withAlphaComponent(dark ? 0.045 : 0.035).setFill()
                    NSRect(x: margin - 10, y: y, width: width - margin * 2 + 20, height: rowHeight).fill()
                }
                drawText(state.0, font: .systemFont(ofSize: 12.5, weight: .medium),
                         color: .labelColor, at: NSPoint(x: margin, y: y + 34))
                drawText(state.1, font: .systemFont(ofSize: 10.5),
                         color: secondary, at: NSPoint(x: margin, y: y + 18))

                for (index, variant) in IconVariant.allCases.enumerated() {
                    let x = margin + labelWidth + CGFloat(index) * colWidth
                    let icon = MenuBarIconRenderer.image(for: state.2, variant: variant, appearance: appearance)
                    let scale: CGFloat = 3.0
                    let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
                    icon.draw(in: NSRect(x: x, y: y + (rowHeight - size.height) / 2,
                                         width: size.width, height: size.height))
                }
            }

            // 真实尺寸（模拟菜单栏）
            let stripY = margin
            menuBarBackground.setFill()
            NSBezierPath(roundedRect: NSRect(x: margin, y: stripY, width: width - margin * 2, height: 52),
                         xRadius: 10, yRadius: 10).fill()
            drawText("真实大小（菜单栏 1x）", font: .systemFont(ofSize: 10),
                     color: secondary, at: NSPoint(x: margin + 14, y: stripY + 34))
            var x = margin + 150
            for (index, state) in states.enumerated() where index != 6 {
                let icon = MenuBarIconRenderer.image(for: state.2, variant: .disc, appearance: appearance)
                icon.draw(in: NSRect(x: x, y: stripY + (52 - icon.size.height) / 2,
                                     width: icon.size.width, height: icon.size.height))
                x += icon.size.width + 22
            }
        }
    }

    // MARK: - 面板预览

    private static func renderPanelSheet(appearance: NSAppearance,
                                         colorScheme: ColorScheme,
                                         pageBackground: NSColor,
                                         title: String,
                                         to url: URL) throws {
        let models: [(String, AppModel)] = [
            ("有会话", AppModel.demo()),
            ("全部空闲", emptyModel()),
            ("未连接", AppModel.demoDisconnected()),
        ]
        let panelWidth: CGFloat = 340
        let gap: CGFloat = 30
        let margin: CGFloat = 30
        let titleHeight: CGFloat = 64
        let labelHeight: CGFloat = 32

        let images = models.map { _, model in
            renderPanel(model: model, width: panelWidth, appearance: appearance, colorScheme: colorScheme)
        }
        let maxHeight = images.map(\.size.height).max() ?? 200
        let width = margin * 2 + panelWidth * 3 + gap * 2
        let height = titleHeight + maxHeight + labelHeight + margin
        let secondary = NSColor.labelColor.withAlphaComponent(0.55)

        try savePNG(width: width, height: height, appearance: appearance, to: url) { rect in
            pageBackground.setFill()
            rect.fill()
            drawText(title, font: .systemFont(ofSize: 15, weight: .semibold),
                     color: .labelColor, at: NSPoint(x: margin, y: height - margin - 18))
            drawText("click 会话行跳转 · 待回答红色 · 运行中蓝色 · 已完成绿色 · 已停止橙色",
                     font: .systemFont(ofSize: 11), color: secondary,
                     at: NSPoint(x: margin, y: height - margin - 36))

            for (index, image) in images.enumerated() {
                let x = margin + CGFloat(index) * (panelWidth + gap)
                let y = margin + labelHeight + (maxHeight - image.size.height) / 2
                // 阴影底板 + 圆角裁剪
                NSColor.labelColor.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: NSRect(x: x - 1, y: y - 1, width: panelWidth + 2, height: image.size.height + 2),
                             xRadius: 13, yRadius: 13).fill()
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: panelWidth, height: image.size.height),
                             xRadius: 12, yRadius: 12).addClip()
                image.draw(in: NSRect(x: x, y: y, width: panelWidth, height: image.size.height))
                NSGraphicsContext.restoreGraphicsState()
                drawText(models[index].0, font: .systemFont(ofSize: 11.5),
                         color: secondary, at: NSPoint(x: x, y: margin - 6))
            }
        }
    }

    private static func emptyModel() -> AppModel {
        let model = AppModel()
        model.setConnected(true)
        model.apply(state: DemoState.emptyState)
        return model
    }

    private static func renderPanel(model: AppModel, width: CGFloat,
                                    appearance: NSAppearance,
                                    colorScheme: ColorScheme) -> NSImage {
        let root = StatusPanelView(model: model)
            .environment(\.colorScheme, colorScheme)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: 220)
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        let height = max(120, fitting.height)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return NSImage(size: NSSize(width: width, height: height))
        }
        rep.size = hosting.bounds.size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        return image
    }

    // MARK: - 绘制工具

    private static func savePNG(width: CGFloat, height: CGFloat,
                                appearance: NSAppearance,
                                to url: URL,
                                draw: (NSRect) -> Void) throws {
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(width * scale)),
            pixelsHigh: Int(ceil(height * scale)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw NSError(domain: "PreviewRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "bitmap alloc failed"])
        }
        rep.size = NSSize(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw NSError(domain: "PreviewRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "context alloc failed"])
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        appearance.performAsCurrentDrawingAppearance {
            draw(NSRect(x: 0, y: 0, width: width, height: height))
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PreviewRenderer", code: 3, userInfo: [NSLocalizedDescriptionKey: "png encode failed"])
        }
        try png.write(to: url)
    }

    private static func drawText(_ string: String, font: NSFont, color: NSColor, at point: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        NSAttributedString(string: string, attributes: attrs).draw(at: point)
    }
}

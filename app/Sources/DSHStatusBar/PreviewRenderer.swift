import AppKit
import SwiftUI

/// `--render-previews`：离屏渲染图标矩阵与面板预览图（docs/app-design.md §2.4）。
enum PreviewRenderer {
    static func renderAll(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let light = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        let dark = NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()

        try renderIconSheet(
            appearance: light,
            menuBarBackground: NSColor(srgbRed: 0.929, green: 0.929, blue: 0.937, alpha: 1),
            pageBackground: NSColor(srgbRed: 0.973, green: 0.973, blue: 0.980, alpha: 1),
            title: "DSH 菜单栏图标 · 浅色菜单栏",
            to: directory.appendingPathComponent("icon-preview-light.png")
        )
        try renderIconSheet(
            appearance: dark,
            menuBarBackground: NSColor(srgbRed: 0.11, green: 0.11, blue: 0.118, alpha: 1),
            pageBackground: NSColor(srgbRed: 0.086, green: 0.086, blue: 0.094, alpha: 1),
            title: "DSH 菜单栏图标 · 深色菜单栏",
            to: directory.appendingPathComponent("icon-preview-dark.png")
        )
        try renderPanelSheet(
            appearance: light,
            colorScheme: .light,
            pageBackground: NSColor(srgbRed: 0.973, green: 0.973, blue: 0.980, alpha: 1),
            title: "DSH 面板 · 浅色",
            to: directory.appendingPathComponent("panel-preview-light.png")
        )
        try renderPanelSheet(
            appearance: dark,
            colorScheme: .dark,
            pageBackground: NSColor(srgbRed: 0.086, green: 0.086, blue: 0.094, alpha: 1),
            title: "DSH 面板 · 深色",
            to: directory.appendingPathComponent("panel-preview-dark.png")
        )
    }

    // MARK: - 图标矩阵

    private static func renderIconSheet(appearance: NSAppearance,
                                        menuBarBackground: NSColor,
                                        pageBackground: NSColor,
                                        title: String,
                                        to url: URL) throws {
        let margin: CGFloat = 28
        let labelWidth: CGFloat = 130
        let colWidth: CGFloat = 236
        let rowHeight: CGFloat = 54
        let states: [(String, IconModel)] = [
            ("空闲 (0)", IconModel()),
            ("运行中 (2)", IconModel(running: 2)),
            ("已完成 (1)", IconModel(completed: 1)),
            ("已停止 (1)", IconModel(stopped: 1)),
            ("待回答 (1)", IconModel(waiting: 1)),
            ("混合（3 关注 · 2 运行）", IconModel(waiting: 1, running: 2, completed: 1, stopped: 1)),
            ("未连接", IconModel(connected: false)),
        ]
        let titleHeight: CGFloat = 62
        let headerHeight: CGFloat = 40
        let stripHeight: CGFloat = 96
        let width = margin * 2 + labelWidth + colWidth * 3
        let height = titleHeight + headerHeight + rowHeight * CGFloat(states.count) + stripHeight + margin

        try savePNG(width: width, height: height, appearance: appearance, to: url) { rect in
            pageBackground.setFill()
            rect.fill()

            drawText(title, font: .systemFont(ofSize: 15, weight: .semibold),
                     color: .labelColor,
                     at: NSPoint(x: margin, y: height - margin - 18))

            // 列标题
            let headerY = height - titleHeight - 20
            for (index, style) in IconStyle.allCases.enumerated() {
                let x = margin + labelWidth + CGFloat(index) * colWidth
                drawText(style.label, font: .systemFont(ofSize: 12, weight: .medium),
                         color: .secondaryLabelColor, at: NSPoint(x: x, y: headerY))
            }

            // 行
            for (rowIndex, state) in states.enumerated() {
                let y = height - titleHeight - headerHeight - CGFloat(rowIndex + 1) * rowHeight
                if rowIndex % 2 == 0 {
                    NSColor.labelColor.withAlphaComponent(0.03).setFill()
                    NSRect(x: margin - 8, y: y, width: width - margin * 2 + 16, height: rowHeight).fill()
                }
                drawTruncatedText(state.0, font: .systemFont(ofSize: 11.5),
                                  color: .secondaryLabelColor,
                                  in: NSRect(x: margin, y: y + rowHeight / 2 - 8, width: labelWidth - 8, height: 18))
                for (index, style) in IconStyle.allCases.enumerated() {
                    let x = margin + labelWidth + CGFloat(index) * colWidth
                    let icon = MenuBarIconRenderer.image(for: state.1, style: style, appearance: appearance)
                    let scale: CGFloat = 2.4
                    let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
                    let drawRect = NSRect(
                        x: x,
                        y: y + (rowHeight - size.height) / 2,
                        width: size.width,
                        height: size.height
                    )
                    icon.draw(in: drawRect)
                }
            }

            // 真实尺寸条（模拟菜单栏）
            let stripY = margin
            menuBarBackground.setFill()
            NSBezierPath(roundedRect: NSRect(x: margin, y: stripY, width: width - margin * 2, height: 44),
                         xRadius: 9, yRadius: 9).fill()
            drawText("真实大小（1x）", font: .systemFont(ofSize: 10.5),
                     color: .secondaryLabelColor,
                     at: NSPoint(x: margin + 10, y: stripY + 28))
            var x = margin + 110
            for style in IconStyle.allCases {
                let icon = MenuBarIconRenderer.image(for: states[5].1, style: style, appearance: appearance)
                icon.draw(in: NSRect(x: x, y: stripY + (44 - icon.size.height) / 2,
                                     width: icon.size.width, height: icon.size.height))
                x += icon.size.width + 36
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
        let titleHeight: CGFloat = 58
        let labelHeight: CGFloat = 30

        let images = models.map { _, model in
            renderPanel(model: model, width: panelWidth, appearance: appearance, colorScheme: colorScheme)
        }
        let maxHeight = images.map(\.size.height).max() ?? 200
        let width = margin * 2 + panelWidth * 3 + gap * 2
        let height = titleHeight + maxHeight + labelHeight + margin

        try savePNG(width: width, height: height, appearance: appearance, to: url) { rect in
            pageBackground.setFill()
            rect.fill()
            drawText(title, font: .systemFont(ofSize: 15, weight: .semibold),
                     color: .labelColor, at: NSPoint(x: margin, y: height - margin - 18))

            for (index, image) in images.enumerated() {
                let x = margin + CGFloat(index) * (panelWidth + gap)
                let y = margin + labelHeight + (maxHeight - image.size.height) / 2
                // 阴影底板 + 圆角裁剪
                NSColor.labelColor.withAlphaComponent(0.12).setFill()
                NSBezierPath(roundedRect: NSRect(x: x - 1, y: y - 1, width: panelWidth + 2, height: image.size.height + 2),
                             xRadius: 13, yRadius: 13).fill()
                NSGraphicsContext.saveGraphicsState()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: panelWidth, height: image.size.height),
                             xRadius: 12, yRadius: 12).addClip()
                image.draw(in: NSRect(x: x, y: y, width: panelWidth, height: image.size.height))
                NSGraphicsContext.restoreGraphicsState()
                drawText(models[index].0, font: .systemFont(ofSize: 11.5),
                         color: .secondaryLabelColor,
                         at: NSPoint(x: x, y: margin - 4))
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
            throw NSError(domain: "PreviewRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "png encode failed"])
        }
        try png.write(to: url)
    }

    private static func drawText(_ string: String, font: NSFont, color: NSColor, at point: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        NSAttributedString(string: string, attributes: attrs).draw(at: point)
    }

    private static func drawTruncatedText(_ string: String, font: NSFont, color: NSColor, in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSAttributedString(string: string, attributes: attrs)
            .draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

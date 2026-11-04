import AppKit
import SwiftUI

/// `--render-previews`：离屏渲染图标矩阵、面板预览与场景示意图。
enum PreviewRenderer {
    static func renderAll(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let light = NSAppearance(named: .aqua) ?? NSAppearance.currentDrawing()
        let dark = NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()

        try renderIconSheet(
            appearance: dark, dark: true,
            pageBackground: NSColor(hex: 0x0E0E10),
            menuBarBackground: NSColor(hex: 0x1C1C1E),
            title: "DSH 菜单栏图标 · 深色（主用）",
            to: directory.appendingPathComponent("icon-preview-dark.png")
        )
        try renderIconSheet(
            appearance: light, dark: false,
            pageBackground: NSColor(hex: 0xF6F6F8),
            menuBarBackground: NSColor(hex: 0xECECEF),
            title: "DSH 菜单栏图标 · 浅色",
            to: directory.appendingPathComponent("icon-preview-light.png")
        )
        try renderPanelSheet(
            appearance: dark, colorScheme: .dark,
            pageBackground: NSColor(hex: 0x0E0E10),
            title: "DSH 面板 · 深色（主用）",
            to: directory.appendingPathComponent("panel-preview-dark.png")
        )
        try renderPanelSheet(
            appearance: light, colorScheme: .light,
            pageBackground: NSColor(hex: 0xF6F6F8),
            title: "DSH 面板 · 浅色",
            to: directory.appendingPathComponent("panel-preview-light.png")
        )
        try renderScene(appearance: dark, colorScheme: .dark,
                        to: directory.appendingPathComponent("scene-preview-dark.png"))
        try renderSettingsSheet(appearance: dark,
                                to: directory.appendingPathComponent("settings-preview-dark.png"))
    }

    // MARK: - 图标矩阵

    private static let states: [(String, String, IconModel)] = [
        ("空闲", "没有任何非空闲任务 · 纯白鲸鱼", IconModel(statuses: [])),
        ("1 个运行中", "整环 = 1 段 · 只有运行中不显示数字", IconModel(statuses: [.running])),
        ("2 个运行中", "对半分 = 2 段 · 无数字", IconModel(statuses: [.running, .running])),
        ("1 个待回答", "整环 = 待回答红 · 中心 1", IconModel(statuses: [.waiting])),
        ("1 个已完成", "整环 = 已完成绿 · 中心 1", IconModel(statuses: [.completed])),
        ("1 个已停止", "整环 = 已停止橙 · 中心 1", IconModel(statuses: [.stopped])),
        ("1 待回答 + 2 运行中", "三等分 · 中心 1（只数非运行中）", IconModel(statuses: [.waiting, .running, .running])),
        ("2 待回答 + 1 已完成 + 2 运行中", "五等分 · 中心 3", IconModel(statuses: [.waiting, .waiting, .completed, .running, .running])),
        ("未连接", "灰色虚线环", IconModel(statuses: [], connected: false)),
        ("数字 = 非空闲总数", "设置：中心数字改为「非空闲总数」", IconModel(statuses: [.waiting, .running, .running], numberMode: .nonIdle)),
        ("段数上限 4（共 5 个任务）", "设置：最多画 4 段，中心数字仍完整", IconModel(statuses: [.waiting, .waiting, .completed, .running, .running], segmentCap: 4)),
        ("隐藏「运行中」", "设置：状态过滤后只剩待回答+已完成", IconModel(statuses: [.waiting, .completed])),
    ]

    private static func renderIconSheet(appearance: NSAppearance,
                                        dark: Bool,
                                        pageBackground: NSColor,
                                        menuBarBackground: NSColor,
                                        title: String,
                                        to url: URL) throws {
        let margin: CGFloat = 30
        let labelColumn: CGFloat = 340
        let rowHeight: CGFloat = 78
        let titleHeight: CGFloat = 66
        let headerHeight: CGFloat = 30
        let stripHeight: CGFloat = 104
        let width: CGFloat = 760
        let height = titleHeight + headerHeight + rowHeight * CGFloat(states.count) + stripHeight + margin

        try savePNG(width: width, height: height, appearance: appearance, to: url) { rect in
            let secondary = NSColor.secondaryLabelColor
            pageBackground.setFill()
            rect.fill()

            drawText(title, font: .systemFont(ofSize: 15, weight: .semibold), color: .labelColor,
                     at: NSPoint(x: margin, y: height - margin - 18))
            drawText("圆环段数 = 非空闲任务数 · 段色 = 状态 · 中心数字 = 待回答+已完成+已停止",
                     font: .systemFont(ofSize: 11), color: secondary,
                     at: NSPoint(x: margin, y: height - margin - 36))

            drawText("状态说明", font: .systemFont(ofSize: 11, weight: .medium), color: secondary,
                     at: NSPoint(x: margin, y: height - titleHeight - 14))
            drawText("图标（放大 3.2×）", font: .systemFont(ofSize: 11, weight: .medium), color: secondary,
                     at: NSPoint(x: margin + labelColumn, y: height - titleHeight - 14))

            for (rowIndex, state) in states.enumerated() {
                let y = height - titleHeight - headerHeight - CGFloat(rowIndex + 1) * rowHeight
                if rowIndex % 2 == 0 {
                    NSColor.labelColor.withAlphaComponent(dark ? 0.045 : 0.035).setFill()
                    NSRect(x: margin - 10, y: y, width: width - margin * 2 + 20, height: rowHeight).fill()
                }
                drawText(state.0, font: .systemFont(ofSize: 12, weight: .medium), color: .labelColor,
                         at: NSPoint(x: margin, y: y + 46))
                drawText(state.1, font: .systemFont(ofSize: 10.5), color: secondary,
                         at: NSPoint(x: margin, y: y + 28))

                let icon = MenuBarIconRenderer.image(for: state.2, appearance: appearance)
                let scale: CGFloat = 3.2
                let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
                icon.draw(in: NSRect(x: margin + labelColumn, y: y + (rowHeight - size.height) / 2,
                                     width: size.width, height: size.height))
            }

            // 真实尺寸
            let stripY = margin
            menuBarBackground.setFill()
            NSBezierPath(roundedRect: NSRect(x: margin, y: stripY, width: width - margin * 2, height: 54),
                         xRadius: 10, yRadius: 10).fill()
            drawText("真实大小（菜单栏 1x）", font: .systemFont(ofSize: 10),
                     color: secondary, at: NSPoint(x: margin + 14, y: stripY + 35))
            var x = margin + 150
            for (index, state) in states.enumerated() where index != states.count - 1 {
                let icon = MenuBarIconRenderer.image(for: state.2, appearance: appearance)
                icon.draw(in: NSRect(x: x, y: stripY + (54 - icon.size.height) / 2,
                                     width: icon.size.width, height: icon.size.height))
                x += icon.size.width + 24
            }
        }
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
        let iconModel = iconModel(for: DemoState.state)
        let icon = MenuBarIconRenderer.image(for: iconModel, appearance: appearance)
        let iconX: CGFloat = width - 196
        let iconRect = NSRect(x: iconX,
                              y: height - menuBarHeight + (menuBarHeight - icon.size.height) / 2,
                              width: icon.size.width, height: icon.size.height)
        let panelX = iconX + icon.size.width / 2 - panelWidth + 60
        let panelY = height - menuBarHeight - 10 - panelImage.size.height

        try savePNG(width: width, height: height, appearance: appearance, to: url) { rect in
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

    // MARK: - 设置页预览

    private static func renderSettingsSheet(appearance: NSAppearance, to url: URL) throws {
        let settings = AppSettings.preview()
        let model = AppModel.demo(settings: settings)
        let root = SettingsView(settings: settings, model: model)
            .environment(\.colorScheme, .dark)
        let hosting = NSHostingView(rootView: root)
        hosting.appearance = appearance
        hosting.frame = NSRect(x: 0, y: 0, width: 470, height: 760)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "PreviewRenderer", code: 9, userInfo: [NSLocalizedDescriptionKey: "settings bitmap failed"])
        }
        rep.size = hosting.bounds.size
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: NSSize(width: 470, height: 760))
        image.addRepresentation(rep)

        let margin: CGFloat = 34
        let titleHeight: CGFloat = 86
        let width = 470 + margin * 2
        let height = 760 + margin + titleHeight

        try savePNG(width: width, height: height, appearance: appearance, to: url) { rect in
            NSColor(hex: 0x0E0E10).setFill()
            rect.fill()
            drawText("DSH Status 设置页 · 深色", font: .systemFont(ofSize: 15, weight: .semibold),
                     color: .labelColor, at: NSPoint(x: margin, y: height - margin - 18))
            drawText("显示状态 / 隐藏项目 / 菜单栏数字 / 圆环段数上限 / 通知；修改即时生效",
                     font: .systemFont(ofSize: 11), color: .secondaryLabelColor,
                     at: NSPoint(x: margin, y: height - margin - 36))

            let x = margin
            let y = margin
            NSColor.labelColor.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: NSRect(x: x - 1, y: y - 1, width: 472, height: 762),
                         xRadius: 13, yRadius: 13).fill()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 470, height: 760),
                         xRadius: 12, yRadius: 12).addClip()
            image.draw(in: NSRect(x: x, y: y, width: 470, height: 760))
            NSGraphicsContext.restoreGraphicsState()
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
        let panelWidth: CGFloat = 344
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

        try savePNG(width: width, height: height, appearance: appearance, to: url) { rect in
            let secondary = NSColor.secondaryLabelColor
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
        let model = AppModel(settings: .preview())
        model.setConnected(true)
        model.apply(state: DemoState.emptyState)
        return model
    }

    private static func iconModel(for state: BridgeState) -> IconModel {
        let priority: [SessionStatus: Int] = [.waiting: 0, .running: 1, .completed: 2, .stopped: 3]
        let statuses = state.sessions
            .filter { $0.statusKind != .idle }
            .sorted { lhs, rhs in
                let lp = priority[lhs.statusKind] ?? 9
                let rp = priority[rhs.statusKind] ?? 9
                if lp != rp { return lp < rp }
                return (lhs.updatedAt ?? 0) > (rhs.updatedAt ?? 0)
            }
            .map { $0.statusKind }
        return IconModel(statuses: statuses)
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

import AppKit
import SwiftUI

/// 统一设计 token：与 macOS 26/27 原生视觉一致（Liquid Glass 时代）。
///
/// 原则（见 docs/ui-redesign-spec.md）：
/// - 界面颜色一律用系统语义色（label / secondaryLabel / separator / system 状态色）；
/// - 彩色只用于状态 glyph、设置页图标块与连接点；
/// - 菜单栏图标有自己的 22pt 调色板（`statusNSColor`），因为它画在壁纸/菜单栏上，
///   需要比正文更大的对比度，这里保持既有调色不动。
enum Theme {
    /// 面板/设置页视觉尺寸（pt）。改动会影响真机观感，改前先看 docs/ui-redesign-spec.md。
    enum Metrics {
        // 弹出面板
        static let panelWidth: CGFloat = 330
        static let panelCornerRadius: CGFloat = 16
        static let panelHorizontalPadding: CGFloat = 14
        static let rowHeight: CGFloat = 44
        static let subagentRowHeight: CGFloat = 24
        static let footerHeight: CGFloat = 38
        static let maxContentHeight: CGFloat = 480

        // 设置窗口
        static let settingsWidth: CGFloat = 540
        static let settingsHeight: CGFloat = 640
        static let settingsMinWidth: CGFloat = 500
        static let settingsMinHeight: CGFloat = 480
        static let settingsIconSize: CGFloat = 24
        static let settingsIconCorner: CGFloat = 6
    }

    // MARK: - 界面状态色（动态系统色）

    /// 面板/设置页里小面积使用的状态色。
    /// 使用系统动态色，深浅色模式下自动取 Apple 原生色值。
    static func uiColor(_ status: SessionStatus) -> Color {
        Color(nsColor: uiNSColor(status))
    }

    static func uiNSColor(_ status: SessionStatus) -> NSColor {
        switch status {
        case .waiting: return .systemYellow
        case .running: return .systemBlue
        case .completed: return .systemGreen
        case .stopped: return .systemRed
        case .idle: return .secondaryLabelColor
        }
    }

    /// 兼容旧调用点（设置页图标块用）。
    static func statusColor(_ status: SessionStatus, scheme: ColorScheme) -> Color {
        Color(nsColor: uiNSColor(status))
    }

    static func statusColor(_ status: SessionStatus, dark: Bool) -> Color {
        Color(nsColor: uiNSColor(status))
    }

    /// 未连接 = 次要文字色，不用彩色（系统里「不可用」不靠颜色表达）。
    static func disconnectedColor(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .secondaryLabelColor)
    }

    // MARK: - 菜单栏图标调色板（22pt，需要更大对比度；保持 v5 既有取值）

    static func statusNSColor(_ status: SessionStatus, dark: Bool) -> NSColor {
        let rgb = iconStatusRGB(status, dark: dark)
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    private static func iconStatusRGB(_ status: SessionStatus, dark: Bool) -> (Double, Double, Double) {
        switch status {
        case .waiting:
            // 待回答 = 黄色（参考 Status Trio 的 Low Power Mode 黄 #F2B900）
            return dark ? (0.949, 0.725, 0.000) : (0.780, 0.600, 0.000)
        case .running:
            // 运行中 = 蓝色（参考 Status Trio 的蓝牙播放蓝 #0A84FF）
            return dark ? (0.039, 0.518, 1.000) : (0.000, 0.478, 1.000)
        case .completed:
            // 已完成 = 绿色（参考 Status Trio 的充电绿 #34C759）
            return dark ? (0.204, 0.780, 0.349) : (0.141, 0.541, 0.239)
        case .stopped:
            // 已停止 = 红色（系统红）
            return dark ? (1.000, 0.271, 0.227) : (0.843, 0.000, 0.082)
        case .idle:
            return dark ? (0.58, 0.58, 0.60) : (0.46, 0.46, 0.48)
        }
    }

    // MARK: - 面板（卡片式浮层）

    /// 离屏预览（无材质）时的面板底色，近似真实灰玻璃在常见深色背景上的观感。
    static var panelFallbackBackground: Color {
        Color(nsColor: dynamicNSColor(dark: (0.19, 0.19, 0.21), light: (0.95, 0.95, 0.96)))
    }

    // MARK: - 设置窗口（原生实测色板，显式不透明色，避免跟随桌面/窗口激活态变色）

    /// 设置窗口内容底（实测 System Settings 深色 #1F2024；浅色取系统浅灰白）。
    static var settingsContentBackground: Color {
        Color(nsColor: dynamicColor(dark: (0.122, 0.125, 0.141), light: (0.949, 0.949, 0.965)))
    }

    /// 设置分组卡片底（实测 System Settings 深色 #26272B；浅色为纯白）。
    static var settingsCardBackground: Color {
        Color(nsColor: dynamicColor(dark: (0.149, 0.153, 0.169), light: (1.0, 1.0, 1.0)))
    }

    /// 设置行分隔线（实测 #303135 / 浅色 #E3E3E8）。
    static var settingsSeparator: Color {
        Color(nsColor: dynamicColor(dark: (0.188, 0.192, 0.208), light: (0.890, 0.890, 0.906)))
    }

    /// 显式深/浅两套色值（不参与 vibrancy/壁纸染色）。
    static func dynamicNSColor(dark: (Double, Double, Double),
                               light: (Double, Double, Double)) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let rgb = isDark ? dark : light
            return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        }
    }

    private static func dynamicColor(dark: (Double, Double, Double),
                                     light: (Double, Double, Double)) -> NSColor {
        dynamicNSColor(dark: dark, light: light)
    }

    // MARK: - 表面与描边（系统语义色）

    /// hover 底色：用主文字色的小透明度，深浅色通用。
    static func hoverFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    /// 面板内分隔线颜色（动态）。
    static var separator: Color { Color(nsColor: .separatorColor) }

    /// 面板内次级表面（如提示条、设置图标块底色）。
    static func subtleFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    /// 设置页图标块：系统色 → 上亮下暗的轻微渐变（接近系统设置 sidebar 图标）。
    static func iconBlockGradient(_ color: NSColor) -> LinearGradient {
        let base = Color(nsColor: color)
        return LinearGradient(colors: [base.opacity(0.98), base.opacity(0.88)],
                              startPoint: .top,
                              endPoint: .bottom)
    }

    // MARK: - 兼容旧设置页的 token（新设置页用 grouped Form，不再使用这些）

    enum Radius {
        static let card: CGFloat = 10
        static let row: CGFloat = 8
        static let well: CGFloat = 12
        static let control: CGFloat = 6
    }

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035)
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        Color(nsColor: .separatorColor)
    }
}

// MARK: - 面板背景开关（预览时用实色，避免离屏渲染毛玻璃不稳定）

private struct PanelUsesMaterialKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var panelUsesMaterial: Bool {
        get { self[PanelUsesMaterialKey.self] }
        set { self[PanelUsesMaterialKey.self] = newValue }
    }
}

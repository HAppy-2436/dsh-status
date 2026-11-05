import AppKit
import SwiftUI

/// 统一设计 token：圆角、柔和配色（深色模式优先），尽量贴近 macOS 系统风格。
enum Theme {
    enum Radius {
        static let card: CGFloat = 14
        static let row: CGFloat = 10
        static let well: CGFloat = 12
        static let control: CGFloat = 8
    }

    // MARK: 状态色（低饱和、深浅两套）

    static func statusColor(_ status: SessionStatus, scheme: ColorScheme) -> Color {
        let rgb = statusRGB(status, dark: scheme == .dark)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    static func statusColor(_ status: SessionStatus, dark: Bool) -> Color {
        let rgb = statusRGB(status, dark: dark)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    static func statusNSColor(_ status: SessionStatus, dark: Bool) -> NSColor {
        let rgb = statusRGB(status, dark: dark)
        return NSColor(srgbRed: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    private static func statusRGB(_ status: SessionStatus, dark: Bool) -> (Double, Double, Double) {
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

    /// 未连接用中性灰（参考 Status Trio 用 30% 前景色表示不可用状态）。
    static func disconnectedColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.557, green: 0.557, blue: 0.576)
            : Color(red: 0.420, green: 0.420, blue: 0.447)
    }

    // MARK: 表面与描边

    static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.035)
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }

    static func hairline(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07)
    }

    static func hoverFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.055) : Color.black.opacity(0.045)
    }

    static func subtleFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.065) : Color.black.opacity(0.05)
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

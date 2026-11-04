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
            return dark ? (0.914, 0.498, 0.463) : (0.816, 0.396, 0.365)
        case .running:
            return dark ? (0.478, 0.663, 0.843) : (0.353, 0.522, 0.741)
        case .completed:
            return dark ? (0.494, 0.753, 0.616) : (0.353, 0.604, 0.475)
        case .stopped:
            return dark ? (0.859, 0.690, 0.459) : (0.722, 0.549, 0.318)
        case .idle:
            return dark ? (0.58, 0.58, 0.60) : (0.46, 0.46, 0.48)
        }
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

// MARK: - 原生毛玻璃背景（面板用）

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
    }
}

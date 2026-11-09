import Foundation
import ServiceManagement

/// 「登录时自动启动」的系统状态（macOS 13+ 的 `SMAppService.mainApp`）。
///
/// 不把开关存进 `UserDefaults`：登录项的真实状态由系统维护，App 只读取
/// `SMAppService.mainApp.status` 并据此渲染开关。这样用户在「系统设置 → 通用 → 登录项」
/// 里手动关掉、或系统要求确认时，设置页仍显示真实状态，不会出现「开关记住了、系统没生效」。
final class LaunchAtLoginController: ObservableObject {
    enum State: Equatable {
        case enabled
        case disabled
        /// 已注册但需要用户在「系统设置 → 通用 → 登录项」里放行。
        case requiresApproval
        case failed(String)
    }

    @Published private(set) var state: State = .disabled

    init() { refresh() }

    /// 开关显示值：`requiresApproval` 视为「已开启、等待系统确认」。
    var isOn: Bool {
        switch state {
        case .enabled, .requiresApproval: return true
        case .disabled, .failed: return false
        }
    }

    var detailText: String {
        switch state {
        case .enabled: return "已随登录自动启动"
        case .disabled: return "登录 macOS 后自动打开 DSH Status"
        case .requiresApproval: return "已注册，需在「系统设置 → 通用 → 登录项」中允许"
        case .failed(let message): return message
        }
    }

    func refresh() {
        // 离屏预览（`--render-previews`）不读取本机真实登录项，保证文档图可复现。
        if CommandLine.arguments.contains("--render-previews") {
            state = .disabled
            return
        }
        switch SMAppService.mainApp.status {
        case .enabled: state = .enabled
        case .requiresApproval: state = .requiresApproval
        case .notRegistered: state = .disabled
        case .notFound:
            // 首次注册前，部分环境（App 不在 /Applications、尚未经 LaunchServices 登记等）
            // 会返回 notFound。语义上等同「尚未注册」：按关闭显示；register() 仍可成功，
            // 若确实失败，切换开关时会进入 failed 并显示系统错误。
            state = .disabled
        @unknown default: state = .disabled
        }
    }

    /// 返回是否成功；失败时 `state == .failed(message)`。
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
        refresh()
        return true
    }

    /// 打开「系统设置 → 通用 → 登录项」。
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

extension LaunchAtLoginController.State: CustomStringConvertible {
    var description: String {
        switch self {
        case .enabled: return "enabled"
        case .disabled: return "disabled"
        case .requiresApproval: return "requiresApproval"
        case .failed(let message): return "failed(\(message))"
        }
    }
}

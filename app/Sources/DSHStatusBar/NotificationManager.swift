import AppKit
import UserNotifications

enum NotificationPermission: Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized
}

/// 系统通知：默认只对「进入待回答」发一条；点击跳到对应会话。
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    var onClick: ((String?) -> Void)?
    var onPermissionChanged: ((NotificationPermission) -> Void)?

    private(set) var permission: NotificationPermission = .unknown
    private var lastNotified: [String: Date] = [:]

    /// 裸二进制（未打包 .app）时 UNUserNotificationCenter 不可用，直接跳过。
    private var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func setup() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().delegate = self
        refreshPermission()
    }

    /// 查询当前授权状态；不主动弹系统授权框（避免 App 在后台时被静默拒绝）。
    func refreshPermission() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let permission: NotificationPermission
            switch settings.authorizationStatus {
            case .notDetermined: permission = .notDetermined
            case .denied: permission = .denied
            case .authorized, .provisional, .ephemeral: permission = .authorized
            @unknown default: permission = .unknown
            }
            DispatchQueue.main.async {
                self?.permission = permission
                self?.onPermissionChanged?(permission)
            }
        }
    }

    /// 由用户主动点「允许通知」时调用；先把 App 提到前台，系统授权框才可见。
    func requestPermission() {
        guard isBundled else { return }
        NSApp.activate(ignoringOtherApps: true)
        // 只申请横幅权限：提示音由 App 自己播放（见 NotificationSound.swift），不依赖系统通知声音。
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { [weak self] _, _ in
            self?.refreshPermission()
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSApp.activate(ignoringOtherApps: true)
        NSWorkspace.shared.open(url)
    }

    func notify(_ row: SessionRow, status: SessionStatus) {
        guard isBundled else { return }
        // 不因缓存状态守卫：权限可能在运行中被用户打开，交给系统过滤即可。
        let key = "\(row.id)-\(status.rawValue)"
        let now = Date()
        if let last = lastNotified[key], now.timeIntervalSince(last) < 30 { return }
        lastNotified[key] = now

        let content = UNMutableNotificationContent()
        switch status {
        case .waiting:
            content.title = "需要回答：\(row.displayTitle)"
            content.body = "\(row.projectName) · \(row.pendingSummary ?? "等待你的回复")"
        case .completed:
            content.title = "已完成：\(row.displayTitle)"
            content.body = "\(row.projectName) · 本轮已结束"
        case .stopped:
            content.title = "已停止：\(row.displayTitle)"
            content.body = "\(row.projectName) · 任务已停止"
        default:
            return
        }
        // 声音由 App 自己播放（独立音量、可换音色）；这里显式不给系统声音，避免「双响」。
        content.sound = nil
        content.userInfo = ["sessionId": row.id]
        let identifier = "\(status.rawValue)-\(row.id)-\(Int(now.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                FileHandle.standardError.write(Data("[dsh-status] 通知发送失败：\(error)\n".utf8))
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // 前台时仍显示横幅并进通知中心；声音由 App 内播放器负责（不依赖系统通知音）。
        completionHandler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
        DispatchQueue.main.async { self.onClick?(sessionId) }
        completionHandler()
    }
}

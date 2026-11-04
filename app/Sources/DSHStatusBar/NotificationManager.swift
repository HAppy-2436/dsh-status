import AppKit
import UserNotifications

/// 系统通知：默认只对「进入待回答」发一条；点击打开 DSH。
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    var onClick: ((String?) -> Void)?

    private var authorized = false
    private var requested = false
    private var lastNotified: [String: Date] = [:]

    /// 裸二进制（未打包 .app）时 UNUserNotificationCenter 不可用，直接跳过。
    private var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func setup() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().delegate = self
        requestAuthorizationIfNeeded()
    }

    private func requestAuthorizationIfNeeded() {
        guard isBundled, !requested else { return }
        requested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func notify(_ row: SessionRow, status: SessionStatus) {
        guard isBundled, authorized else { return }
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
        content.sound = .default
        content.userInfo = ["sessionId": row.id]
        let identifier = "\(status.rawValue)-\(row.id)-\(Int(now.timeIntervalSince1970))"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let sessionId = response.notification.request.content.userInfo["sessionId"] as? String
        DispatchQueue.main.async { self.onClick?(sessionId) }
        completionHandler()
    }
}

import AppKit
import UserNotifications
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var bridge: BridgeClient!
    private var statusItemController: StatusItemController!
    private var panelController: StatusPanelController!
    private var settingsWindow: SettingsWindowController!
    private let settings = AppSettings.shared
    private let notifications = NotificationManager()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        model = AppModel(settings: settings)
        model.onOpenSession = { [weak self] sessionId in
            self?.panelController.close()
            self?.openSession(sessionId)
        }
        model.onOpenDSH = { [weak self] in
            self?.panelController.close()
            self?.openDSH()
        }
        model.onQuit = { [weak self] in
            self?.panelController.close()
            self?.confirmQuit()
        }
        model.onStatusTransition = { [weak self] row, status in
            guard let self, !self.settings.doNotDisturb else { return }
            switch status {
            case .waiting:
                if self.settings.notifyWaiting { self.notifications.notify(row, status: .waiting) }
            case .completed:
                if self.settings.notifyCompleted { self.notifications.notify(row, status: .completed) }
            case .stopped:
                if self.settings.notifyStopped { self.notifications.notify(row, status: .stopped) }
            default:
                break
            }
        }
        model.onOpenSettings = { [weak self] in
            self?.panelController.close()
            self?.notifications.refreshPermission()
            self?.settingsWindow.show()
        }

        statusItemController = StatusItemController(model: model)
        statusItemController.onTogglePopover = { [weak self] in
            self?.notifications.refreshPermission()
            self?.panelController.toggle()
        }
        statusItemController.onOpenDSH = { [weak self] in self?.openDSH() }
        statusItemController.onQuit = { [weak self] in self?.confirmQuit() }
        statusItemController.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        statusItemController.onRequestNotificationPermission = { [weak self] in self?.notifications.requestPermission() }
        statusItemController.onOpenNotificationSettings = { [weak self] in self?.notifications.openSystemSettings() }

        panelController = StatusPanelController(model: model, statusItem: statusItemController.statusItem, settings: settings)
        settingsWindow = SettingsWindowController(settings: settings, model: model)

        // 展开/收起子智能体后内容高度变化：等 SwiftUI 完成一轮布局再重新适配面板。
        model.onPanelLayoutChange = { [weak self] in
            DispatchQueue.main.async { self?.panelController.fitIfVisible() }
        }

        // 设置变化 → 立即重绘图标
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.panelController.refreshBackground()
                DispatchQueue.main.async { self?.statusItemController.refresh() }
            }
            .store(in: &cancellables)

        notifications.setup()
        notifications.onPermissionChanged = { [weak self] permission in
            guard let self else { return }
            self.model.setNotificationPermission(permission)
        }
        notifications.onClick = { [weak self] sessionId in
            guard let self else { return }
            if let sessionId { self.bridge.sendOpenSession(sessionId) }
            self.openDSH()
        }
        model.onRequestNotificationPermission = { [weak self] in
            self?.panelController.close()
            self?.notifications.requestPermission()
        }
        model.onOpenNotificationSettings = { [weak self] in
            self?.panelController.close()
            self?.notifications.openSystemSettings()
        }

        bridge = BridgeClient(bridgeFile: AppConfig.bridgeFile)
        bridge.onState = { [weak self] state in
            guard let self else { return }
            self.model.apply(state: state)
            self.statusItemController.refresh()
            self.panelController.fitIfVisible()
        }
        bridge.onConnectionChange = { [weak self] connected in
            guard let self else { return }
            self.model.setConnected(connected)
            self.statusItemController.refresh()
            self.panelController.fitIfVisible()
        }
        bridge.onLog = { message in
            FileHandle.standardError.write(Data(("[dsh-status] " + message + "\n").utf8))
        }
        bridge.start()

        // 调试：启动后自动打开面板（便于截图/验收）
        if CommandLine.arguments.contains("--test-ring-transition") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.statusItemController.debugPlayRingTransition()
            }
        }
        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.panelController.show()
            }
        }
        if CommandLine.arguments.contains("--request-notify") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.notifications.requestPermission()
            }
        }
        if CommandLine.arguments.contains("--test-notify") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let content = UNMutableNotificationContent()
                content.title = "DSH Status 测试通知"
                content.body = "通知链路正常：任务完成时会这样提醒你。"
                content.sound = .default
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "test-\(UUID().uuidString)",
                                         content: content, trigger: nil)
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { NSApp.terminate(nil) }
        }
        if CommandLine.arguments.contains("--preview-quit-confirm") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.confirmQuit()
            }
        }
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.settingsWindow.show()
            }
        }

        // 调试/截图：展开第一个有子智能体的会话（用于出「展开态」真机截图）。
        if CommandLine.arguments.contains("--expand-subagents") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self else { return }
                if let parent = self.model.orderedSessions.first(where: { self.model.hasSubagents($0.id) }) {
                    self.model.toggleSubagents(for: parent.id)
                }
            }
        }

        // 定时刷新（运行时长/tooltip）
        Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            self?.statusItemController.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        bridge?.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - 退出确认

    private func confirmQuit() {
        guard settings.confirmBeforeQuit else {
            NSApp.terminate(nil)
            return
        }
        let alert = NSAlert()
        alert.messageText = "退出 DSH Status？"
        alert.informativeText = "菜单栏图标会消失；DeepSeek Harness 本身不受影响，之后可随时重新打开。"
        alert.alertStyle = .warning
        alert.icon = AppIconRenderer.image(size: 72)
        let cancel = alert.addButton(withTitle: "取消")
        cancel.keyEquivalent = "\r"      // 默认按钮 = 取消，避免误触
        let quit = alert.addButton(withTitle: "退出")
        quit.keyEquivalent = ""
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertSecondButtonReturn {
            NSApp.terminate(nil)
        }
    }

    // MARK: - 动作

    private func openSession(_ sessionId: String) {
        bridge.sendOpenSession(sessionId)
        openDSH()
    }

    private func openDSH() {
        if let url = URL(string: "dsh://open"), NSWorkspace.shared.open(url) {
            return
        }
        // 兜底：按 bundle id / 应用名唤起
        let candidates = ["/Applications/DeepSeek Harness.app"]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: path),
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
            return
        }
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.deepseek.dsh") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }
}

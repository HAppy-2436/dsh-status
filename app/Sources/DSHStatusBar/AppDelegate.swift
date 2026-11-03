import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var bridge: BridgeClient!
    private var statusItemController: StatusItemController!
    private var popoverController: PopoverController!
    private let notifications = NotificationManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        model = AppModel()
        model.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        model.onOpenSession = { [weak self] sessionId in self?.openSession(sessionId) }
        model.onOpenDSH = { [weak self] in self?.openDSH() }
        model.onQuit = { NSApp.terminate(nil) }
        model.onToggleNotifications = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(self.model.notificationsEnabled, forKey: "notificationsEnabled")
        }
        model.onWaitingTransition = { [weak self] row in
            guard let self, self.model.notificationsEnabled else { return }
            self.notifications.notifyWaiting(row)
        }

        statusItemController = StatusItemController(model: model)
        statusItemController.onTogglePopover = { [weak self] in self?.popoverController.toggle() }
        statusItemController.onOpenDSH = { [weak self] in self?.openDSH() }
        statusItemController.onQuit = { NSApp.terminate(nil) }
        statusItemController.onStyleChange = { [weak self] _ in self?.statusItemController.refresh() }

        popoverController = PopoverController(model: model, statusItem: statusItemController.statusItem)

        notifications.setup()
        notifications.onClick = { [weak self] _ in self?.openDSH() }

        bridge = BridgeClient(bridgeFile: AppConfig.bridgeFile)
        bridge.onState = { [weak self] state in
            guard let self else { return }
            self.model.apply(state: state)
            self.statusItemController.refresh()
        }
        bridge.onConnectionChange = { [weak self] connected in
            guard let self else { return }
            self.model.setConnected(connected)
            self.statusItemController.refresh()
        }
        bridge.onLog = { message in
            FileHandle.standardError.write(Data(("[dsh-status] " + message + "\n").utf8))
        }
        bridge.start()

        // 调试：启动后自动打开面板（便于截图/验收）
        if CommandLine.arguments.contains("--open-panel") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                self?.popoverController.show()
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

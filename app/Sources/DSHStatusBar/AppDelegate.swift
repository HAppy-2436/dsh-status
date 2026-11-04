import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var bridge: BridgeClient!
    private var statusItemController: StatusItemController!
    private var popoverController: PopoverController!
    private var settingsWindow: SettingsWindowController!
    private let settings = AppSettings.shared
    private let notifications = NotificationManager()
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        model = AppModel(settings: settings)
        model.notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        model.onOpenSession = { [weak self] sessionId in self?.openSession(sessionId) }
        model.onOpenDSH = { [weak self] in self?.openDSH() }
        model.onQuit = { NSApp.terminate(nil) }
        model.onToggleNotifications = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(self.model.notificationsEnabled, forKey: "notificationsEnabled")
        }
        model.onStatusTransition = { [weak self] row, status in
            guard let self else { return }
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
        model.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

        statusItemController = StatusItemController(model: model)
        statusItemController.onTogglePopover = { [weak self] in self?.popoverController.toggle() }
        statusItemController.onOpenDSH = { [weak self] in self?.openDSH() }
        statusItemController.onQuit = { NSApp.terminate(nil) }
        statusItemController.onOpenSettings = { [weak self] in self?.settingsWindow.show() }

        popoverController = PopoverController(model: model, statusItem: statusItemController.statusItem)
        settingsWindow = SettingsWindowController(settings: settings, model: model)

        // 设置变化 → 立即重绘图标
        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.statusItemController.refresh() }
            }
            .store(in: &cancellables)

        notifications.setup()
        notifications.onClick = { [weak self] sessionId in
            guard let self else { return }
            if let sessionId { self.bridge.sendOpenSession(sessionId) }
            self.openDSH()
        }

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
        if CommandLine.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.settingsWindow.show()
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

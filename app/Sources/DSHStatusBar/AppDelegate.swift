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
    /// 提示音合并窗口：多个会话可能在同一帧里一起跃迁，只响一次避免叠音。
    private var lastSoundAt = Date.distantPast

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
            let enabled: Bool
            switch status {
            case .waiting:
                enabled = self.settings.notifyWaiting
            case .completed:
                enabled = self.settings.notifyCompleted
            case .stopped:
                enabled = self.settings.notifyStopped
            default:
                return
            }
            guard enabled else { return }
            // 提示音是独立通道：由 App 直接播放，不依赖系统通知权限/系统通知音音量。
            // 0.4s 内的多次跃迁合并为一次提示音（否则同帧多个会话会叠成一片噪音）。
            let now = Date()
            if now.timeIntervalSince(self.lastSoundAt) >= 0.4 {
                self.lastSoundAt = now
                self.settings.playSound()
            }
            self.notifications.notify(row, status: status)
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

        // 调试：脚本化回放全部图标状态迁移（配合 DSH_STATUS_ANIM_SCALE 放慢逐帧核对）。
        // 可选参数：`--test-icon-transitions=<起始步>,<步数>`，只回放其中一段。
        if let raw = CommandLine.arguments.first(where: { $0.hasPrefix("--test-icon-transitions") }) {
            var startIndex = 0
            var count: Int?
            if let equals = raw.firstIndex(of: "=") {
                let parts = raw[raw.index(after: equals)...].split(separator: ",")
                if let first = parts.first, let value = Int(first) { startIndex = value }
                if parts.count > 1, let value = Int(parts[1]) { count = value }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.statusItemController.debugRunIconTransitionScript(startIndex: startIndex,
                                                                        count: count)
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
                content.sound = nil
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: "test-\(UUID().uuidString)",
                                         content: content, trigger: nil)
                )
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { NSApp.terminate(nil) }
        }
        // 调试：单独试听提示音（不影响通知）。`--test-sound[=<option>,<volume>]`，播完自动退出。
        if let raw = CommandLine.arguments.first(where: { $0 == "--test-sound" || $0.hasPrefix("--test-sound=") }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                var option = self.settings.soundOption
                var volume = self.settings.soundVolume
                if let equals = raw.firstIndex(of: "=") {
                    let parts = raw[raw.index(after: equals)...].split(separator: ",")
                    if let first = parts.first,
                       let parsed = NotificationSoundOption(rawValue: String(first)) { option = parsed }
                    if parts.count > 1, let parsed = Double(parts[1]) { volume = parsed }
                }
                let player = NotificationSoundPlayer.shared
                let ok = player.play(option: option,
                                     volume: volume,
                                     customPath: self.settings.soundCustomPath)
                let url = player.lastResolvedURL?.path ?? "nil"
                let error = player.lastError.map { " error=\($0)" } ?? ""
                print("[dsh-status] --test-sound option=\(option.rawValue) volume=\(volume) ok=\(ok) file=\(url)\(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { NSApp.terminate(nil) }
            }
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

        // 调试：打开面板 → 展开 → 收起 第一个有子智能体的会话，用于逐帧核对高度动画。
        // 配合 DSH_STATUS_ANIM_SCALE=10 放慢 10 倍，外部 screencapture 循环就能抓到中间帧。
        if CommandLine.arguments.contains("--animate-subagents") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.panelController.show()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
                guard let self else { return }
                if let parent = self.model.orderedSessions.first(where: { self.model.hasSubagents($0.id) }) {
                    self.model.toggleSubagents(for: parent.id)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { [weak self] in
                guard let self else { return }
                if let parent = self.model.orderedSessions.first(where: { self.model.isSubagentsExpanded($0.id) }) {
                    self.model.toggleSubagents(for: parent.id)
                }
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

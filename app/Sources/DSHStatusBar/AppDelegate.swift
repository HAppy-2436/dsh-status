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

    /// 送达方式二选一：
    /// - App 直接播放：独立音量、不受系统专注模式限制；0.4s 内的多次跃迁合并为一次提示音。
    /// - 系统通知音：声音随通知一起发，受系统专注模式/勿扰与通知音量控制。
    private func playAlertSound() {
        guard settings.soundDelivery == .app else { return }
        let now = Date()
        guard now.timeIntervalSince(lastSoundAt) >= 0.4 else { return }
        lastSoundAt = now
        settings.playSound()
    }

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
            self.playAlertSound()
            self.notifications.notify(row, status: status,
                                      sound: self.settings.systemNotificationSound())
        }
        // 焦点会话（DSH 主视图）跑完：DSH 不置 completionUnread，桥补一条 notice，这里照常提醒。
        // 开关 / 勿扰 / 项目过滤与状态跃迁完全一致（项目过滤在 AppModel 里做）。
        model.onCompletionNotice = { [weak self] notice in
            guard let self, !self.settings.doNotDisturb else { return }
            let enabled = notice.statusKind == .stopped
                ? self.settings.notifyStopped
                : self.settings.notifyCompleted
            guard enabled else { return }
            self.playAlertSound()
            self.notifications.notify(notice, sound: self.settings.systemNotificationSound())
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
        settingsWindow = SettingsWindowController(settings: settings, model: model,
                                                    onPreviewSound: { [weak self] in
                                                        self?.previewNotificationSound()
                                                    })

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
        AppIconController.shared.syncInstalledIconIfNeeded()
        if let raw = CommandLine.arguments.first(where: { $0.hasPrefix("--test-app-icon") }) {
            let style: AppIconStyle = raw.hasSuffix("=whale") ? .whale : .brand
            AppIconController.shared.apply(style)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                let matches = AppIconController.shared.bundleIconMatches(style)
                print("[dsh-status] app-icon style=\(style.rawValue) bundleIconMatches=\(matches) "
                      + "needsRestart=\(AppIconController.shared.needsRestart) "
                      + "message=\(AppIconController.shared.message ?? "")")
                _ = self
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--dump-app-icon") {
            let style = AppSettings.shared.appIconStyle
            print("[dsh-status] app-icon persisted=\(style.rawValue) "
                  + "bundleIconMatches=\(AppIconController.shared.bundleIconMatches(style))")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
        if let raw = CommandLine.arguments.first(where: { $0.hasPrefix("--test-launch-at-login") }) {
            let controller = LaunchAtLoginController()
            var action = "status"
            if raw.hasSuffix("=on") {
                action = controller.setEnabled(true) ? "on-ok" : "on-failed"
            } else if raw.hasSuffix("=off") {
                action = controller.setEnabled(false) ? "off-ok" : "off-failed"
            }
            print("[dsh-status] launch-at-login action=\(action) state=\(controller.state) "
                  + "detail=\(controller.detailText)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) }
        }
        if CommandLine.arguments.contains("--dump-appearance") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.statusItemController.dumpAppearanceDebug()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
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
        // 调试：走「焦点会话跑完」的正式通知链路（横幅文案 / 提示音 / 点击跳转），1 条后自动退出。
        // 与 `--test-notify` 的区别：这里用的是补发的 notice（没有状态行），验收焦点会话提醒用。
        if CommandLine.arguments.contains("--test-notice") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                let notice = SessionNotice(id: "test-\(UUID().uuidString)",
                                           sessionId: "test-session",
                                           kind: "completed",
                                           title: "测试会话",
                                           workspaceId: nil,
                                           workspaceTitle: "示例项目",
                                           at: Date().timeIntervalSince1970 * 1000)
                self.playAlertSound()
                self.notifications.notify(notice, sound: self.settings.systemNotificationSound())
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { NSApp.terminate(nil) }
        }
        // 调试：单独试听提示音（不影响正式通知）。
        // `--test-sound[=<option>,<volume>[,<customPath>]]`；送达方式默认跟随设置，
        // 可用 `DSH_STATUS_SOUND_DELIVERY=app|system` 覆盖（验收两种通道用），播完自动退出。
        if let raw = CommandLine.arguments.first(where: { $0 == "--test-sound" || $0.hasPrefix("--test-sound=") }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self else { return }
                var option = self.settings.soundOption
                var volume = self.settings.soundVolume
                var customPath = self.settings.soundCustomPath
                if let equals = raw.firstIndex(of: "=") {
                    let parts = raw[raw.index(after: equals)...]
                        .split(separator: ",", omittingEmptySubsequences: false)
                    if let first = parts.first,
                       let parsed = NotificationSoundOption(rawValue: String(first)) { option = parsed }
                    if parts.count > 1, let parsed = Double(parts[1]) { volume = parsed }
                    if parts.count > 2 { customPath = String(parts[2]) }
                }
                let delivery = ProcessInfo.processInfo.environment["DSH_STATUS_SOUND_DELIVERY"]
                    .flatMap { SoundDeliveryMode(rawValue: $0) } ?? self.settings.soundDelivery
                if delivery == .system {
                    let sound = SystemNotificationSound.sound(option: option, customPath: customPath)
                    let staged = SystemNotificationSound.stage(
                        option: option, customPath: customPath,
                        directory: SystemNotificationSound.defaultStagingDirectory)
                    self.notifications.previewSound(sound)
                    print("[dsh-status] --test-sound delivery=system option=\(option.rawValue) "
                          + "ok=\(sound != nil) staged=\(staged?.path ?? "nil")")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { NSApp.terminate(nil) }
                } else {
                    let player = NotificationSoundPlayer.shared
                    let ok = player.play(option: option, volume: volume, customPath: customPath)
                    let url = player.lastResolvedURL?.path ?? "nil"
                    let error = player.lastError.map { " error=\($0)" } ?? ""
                    print("[dsh-status] --test-sound delivery=app option=\(option.rawValue) "
                          + "volume=\(volume) ok=\(ok) file=\(url)\(error)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { NSApp.terminate(nil) }
                }
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

    /// 设置页「试听」：App 播放模式直接播；系统通知音模式发一条真实测试通知。
    private func previewNotificationSound() {
        if settings.soundDelivery == .app {
            _ = settings.playSound()
        } else {
            notifications.previewSound(settings.systemNotificationSound())
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

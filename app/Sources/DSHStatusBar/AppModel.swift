import AppKit
import Combine

/// UI 状态模型：由 BridgeClient 推送更新，SwiftUI 面板观察。
final class AppModel: ObservableObject {
    let settings: AppSettings
    @Published private(set) var state: BridgeState = .empty
    @Published private(set) var connected: Bool = false
    @Published private(set) var lastUpdate: Date?

    /// 状态跃迁：某会话进入新状态（用于通知；首帧基线不触发）。
    var onStatusTransition: ((SessionRow, SessionStatus) -> Void)?
    var onOpenSettings: (() -> Void)?

    var onOpenSession: ((String) -> Void)?
    var onOpenDSH: (() -> Void)?
    var onQuit: (() -> Void)?
    var onToggleNotifications: (() -> Void)?
    var notificationsEnabled: Bool = true

    private var previousStatus: [String: String] = [:]
    private var hasBaseline = false
    private var settingsCancellable: AnyCancellable?

    init(settings: AppSettings = .shared) {
        self.settings = settings
        settingsCancellable = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.objectWillChange.send() }
            }
    }

    var iconModel: IconModel {
        let statuses = visibleSessions
            .sorted { lhs, rhs in
                let lp = priority(lhs.statusKind)
                let rp = priority(rhs.statusKind)
                if lp != rp { return lp < rp }
                return (lhs.updatedAt ?? 0) > (rhs.updatedAt ?? 0)
            }
            .map { $0.statusKind }
        return IconModel(
            statuses: connected ? statuses : [],
            connected: connected,
            segmentCap: settings.segmentCap.rawValue,
            numberMode: settings.centerNumberMode
        )
    }

    var sections: [(status: SessionStatus, rows: [SessionRow])] {
        let visible = visibleSessions
        var grouped: [SessionStatus: [SessionRow]] = [:]
        for row in visible { grouped[row.statusKind, default: []].append(row) }
        return [SessionStatus.waiting, .running, .completed, .stopped].compactMap { status in
            guard let rows = grouped[status], !rows.isEmpty else { return nil }
            let sorted = rows.sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            return (status, sorted)
        }
    }

    var attendingCount: Int { state.counts.attention }

    func apply(state: BridgeState) {
        let rows = state.sessions
        var next: [String: String] = [:]
        for row in rows { next[row.id] = row.status }

        var transitions: [(SessionRow, SessionStatus)] = []
        if hasBaseline {
            for row in rows where settings.isVisible(row) {
                if let previous = previousStatus[row.id], previous != row.status {
                    transitions.append((row, row.statusKind))
                }
            }
        }
        previousStatus = next
        hasBaseline = true
        self.state = state
        self.lastUpdate = Date()
        for (row, status) in transitions { onStatusTransition?(row, status) }
    }

    // MARK: - 过滤

    private var visibleSessions: [SessionRow] {
        state.sessions.filter { $0.statusKind != .idle && settings.isVisible($0) }
    }

    private func priority(_ status: SessionStatus) -> Int {
        switch status {
        case .waiting: return 0
        case .running: return 1
        case .completed: return 2
        case .stopped: return 3
        case .idle: return 9
        }
    }

    func setConnected(_ value: Bool) {
        guard connected != value else { return }
        connected = value
        if !value {
            // 断线时保留最后一帧数据用于「打开 DSH」，但图标显示未连接
            lastUpdate = Date()
        }
    }

    // MARK: - 预览用

    static func demo(settings: AppSettings = .preview()) -> AppModel {
        let model = AppModel(settings: settings)
        model.connected = true
        model.state = DemoState.state
        model.lastUpdate = Date()
        return model
    }

    static func demoDisconnected() -> AppModel {
        let model = AppModel(settings: .preview())
        model.connected = false
        model.state = .empty
        return model
    }
}

enum DemoState {
    static func row(_ id: String, _ title: String, _ workspace: String,
                    _ status: String, pending: PendingInfo? = nil,
                    updatedMinutesAgo: Double = 1, since: Double? = nil) -> SessionRow {
        let now = Date().timeIntervalSince1970 * 1000
        return SessionRow(
            id: id,
            title: title,
            workspaceId: "w-\(workspace)",
            workspaceTitle: workspace,
            status: status,
            pending: pending,
            lastTurn: status == "stopped" ? LastTurn(kind: "aborted", at: now - 42 * 60_000) : nil,
            since: since ?? now - updatedMinutesAgo * 60_000,
            updatedAt: now - updatedMinutesAgo * 60_000
        )
    }

    static let state: BridgeState = {
        let rows = [
            row("session-erhu", "选哪种调音方案？", "erhu", "waiting",
                pending: PendingInfo(kind: "question", summary: "选哪种调音方案？"), updatedMinutesAgo: 1),
            row("session-dsh", "实现菜单栏图标", "dsh-status", "running", updatedMinutesAgo: 0.2, since: Date().timeIntervalSince1970 * 1000 - 134_000),
            row("session-stability", "测试出口节点", "stability", "running", updatedMinutesAgo: 0.3, since: Date().timeIntervalSince1970 * 1000 - 300_000),
            row("session-protocol", "写桥接协议", "dsh-status", "completed", updatedMinutesAgo: 9),
            row("session-homebrew", "梳理 homebrew 配置", "homebrew", "stopped", updatedMinutesAgo: 42),
        ]
        return BridgeState(
            version: 1,
            generatedAt: Date().timeIntervalSince1970 * 1000,
            dsh: DSHInfo(pid: 12345, version: "0.2.1-rc.5"),
            client: ClientInfo(connected: true, lastPushAt: Date().timeIntervalSince1970 * 1000),
            counts: Counts(waiting: 1, running: 2, completed: 1, stopped: 1, attention: 3),
            sessions: rows
        )
    }()

    static let emptyState = BridgeState(
        version: 1,
        generatedAt: Date().timeIntervalSince1970 * 1000,
        dsh: DSHInfo(pid: 12345, version: "0.2.1-rc.5"),
        client: ClientInfo(connected: true, lastPushAt: Date().timeIntervalSince1970 * 1000),
        counts: Counts(waiting: 0, running: 0, completed: 0, stopped: 0, attention: 0),
        sessions: []
    )
}

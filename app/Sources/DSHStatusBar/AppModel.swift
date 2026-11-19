import AppKit
import Combine

/// UI 状态模型：由 BridgeClient 推送更新，SwiftUI 面板观察。
final class AppModel: ObservableObject {
    let settings: AppSettings
    @Published private(set) var state: BridgeState = .empty
    @Published private(set) var connected: Bool = false
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var notificationPermission: NotificationPermission = .unknown
    /// 当前是否正在阻止 Mac 闲置睡眠（设置页副标题用）。
    @Published private(set) var sleepPrevented: Bool = false

    /// 状态跃迁：某会话进入新状态（用于通知；首帧基线不触发）。
    var onStatusTransition: ((SessionRow, SessionStatus) -> Void)?
    /// 桥补发的「焦点会话跑完」通知（没有状态行；首帧基线不触发，按 id 去重）。
    var onCompletionNotice: ((SessionNotice) -> Void)?
    var onRequestNotificationPermission: (() -> Void)?
    var onOpenNotificationSettings: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    var onOpenSession: ((String) -> Void)?
    /// 面板行尾「忽略」：删掉桥补的临时「已完成」行（sessionId）。
    var onDismissSession: ((String) -> Void)?
    var onOpenDSH: (() -> Void)?
    var onQuit: (() -> Void)?
    /// 面板内容高度变化（如展开/收起子智能体）时请求重新适配窗口。
    var onPanelLayoutChange: (() -> Void)?

    /// 面板里已展开子智能体的父会话（默认折叠；仅内存态，重启回到折叠）。
    @Published private(set) var expandedSubagentParents: Set<String> = []

    private var previousStatus: [String: String] = [:]
    private var hasBaseline = false
    private var noticeInbox = NoticeInbox()
    private var settingsCancellable: AnyCancellable?
    private var sleepSettingCancellable: AnyCancellable?
    private let sleepPreventer = SleepPreventer()

    init(settings: AppSettings = .shared) {
        self.settings = settings
        settingsCancellable = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.objectWillChange.send() }
            }
        sleepSettingCancellable = settings.$preventSleepWhileRunning
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.refreshSleepPrevention() }
            }
    }

    func setNotificationPermission(_ permission: NotificationPermission) {
        notificationPermission = permission
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
            numberMode: settings.centerNumberMode,
            idleStyle: settings.menuBarIdleStyle
        )
    }

    /// 面板列表：不按状态分组，最近一次状态变化（`since`）越新越靠上。
    var orderedSessions: [SessionRow] {
        visibleSessions.sorted { lhs, rhs in
            let lhsChanged = lhs.since ?? lhs.updatedAt ?? 0
            let rhsChanged = rhs.since ?? rhs.updatedAt ?? 0
            if lhsChanged != rhsChanged { return lhsChanged > rhsChanged }
            let lhsUpdated = lhs.updatedAt ?? 0
            let rhsUpdated = rhs.updatedAt ?? 0
            if lhsUpdated != rhsUpdated { return lhsUpdated > rhsUpdated }
            return lhs.id < rhs.id
        }
    }

    var attendingCount: Int { state.counts.attention }

    /// 某个父会话下的子智能体（已按状态过滤，按更新时间倒序）。
    func subagents(for parentId: String) -> [SubagentRow] {
        state.subagentRows
            .filter { $0.parentId == parentId && settings.shows($0.statusKind) }
            .sorted { ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
    }

    // MARK: 预览用悬停状态（仅供离屏出图，真机不走这里）

    enum PreviewHoverTrailing { case row, control }

    /// 预览渲染时强制某行进入悬停态：`trailing` 指定悬停的是整行还是行尾披露按钮。
    private(set) var previewHover: (rowId: String, trailing: PreviewHoverTrailing)?

    func setPreviewHover(rowId: String, trailing: PreviewHoverTrailing) {
        previewHover = (rowId, trailing)
    }

    func hasSubagents(_ parentId: String) -> Bool {
        !subagents(for: parentId).isEmpty
    }

    func isSubagentsExpanded(_ parentId: String) -> Bool {
        expandedSubagentParents.contains(parentId)
    }

    /// Finder 风格披露三角：展开/收起某父会话的子智能体。
    func toggleSubagents(for parentId: String) {
        if expandedSubagentParents.contains(parentId) {
            expandedSubagentParents.remove(parentId)
        } else {
            expandedSubagentParents.insert(parentId)
        }
        onPanelLayoutChange?()
    }

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
        refreshSleepPrevention()
        for (row, status) in transitions { onStatusTransition?(row, status) }

        // 焦点会话跑完：桥用 notice 代替 completed 行，这里做同样的开关/过滤后交给通知。
        let notices = state.noticeRows
        let freshNoticeIds = noticeInbox.fresh(notices.map(\.id))
        guard !freshNoticeIds.isEmpty else { return }
        var noticesById: [String: SessionNotice] = [:]
        for notice in notices { noticesById[notice.id] = notice }
        for id in freshNoticeIds {
            guard let notice = noticesById[id], settings.isVisible(notice) else { continue }
            onCompletionNotice?(notice)
        }
    }

    /// 维护「有会话运行中时阻止闲置睡眠」的电源断言。
    ///
    /// 条件 = 设置开关 && 已连接 DSH && 有运行中的顶层会话。
    /// 断线、全部跑完、关闭开关或 App 退出时都会释放；断言是幂等的，重复调用不会叠加。
    private func refreshSleepPrevention() {
        let shouldPrevent = settings.preventSleepWhileRunning
            && connected
            && state.counts.running > 0
        let active = sleepPreventer.update(shouldPrevent: shouldPrevent)
        if sleepPrevented != active { sleepPrevented = active }
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
        refreshSleepPrevention()
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
            updatedAt: now - updatedMinutesAgo * 60_000,
            transient: nil
        )
    }

    static let state: BridgeState = {
        let rows = [
            row("session-example-a", "选择实现方案", "example-app", "waiting",
                pending: PendingInfo(kind: "question", summary: "选择实现方案"), updatedMinutesAgo: 1),
            row("session-example-b", "实现设置页", "example-app", "running", updatedMinutesAgo: 0.2, since: Date().timeIntervalSince1970 * 1000 - 134_000),
            row("session-example-c", "运行回归测试", "example-lab", "running", updatedMinutesAgo: 0.3, since: Date().timeIntervalSince1970 * 1000 - 300_000),
            row("session-example-d", "编写接入文档", "example-app", "completed", updatedMinutesAgo: 9),
            row("session-example-e", "整理配置清单", "example-tools", "stopped", updatedMinutesAgo: 42),
        ]
        return BridgeState(
            version: 1,
            generatedAt: Date().timeIntervalSince1970 * 1000,
            dsh: DSHInfo(pid: 12345, version: "0.2.1-rc.5"),
            client: ClientInfo(connected: true, lastPushAt: Date().timeIntervalSince1970 * 1000),
            counts: Counts(waiting: 1, running: 2, completed: 1, stopped: 1, attention: 3),
            sessions: rows,
            subagents: [
                SubagentRow(id: "sub-1", parentId: "session-example-b", title: "拆分设计任务",
                            status: "running", pending: nil, updatedAt: Date().timeIntervalSince1970 * 1000 - 20_000),
                SubagentRow(id: "sub-2", parentId: "session-example-b", title: "实现数据导入",
                            status: "completed", pending: nil, updatedAt: Date().timeIntervalSince1970 * 1000 - 120_000),
                SubagentRow(id: "sub-3", parentId: "session-example-c", title: "核对分析结果",
                            status: "running", pending: nil, updatedAt: Date().timeIntervalSince1970 * 1000 - 40_000),
            ],
            notices: []
        )
    }()

    static let emptyState = BridgeState(
        version: 1,
        generatedAt: Date().timeIntervalSince1970 * 1000,
        dsh: DSHInfo(pid: 12345, version: "0.2.1-rc.5"),
        client: ClientInfo(connected: true, lastPushAt: Date().timeIntervalSince1970 * 1000),
        counts: Counts(waiting: 0, running: 0, completed: 0, stopped: 0, attention: 0),
        sessions: [],
        subagents: [],
        notices: []
    )
}

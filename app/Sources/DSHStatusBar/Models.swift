import Foundation

// MARK: - 桥协议数据模型（docs/protocol.md §2）

struct BridgeInfo: Codable, Equatable {
    let version: Int
    let port: Int
    let origin: String
    let token: String
    let pid: Int?
    let startedAt: Double?
    let appPath: String?
    let mock: Bool?
}

struct BridgeState: Codable, Equatable {
    let version: Int
    let generatedAt: Double
    let dsh: DSHInfo?
    let client: ClientInfo?
    let counts: Counts
    let sessions: [SessionRow]
    /// 子智能体会话：只用于面板展示，不计入 counts / 图标 / 通知。
    let subagents: [SubagentRow]?
    /// 焦点会话跑完的一次性通知（见 `SessionNotice`）；旧版桥不发送该字段。
    let notices: [SessionNotice]?

    var subagentRows: [SubagentRow] { subagents ?? [] }
    var noticeRows: [SessionNotice] { notices ?? [] }

    static let empty = BridgeState(
        version: 1,
        generatedAt: 0,
        dsh: nil,
        client: nil,
        counts: Counts(waiting: 0, running: 0, completed: 0, stopped: 0, attention: 0),
        sessions: [],
        subagents: [],
        notices: []
    )
}

struct DSHInfo: Codable, Equatable {
    let pid: Int?
    let version: String?
}

struct ClientInfo: Codable, Equatable {
    let connected: Bool
    let lastPushAt: Double?
}

struct Counts: Codable, Equatable {
    let waiting: Int
    let running: Int
    let completed: Int
    let stopped: Int
    let attention: Int
}

struct PendingInfo: Codable, Equatable {
    let kind: String?
    let summary: String?
}

struct LastTurn: Codable, Equatable {
    let kind: String?
    let at: Double?
}

enum SessionStatus: String, Codable, CaseIterable {
    case waiting
    case running
    case completed
    case stopped
    case idle

    var label: String {
        switch self {
        case .waiting: return "待回答"
        case .running: return "运行中"
        case .completed: return "已完成"
        case .stopped: return "已停止"
        case .idle: return "空闲"
        }
    }

    var sortOrder: Int {
        switch self {
        case .waiting: return 0
        case .running: return 1
        case .completed: return 2
        case .stopped: return 3
        case .idle: return 4
        }
    }
}

struct SessionRow: Codable, Equatable, Identifiable {
    let id: String
    let title: String?
    let workspaceId: String?
    let workspaceTitle: String?
    let status: String
    let pending: PendingInfo?
    let lastTurn: LastTurn?
    let since: Double?
    let updatedAt: Double?

    var statusKind: SessionStatus { SessionStatus(rawValue: status) ?? .idle }
    var displayTitle: String {
        if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        return "未命名会话"
    }
    var projectName: String {
        if let w = workspaceTitle, !w.isEmpty { return w }
        return "未分组"
    }
    var pendingSummary: String? {
        guard let p = pending else { return nil }
        if let s = p.summary, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        switch p.kind {
        case "plan-review": return "等待确认计划"
        case "approval": return "等待批准操作"
        case "question": return "等待回答问题"
        default: return "等待你的回复"
        }
    }
}

/// 子智能体会话（挂在父会话下，用于面板展示）。
struct SubagentRow: Codable, Equatable, Identifiable {
    let id: String
    let parentId: String?
    let title: String?
    let status: String
    let pending: PendingInfo?
    let updatedAt: Double?

    var statusKind: SessionStatus { SessionStatus(rawValue: status) ?? .idle }
    var displayTitle: String {
        if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        return "子智能体"
    }
}

/// 焦点会话（DSH 主视图）跑完时桥补发的一次性通知。
///
/// DSH 只在「跑完时不在主视图」才置 `completionUnread`，所以在看的那个会话跑完既没有
/// completed 行、也不会触发状态跃迁通知；桥按 `turn/end` 原因补一条 notice，App 据此照常提醒。
/// notice 不产生面板行、不计入 counts / 角标。协议见 docs/protocol.md §2。
struct SessionNotice: Codable, Equatable, Identifiable {
    let id: String
    let sessionId: String
    let kind: String?
    let title: String?
    let workspaceId: String?
    let workspaceTitle: String?
    let at: Double?

    var statusKind: SessionStatus { kind == "stopped" ? .stopped : .completed }

    var displayTitle: String {
        if let t = title, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return t }
        return "未命名会话"
    }

    var projectName: String {
        if let w = workspaceTitle, !w.isEmpty { return w }
        return "未分组"
    }
}

struct CommandRequest: Codable {
    let type: String
    let sessionId: String
}

struct CommandResponse: Codable {
    let ok: Bool?
    let requestId: String?
    let error: String?
}

// MARK: - 帮助函数

enum Fmt {
    static func relative(_ millis: Double?, now: Date = Date()) -> String {
        guard let millis, millis > 0 else { return "" }
        let date = Date(timeIntervalSince1970: millis / 1000)
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 45 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) 小时前" }
        return "\(Int(seconds / 86_400)) 天前"
    }

    static func elapsed(_ millis: Double?) -> String {
        guard let millis, millis > 0 else { return "" }
        let seconds = max(0, Date().timeIntervalSince1970 - millis / 1000)
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}

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

    static let empty = BridgeState(
        version: 1,
        generatedAt: 0,
        dsh: nil,
        client: nil,
        counts: Counts(waiting: 0, running: 0, completed: 0, stopped: 0, attention: 0),
        sessions: []
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

enum SessionStatus: String, Codable {
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

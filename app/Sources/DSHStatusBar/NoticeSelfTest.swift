import Foundation

/// `--self-test-notice`：焦点会话完成通知自检。
///
/// 覆盖桥协议 `notices` 的解码（含旧版桥缺字段）、`SessionNotice` 文案兜底、
/// `NoticeInbox` 的首帧基线 / 去重 / 上限，以及通知过滤（状态显示开关 + 隐藏项目）。
/// 纯逻辑，无 AppKit 窗口、无系统通知权限依赖；`scripts/build-app.sh` 组装 .app 后自动跑。
enum NoticeSelfTest {
    static func run() -> Int32 {
        var failures = 0

        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  [\(detail)]")")
            if !ok { failures += 1 }
        }

        print("== BridgeState.notices 解码 ==")
        let withNotices = """
        {"version":1,"generatedAt":1000,
         "dsh":{"pid":1,"version":"test"},
         "client":{"connected":true,"lastPushAt":1000},
         "counts":{"waiting":0,"running":1,"completed":0,"stopped":0,"attention":0},
         "sessions":[],
         "notices":[{"id":"s1:900","sessionId":"s1","kind":"completed","title":"跑测试",
                     "workspaceId":"w1","workspaceTitle":"example-app","at":900}]}
        """
        let decoded = decodeState(withNotices)
        check("含 notices 的状态可解码", decoded != nil)
        check("notice 条数", decoded?.noticeRows.count == 1, "\(decoded?.noticeRows.count ?? -1)")
        check("notice 状态标签 = 已完成", decoded?.noticeRows.first?.statusKind == .completed)
        check("notice 标题", decoded?.noticeRows.first?.displayTitle == "跑测试")
        check("notice 项目名", decoded?.noticeRows.first?.projectName == "example-app")
        check("notice 会话 id", decoded?.noticeRows.first?.sessionId == "s1")

        let stoppedJSON = withNotices.replacingOccurrences(of: "\"kind\":\"completed\"", with: "\"kind\":\"stopped\"")
        check("kind=stopped → 已停止", decodeState(stoppedJSON)?.noticeRows.first?.statusKind == .stopped)

        print("\n== 旧版桥 / 未知字段兼容 ==")
        let legacy = """
        {"version":1,"generatedAt":1000,
         "counts":{"waiting":0,"running":0,"completed":0,"stopped":0,"attention":0},
         "sessions":[]}
        """
        let legacyState = decodeState(legacy)
        check("缺 notices 字段仍可解码", legacyState != nil)
        check("缺 notices → 空列表", legacyState?.noticeRows.isEmpty == true)

        let unknown = legacy.replacingOccurrences(
            of: "\"sessions\":[]",
            with: "\"sessions\":[],\"futureField\":{\"x\":1}")
        check("未知字段被忽略", decodeState(unknown) != nil)

        print("\n== SessionRow.transient（临时「已完成」行） ==")
        check("transient:true 可解码",
              decodeRow(#"{"id":"s1","title":"跑测试","status":"completed","transient":true}"#)?.isTransient == true)
        check("缺 transient → 普通行",
              decodeRow(#"{"id":"s2","title":"普通","status":"completed"}"#)?.isTransient == false)
        check("transient 行状态标签",
              decodeRow(#"{"id":"s3","status":"stopped","transient":true}"#)?.statusKind == .stopped)

        print("\n== SessionNotice 文案兜底 ==")
        let bare = SessionNotice(id: "n1", sessionId: "s1", kind: nil, title: nil,
                                 workspaceId: nil, workspaceTitle: nil, at: nil)
        check("缺 kind → 已完成", bare.statusKind == .completed)
        check("空标题 → 未命名会话", bare.displayTitle == "未命名会话")
        check("空项目 → 未分组", bare.projectName == "未分组")
        let blank = SessionNotice(id: "n2", sessionId: "s2", kind: "completed", title: "   ",
                                  workspaceId: nil, workspaceTitle: "", at: 0)
        check("纯空白标题 → 未命名会话", blank.displayTitle == "未命名会话")
        check("空 workspaceTitle → 未分组", blank.projectName == "未分组")

        print("\n== NoticeInbox：基线 / 去重 / 上限 ==")
        var inbox = NoticeInbox(capacity: 4)
        check("首帧基线不通知", inbox.fresh(["a:1", "b:2"]).isEmpty)
        check("基线已登记（同帧重放不通知）", inbox.fresh(["a:1", "b:2"]).isEmpty)
        check("新 id 通知一次", inbox.fresh(["a:1", "c:3"]) == ["c:3"])
        check("同一 id 不重复通知", inbox.fresh(["c:3"]).isEmpty)
        check("多新 id 保持输入顺序", inbox.fresh(["d:4", "e:5"]) == ["d:4", "e:5"])
        check("空 id 被忽略", inbox.fresh(["", "f:6"]) == ["f:6"])
        check("空帧不通知", inbox.fresh([]).isEmpty)

        var small = NoticeInbox(capacity: 2)
        _ = small.fresh(["base:0"])              // 基线
        check("上限内正常通知", small.fresh(["a:1"]) == ["a:1"])
        _ = small.fresh(["b:2"])                 // 淘汰 base:0
        check("淘汰最旧后仍通知新 id", small.fresh(["c:3"]) == ["c:3"])
        check("被淘汰的旧 id 会重新通知（有上限的代价）", small.fresh(["base:0"]) == ["base:0"])

        print("\n== 通知过滤（状态显示 / 隐藏项目） ==")
        let settings = AppSettings.preview()
        settings.visibleStatuses = Set(SessionStatus.allCases.filter { $0 != .idle })
        settings.hiddenWorkspaces = []
        check("默认设置下已完成可见", settings.isVisible(bare))
        settings.hiddenWorkspaces = ["w1"]
        let hidden = SessionNotice(id: "n3", sessionId: "s3", kind: "completed", title: "t",
                                   workspaceId: "w1", workspaceTitle: "example-app", at: 1)
        check("隐藏项目不提醒", settings.isVisible(hidden) == false)
        settings.hiddenWorkspaces = []
        settings.visibleStatuses.remove(.completed)
        check("关闭「已完成」显示后不提醒", settings.isVisible(bare) == false)
        settings.visibleStatuses.insert(.completed)
        settings.visibleStatuses.remove(.stopped)
        let stoppedNotice = SessionNotice(id: "n4", sessionId: "s4", kind: "stopped", title: "t",
                                          workspaceId: nil, workspaceTitle: nil, at: 1)
        check("关闭「已停止」显示后不提醒", settings.isVisible(stoppedNotice) == false)
        settings.visibleStatuses.insert(.stopped)
        check("恢复显示后重新可见", settings.isVisible(stoppedNotice))

        print("\n== AppModel：notice → onCompletionNotice 的接线 ==")
        let modelSettings = AppSettings.preview()
        modelSettings.visibleStatuses = Set(SessionStatus.allCases.filter { $0 != .idle })
        modelSettings.hiddenWorkspaces = []
        let model = AppModel(settings: modelSettings)
        var received: [String] = []
        model.onCompletionNotice = { received.append($0.id) }

        let running = SessionRow(id: "s1", title: "跑测试", workspaceId: "w1",
                                 workspaceTitle: "example-app", status: "running",
                                 pending: nil, lastTurn: nil, since: 1, updatedAt: 1, transient: nil)
        func frame(_ notices: [SessionNotice]) -> BridgeState {
            BridgeState(version: 1, generatedAt: 2, dsh: nil,
                        client: ClientInfo(connected: true, lastPushAt: 2),
                        counts: Counts(waiting: 0, running: 1, completed: 0, stopped: 0, attention: 0),
                        sessions: [running], subagents: [], notices: notices)
        }
        let notice = SessionNotice(id: "n1", sessionId: "s1", kind: "completed", title: "跑测试",
                                   workspaceId: "w1", workspaceTitle: "example-app", at: 2)
        model.apply(state: frame([]))
        check("首帧（无 notice）不通知", received.isEmpty)
        model.apply(state: frame([notice]))
        check("新 notice 通知一次", received == ["n1"])
        model.apply(state: frame([notice]))
        check("同一 notice 重放不重复通知", received == ["n1"])

        modelSettings.hiddenWorkspaces = ["w1"]
        let hiddenNotice = SessionNotice(id: "n2", sessionId: "s1", kind: "completed", title: "跑测试",
                                         workspaceId: "w1", workspaceTitle: "example-app", at: 3)
        model.apply(state: frame([notice, hiddenNotice]))
        check("隐藏项目的 notice 不通知", received == ["n1"])

        modelSettings.hiddenWorkspaces = []
        modelSettings.visibleStatuses.remove(.completed)
        model.apply(state: frame([notice, hiddenNotice]))
        check("关闭「已完成」显示后 notice 不通知", received == ["n1"])

        print(failures == 0 ? "\n全部通过" : "\n失败 \(failures) 项")
        return failures == 0 ? 0 : 1
    }

    private static func decodeRow(_ json: String) -> SessionRow? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SessionRow.self, from: data)
    }

    private static func decodeState(_ json: String) -> BridgeState? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BridgeState.self, from: data)
    }
}

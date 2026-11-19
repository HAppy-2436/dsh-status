import Foundation

/// 完成通知去重器。
///
/// 桥插件在「焦点会话跑完」时补发一条 `SessionNotice`（DSH 不置 `completionUnread`，
/// 所以没有 completed 行，只能靠这条通知）。状态快照是幂等的、还可能因为 SSE 重连
/// 重复到达，所以按 `id` 去重：
///
/// - **首帧基线**只登记不通知（与状态跃迁的「首帧不触发」一致，App 重启后不会为旧通知补弹横幅）；
///   基线由第一帧（哪怕这一帧没有 notice）确立，之后的 notice 才可能触发提醒；
/// - 之后每个新 `id` 只上报一次，重复到达直接忽略；
/// - 已见过的 id 有上限，超出后按先进先出淘汰，避免长跑进程内存无限增长。
struct NoticeInbox {
    private(set) var seen: Set<String> = []
    private var order: [String] = []
    private var primed = false
    private let capacity: Int

    init(capacity: Int = 512) {
        self.capacity = max(1, capacity)
    }

    /// 返回本帧需要通知的 id（保持输入顺序）。
    mutating func fresh(_ ids: [String]) -> [String] {
        if !primed {
            primed = true
            for id in ids { remember(id) }
            return []
        }
        var fresh: [String] = []
        for id in ids where !id.isEmpty && !seen.contains(id) {
            remember(id)
            fresh.append(id)
        }
        return fresh
    }

    private mutating func remember(_ id: String) {
        guard !id.isEmpty, seen.insert(id).inserted else { return }
        order.append(id)
        if order.count > capacity {
            let drop = order.count - capacity
            for old in order.prefix(drop) { seen.remove(old) }
            order.removeFirst(drop)
        }
    }
}

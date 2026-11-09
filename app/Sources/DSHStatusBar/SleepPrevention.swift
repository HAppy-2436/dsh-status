import Foundation

/// 会话运行期间阻止 Mac 进入闲置睡眠（等价 `caffeinate -i`）。
///
/// 用 `ProcessInfo.beginActivity(.idleSystemSleepDisabled)` 申请系统电源断言：
/// - 只阻止「闲置系统睡眠」：显示器仍可关闭，合盖 / 手动睡眠 / 低电量强制睡眠不受影响；
/// - 断言绑定进程生命周期，App 退出或崩溃时由系统自动回收，不会残留；
/// - 无第三方依赖、无需任何权限。
///
/// `pmset -g assertions` 里可看到 `PreventUserIdleSystemSleep` 断言与本类给出的 reason。
final class SleepPreventer {
    /// 当前持有的断言 token；`nil` 表示没有阻止睡眠。
    private var activity: NSObjectProtocol?

    /// 当前是否正在阻止闲置睡眠。
    var isActive: Bool { activity != nil }

    /// 按「是否应阻止」同步断言状态（幂等：重复调用不会叠加断言）。
    /// - Parameter shouldPrevent: 有运行中会话且用户开启开关时为 true。
    /// - Returns: 更新后是否处于阻止状态。
    @discardableResult
    func update(shouldPrevent: Bool) -> Bool {
        if shouldPrevent {
            guard activity == nil else { return true }
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.idleSystemSleepDisabled],
                // 断言名会显示在 `pmset -g assertions`；用 ASCII 保证可见（中文会被系统过滤成空串）。
                reason: "DSH Status: sessions running, preventing idle sleep"
            )
            return activity != nil
        }
        stop()
        return false
    }

    /// 结束断言（显式路径；App 退出时系统也会自动回收）。
    func stop() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }

    deinit {
        stop()
    }
}

import Foundation

enum AppConfig {
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// bridge.json 路径：`--bridge-file` 参数 > `DSH_STATUS_BRIDGE_FILE` 环境变量 > ~/.dsh-status/bridge.json
    static var bridgeFile: URL {
        if let idx = CommandLine.arguments.firstIndex(of: "--bridge-file"),
           idx + 1 < CommandLine.arguments.count {
            return URL(fileURLWithPath: CommandLine.arguments[idx + 1])
        }
        if let env = ProcessInfo.processInfo.environment["DSH_STATUS_BRIDGE_FILE"], !env.isEmpty {
            return URL(fileURLWithPath: env)
        }
        return home.appendingPathComponent(".dsh-status/bridge.json")
    }

    /// 面板高度动画/视图查看用的倍速（调试）：`DSH_STATUS_ANIM_SCALE=10` 把窗口高度动画放慢 10 倍，
    /// 便于逐帧核对「展开只向下长、内容不上下漂」。默认 1（正常速度）。
    static var animationScale: Double {
        guard let raw = ProcessInfo.processInfo.environment["DSH_STATUS_ANIM_SCALE"],
              let value = Double(raw), value > 0 else { return 1 }
        return value
    }

    static let pollInterval: TimeInterval = 2.0
    static let staleAfter: TimeInterval = 12.0

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }
}

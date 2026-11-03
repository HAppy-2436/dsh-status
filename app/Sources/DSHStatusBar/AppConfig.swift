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

    static let pollInterval: TimeInterval = 2.0
    static let staleAfter: TimeInterval = 6.0

    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.1.0"
    }
}

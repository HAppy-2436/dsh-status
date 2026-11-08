import AppKit

// MARK: - 提示音选项

/// 设置页「提示音 → 声音」的可选项。
///
/// 设计背景（用户反馈「系统默认提示音太不明显」）：
/// - 系统通知音的音量由「系统设置 → 通知」与提醒音量控制，App 无法调节，且系统音本身峰值偏低；
/// - 因此提示音改为**由 App 自己播放**（`NSSound`），App 内独立音量、独立选音，甚至不受
///   「系统通知被关闭」影响（横幅不弹，声音照响，除非开勿扰）。
/// - 默认使用随 App 打包的 `dsh-chime.wav`：三音上行琶音、峰值 0.92（约为系统 Glass 的 4.6 倍），
///   生成脚本见 `scripts/generate-dsh-chime.py`。
enum NotificationSoundOption: String, CaseIterable, Identifiable {
    /// 内置「DSH 提示音」：更响、更有辨识度（默认）。
    case dshChime
    /// macOS 自带声音（`/System/Library/Sounds/<name>.aiff`）。
    case glass
    case hero
    case ping
    case sosumi
    case submarine
    case pop
    case tink
    case basso
    /// 用户自选音频文件（WAV / AIFF / MP3 / M4A / CAF 等，路径存 UserDefaults）。
    case custom
    /// 静音：不发提示音（系统通知横幅照常）。
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dshChime: return "DSH 提示音（推荐）"
        case .glass: return "Glass · 清脆"
        case .hero: return "Hero · 悠长"
        case .ping: return "Ping · 短促"
        case .sosumi: return "Sosumi · 醒目"
        case .submarine: return "Submarine · 低沉"
        case .pop: return "Pop · 轻快"
        case .tink: return "Tink · 轻盈"
        case .basso: return "Basso · 厚重"
        case .custom: return "自定义音频文件…"
        case .none: return "静音"
        }
    }

    /// macOS 自带声音名（对应 `/System/Library/Sounds/<name>.aiff`）；
    /// 内置音 / 自定义 / 静音返回 nil。
    var systemSoundName: String? {
        switch self {
        case .glass: return "Glass"
        case .hero: return "Hero"
        case .ping: return "Ping"
        case .sosumi: return "Sosumi"
        case .submarine: return "Submarine"
        case .pop: return "Pop"
        case .tink: return "Tink"
        case .basso: return "Basso"
        case .dshChime, .custom, .none: return nil
        }
    }

    /// 设置项是否真的会发声（用于设置页禁用试听/音量控件）。
    var producesSound: Bool {
        self != .none
    }
}

// MARK: - 提示音播放器

/// App 内提示音播放器：解析音频文件 → `NSSound` 播放 → 独立音量。
///
/// 为什么不用 `UNNotificationSound`：它无法设置音量（由系统提醒音量决定），
/// 也不支持「系统通知关闭后仍提醒」，正是用户反馈「太不明显」的根因。
final class NotificationSoundPlayer: NSObject, NSSoundDelegate {
    static let shared = NotificationSoundPlayer()

    /// 正在播放的 `NSSound` 必须被持有，否则会提前释放导致声音被截断。
    private var activeSounds: [NSSound] = []
    /// 最近一次解析到的音频文件（调试/自检用）。
    private(set) var lastResolvedURL: URL?
    /// 最近一次播放失败原因（设置页/日志用）。
    private(set) var lastError: String?

    /// 内置提示音资源：优先 App bundle，其次可执行文件旁（未打包 .app 直接跑 `.build` 产物时），
    /// 最后是工作区 `app/Resources`（调试用；`scripts/demo.sh` 走的是打包后的 .app，资源正常）。
    static func bundledChimeURL() -> URL? {
        if let url = Bundle.main.url(forResource: "dsh-chime", withExtension: "wav") {
            return url
        }
        let executableDir = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
            .deletingLastPathComponent()
        let workingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            executableDir.appendingPathComponent("dsh-chime.wav"),
            executableDir.appendingPathComponent("Resources/dsh-chime.wav"),
            workingDir.appendingPathComponent("app/Resources/dsh-chime.wav"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 选项 → 具体音频文件。`.none` / 缺失的 `.custom` 返回 nil。
    static func resolveURL(option: NotificationSoundOption, customPath: String?) -> URL? {
        switch option {
        case .none:
            return nil
        case .dshChime:
            if let url = bundledChimeURL() { return url }
            // 直接运行 `.build` 产物（未打包 .app）时没有随包资源：降级到系统 Glass，保证链路可测。
            return URL(fileURLWithPath: "/System/Library/Sounds/Glass.aiff")
        case .custom:
            guard let customPath, !customPath.isEmpty else { return nil }
            let url = URL(fileURLWithPath: customPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        default:
            guard let name = option.systemSoundName else { return nil }
            let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    }

    /// 按选项 + 音量播放一次；返回是否成功开始播放。
    ///
    /// `volume` 为 App 内独立音量（0…1，与系统通知/提醒音量无关，仍受系统总输出音量限制）。
    @discardableResult
    func play(option: NotificationSoundOption,
              volume: Double,
              customPath: String?) -> Bool {
        lastError = nil
        guard option.producesSound else {
            lastError = "当前设置为静音"
            return false
        }
        guard let url = Self.resolveURL(option: option, customPath: customPath) else {
            lastError = option == .custom ? "自定义音频文件不存在" : "找不到音频：\(option.rawValue)"
            return false
        }
        guard let sound = NSSound(contentsOf: url, byReference: true)
                ?? NSSound(contentsOf: url, byReference: false) else {
            lastError = "无法加载音频：\(url.lastPathComponent)"
            return false
        }

        activeSounds.removeAll { !$0.isPlaying }
        sound.volume = Self.clampedVolume(volume)
        sound.delegate = self
        lastResolvedURL = url
        activeSounds.append(sound)
        guard sound.play() else {
            activeSounds.removeAll { $0 === sound }
            lastError = "音频播放失败：\(url.lastPathComponent)"
            return false
        }
        return true
    }

    func stopAll() {
        activeSounds.forEach { $0.stop() }
        activeSounds.removeAll()
    }

    /// 音量统一夹取到 0…1（`NSSound.volume` 超出会被系统钳制，这里提前收敛并便于自检）。
    static func clampedVolume(_ volume: Double) -> Float {
        Float(min(max(volume, 0), 1))
    }

    // MARK: NSSoundDelegate

    func sound(_ sound: NSSound, didFinishPlaying flag: Bool) {
        activeSounds.removeAll { $0 === sound }
    }
}

// MARK: - 自检（--self-test-sound）

/// 无音频硬件依赖的自检：资源打包、选项解析、音量映射、设置默认值与持久化。
/// 用 `DSHStatusBar --self-test-sound` 运行（`scripts/build-app.sh` 组装 .app 后自动跑）。
enum NotificationSoundSelfTest {
    static func run() -> Int32 {
        var failures = 0

        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            print("\(ok ? "PASS" : "FAIL")  \(name)\(detail.isEmpty ? "" : "  [\(detail)]")")
            if !ok { failures += 1 }
        }

        print("== 内置提示音资源 ==")
        let chimeURL = NotificationSoundPlayer.bundledChimeURL()
        check("dsh-chime.wav 已打包", chimeURL != nil, chimeURL?.path ?? "未找到")
        if let chimeURL,
           let chime = NSSound(contentsOf: chimeURL, byReference: true) {
            let duration = chime.duration
            check("内置提示音可加载", true, String(format: "%.2fs", duration))
            check("内置提示音时长 0.6–2.0s", duration >= 0.6 && duration <= 2.0,
                  String(format: "%.2fs", duration))
        } else {
            check("内置提示音可加载", false)
        }

        print("\n== macOS 系统声音选项 ==")
        for option in NotificationSoundOption.allCases where option.systemSoundName != nil {
            let url = NotificationSoundPlayer.resolveURL(option: option, customPath: nil)
            let loadable = url.flatMap { NSSound(contentsOf: $0, byReference: true) } != nil
            check("\(option.rawValue) 可解析并可加载", url != nil && loadable, url?.lastPathComponent ?? "nil")
        }

        print("\n== 选项边界 ==")
        check("静音不解析出文件",
              NotificationSoundPlayer.resolveURL(option: .none, customPath: nil) == nil)
        check("自定义空路径不解析出文件",
              NotificationSoundPlayer.resolveURL(option: .custom, customPath: nil) == nil)
        check("自定义不存在路径不解析出文件",
              NotificationSoundPlayer.resolveURL(option: .custom, customPath: "/tmp/definitely-not-here.wav") == nil)
        if let chimeURL {
            check("自定义存在的路径可解析",
                  NotificationSoundPlayer.resolveURL(option: .custom, customPath: chimeURL.path) == chimeURL)
        }

        print("\n== 音量映射（独立音量，0…1 夹取） ==")
        for (input, expected) in [(0.0, 0.0), (0.37, 0.37), (0.85, 0.85), (1.0, 1.0), (-0.5, 0.0), (1.7, 1.0)] {
            let clamped = Double(NotificationSoundPlayer.clampedVolume(input))
            check("volume(\(input)) = \(expected)", abs(clamped - expected) < 0.0001,
                  String(format: "%.3f", clamped))
        }
        if let chimeURL {
            let probe = NSSound(contentsOf: chimeURL, byReference: true)
            for level in [0.2, 0.5, 1.0] {
                probe?.volume = NotificationSoundPlayer.clampedVolume(level)
                let actual = Double(probe?.volume ?? -1)
                check("NSSound.volume 写入 \(level) 后读回一致", abs(actual - level) < 0.001,
                      String(format: "%.3f", actual))
            }
        }

        print("\n== 设置默认值与持久化 ==")
        let suiteName = "com.liyitong.dshstatus.selftest.\(getpid())"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
            // 触发旧域迁移时也拿走「旧域里没有的键」——新键不会被旧版本污染。
            let initial = AppSettings(persist: true, defaults: defaults)
            check("默认开启提示音", initial.soundEnabled)
            check("默认提示音 = DSH 提示音", initial.soundOption == .dshChime, initial.soundOption.rawValue)
            check("默认音量 = 90%", abs(initial.soundVolume - 0.9) < 0.0001,
                  String(format: "%.2f", initial.soundVolume))
            check("默认无自定义音频", initial.soundCustomPath.isEmpty)

            initial.soundEnabled = false
            initial.soundOption = .sosumi
            initial.soundVolume = 0.42
            initial.soundCustomPath = chimeURL?.path ?? "/tmp/x.wav"
            let restored = AppSettings(persist: true, defaults: defaults)
            check("开关持久化", restored.soundEnabled == false)
            check("声音选项持久化", restored.soundOption == .sosumi, restored.soundOption.rawValue)
            check("音量持久化", abs(restored.soundVolume - 0.42) < 0.0001,
                  String(format: "%.2f", restored.soundVolume))
            check("自定义路径持久化", restored.soundCustomPath == initial.soundCustomPath)

            defaults.set(1.7, forKey: "dshStatus.soundVolume")
            let clamped = AppSettings(persist: true, defaults: defaults)
            check("读取时音量夹取到 1.0", abs(clamped.soundVolume - 1.0) < 0.0001,
                  String(format: "%.2f", clamped.soundVolume))

            initial.reset()
            check("恢复默认后 = 打开 / DSH 提示音 / 90%",
                  initial.soundEnabled && initial.soundOption == .dshChime
                  && abs(initial.soundVolume - 0.9) < 0.0001 && initial.soundCustomPath.isEmpty)
            defaults.removePersistentDomain(forName: suiteName)
        } else {
            check("创建临时 UserDefaults 套件", false, suiteName)
        }

        print("")
        if failures == 0 {
            print("✅ 提示音自检全部通过")
            return 0
        }
        print("❌ 提示音自检失败 \(failures) 项")
        return 1
    }
}

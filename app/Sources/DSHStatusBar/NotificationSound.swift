import AppKit
import UserNotifications

// MARK: - 声音送达方式

/// 提示音的两种送达方式（设置页「提示音 → 播放方式」）。
///
/// - `app`：App 自己用 `NSSound` 播放——**独立音量**，不受系统「专注模式/勿扰」限制；
/// - `system`：交给系统通知（`UNNotificationSound`）播放——**跟随系统**：专注模式/勿扰会静音，
///   音量由系统「通知音量/提醒音量」决定；所选音色会复制到 `~/Library/Sounds` 供系统通知读取。
enum SoundDeliveryMode: String, CaseIterable, Identifiable {
    case app
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .app: return "App 直接播放（独立音量）"
        case .system: return "系统通知音（跟随专注模式）"
        }
    }

    var shortLabel: String {
        switch self {
        case .app: return "App 直接播放"
        case .system: return "系统通知音"
        }
    }
}

// MARK: - 提示音选项

/// 设置页「提示音 → 声音」的可选项。
///
/// 设计背景（用户反馈「系统默认提示音太不明显」）：
/// - 系统通知音无法由 App 调音量，系统音本身峰值也低（实测 Glass ≈0.20 / Hero ≈0.53）；
/// - 因此提示音默认改为 **App 自己播放**（`NSSound`），App 内独立音量、独立选音；
/// - 同时保留「系统通知音」送达方式（`SoundDeliveryMode.system`）：交给系统通知播放，
///   从而受系统「专注模式/勿扰」与通知音量管理，并可继续使用自定义音色。
/// - 默认使用随 App 打包的 `dsh-chime.wav`：三音上行琶音、峰值 0.92（约为系统 Glass 的 4.6 倍），
///   生成脚本见 `scripts/generate-dsh-chime.py`。
enum NotificationSoundOption: String, CaseIterable, Identifiable {
    /// 内置「DSH 提示音」：更响、更有辨识度（默认）。
    case dshChime
    /// 系统默认通知音（仅「系统通知音」送达方式下可选；App 直接播放无法取到系统默认音文件）。
    case systemDefault
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
        case .systemDefault: return "系统默认通知音"
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
    /// 内置音 / 系统默认 / 自定义 / 静音返回 nil。
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
        case .dshChime, .systemDefault, .custom, .none: return nil
        }
    }

    /// 设置项是否真的会发声（用于设置页禁用试听/音量控件）。
    var producesSound: Bool {
        self != .none
    }
}

// MARK: - 提示音播放器（App 直接播放）

/// App 内提示音播放器：解析音频文件 → `NSSound` 播放 → 独立音量。
///
/// 为什么不用 `UNNotificationSound`：它无法设置音量（由系统提醒音量决定），
/// 也不支持「系统通知关闭后仍提醒」，正是用户反馈「太不明显」的根因。
/// 需要「跟随系统专注模式」时改用 `SoundDeliveryMode.system`（见 `SystemNotificationSound`）。
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

    /// 选项 → 具体音频文件。`.none` / `.systemDefault`（无文件）/ 缺失的 `.custom` 返回 nil。
    static func resolveURL(option: NotificationSoundOption, customPath: String?) -> URL? {
        switch option {
        case .none, .systemDefault:
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
        guard option != .systemDefault else {
            lastError = "系统默认通知音只能通过系统通知播放"
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

// MARK: - 系统通知音（跟随系统专注模式）

/// 把所选音色交给 macOS 通知系统播放（`UNNotificationSound`）。
///
/// - 优点：跟随系统「专注模式/勿扰」与通知音量，用户不需要再单独管理；
/// - 代价：App 内音量滑杆不生效、系统通知权限关闭时不响；
/// - `UNNotificationSound(named:)` 只认 App bundle 与 `~/Library/Sounds`，
///   所以内置音 / 系统声音 / 自定义文件都先**复制**到 `~/Library/Sounds/dsh-status-*.ext` 再引用；
///   文件名带源文件大小/修改时间戳，改文件后自动重新落地，并清理旧版本文件。
enum SystemNotificationSound {
    /// 默认落地目录：`~/Library/Sounds`（macOS 通知声音的查找路径之一）。
    static var defaultStagingDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Sounds", isDirectory: true)
    }

    /// 选项 → `UNNotificationSound`；`.none` / 音源缺失时返回 nil（该条通知静音）。
    static func sound(option: NotificationSoundOption,
                      customPath: String?,
                      stagingDirectory: URL? = nil) -> UNNotificationSound? {
        switch option {
        case .none:
            return nil
        case .systemDefault:
            return .default
        case .dshChime, .glass, .hero, .ping, .sosumi, .submarine, .pop, .tink, .basso, .custom:
            guard let staged = stage(option: option,
                                     customPath: customPath,
                                     directory: stagingDirectory ?? defaultStagingDirectory) else {
                return nil
            }
            return UNNotificationSound(named: UNNotificationSoundName(staged.lastPathComponent))
        }
    }

    /// 把音源复制到 `directory`，返回可直接交给 `UNNotificationSound(named:)` 的文件 URL。
    /// 同一音源重复调用返回同一路径（幂等）；成功后清理该目录下其它 `dsh-status-*` 旧文件。
    static func stage(option: NotificationSoundOption,
                      customPath: String?,
                      directory: URL) -> URL? {
        guard let source = NotificationSoundPlayer.resolveURL(option: option, customPath: customPath) else {
            return nil
        }
        let fileExtension = source.pathExtension.isEmpty ? "aiff" : source.pathExtension
        let destination = directory.appendingPathComponent(
            "dsh-status-\(option.rawValue)-\(fileStamp(of: source)).\(fileExtension)")
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            pruneStaleFiles(in: directory, keeping: destination.lastPathComponent)
            let data = try Data(contentsOf: source)
            try data.write(to: destination, options: .atomic)
            return destination
        } catch {
            FileHandle.standardError.write(Data(
                "[dsh-status] 提示音落地失败（\(source.lastPathComponent) → \(directory.path)）：\(error)\n".utf8))
            return nil
        }
    }

    /// 源文件的「大小 + 修改时间」指纹，用于在文件变化后重新落地。
    private static func fileStamp(of url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = values?.fileSize ?? 0
        let modified = Int(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)
        return "\(size)-\(modified)"
    }

    /// 清理旧的落地文件，避免 `~/Library/Sounds` 越堆越多。
    private static func pruneStaleFiles(in directory: URL, keeping filename: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files
        where file.lastPathComponent.hasPrefix("dsh-status-")
            && file.lastPathComponent != filename {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// MARK: - 自检（--self-test-sound）

/// 无音频硬件依赖的自检：资源打包、选项解析、音量映射、两种送达方式、设置默认值与持久化。
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
        check("系统默认通知音无音频文件",
              NotificationSoundPlayer.resolveURL(option: .systemDefault, customPath: nil) == nil)
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

        print("\n== 系统通知音（跟随系统专注模式） ==")
        check("系统默认通知音可构造",
              SystemNotificationSound.sound(option: .systemDefault, customPath: nil) != nil)
        check("静音不产生通知声音",
              SystemNotificationSound.sound(option: .none, customPath: nil) == nil)
        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-status-sound-selftest-\(getpid())", isDirectory: true)
        try? FileManager.default.removeItem(at: stagingDir)
        defer { try? FileManager.default.removeItem(at: stagingDir) }
        var stagedChime: URL?
        for option in [NotificationSoundOption.dshChime, .glass] {
            guard let staged = SystemNotificationSound.stage(option: option,
                                                             customPath: nil,
                                                             directory: stagingDir) else {
                check("\(option.rawValue) 落地到 Library/Sounds", false)
                continue
            }
            check("\(option.rawValue) 落地到 Library/Sounds",
                  FileManager.default.fileExists(atPath: staged.path)
                  && staged.lastPathComponent.hasPrefix("dsh-status-\(option.rawValue)-"),
                  staged.lastPathComponent)
            if option == .dshChime { stagedChime = staged }
        }
        if let chimeURL {
            check("自定义音频落地到 Library/Sounds",
                  SystemNotificationSound.stage(option: .custom,
                                                customPath: chimeURL.path,
                                                directory: stagingDir) != nil)
        }
        if let stagedChime {
            check("同名音源重复落地幂等（同一路径）",
                  SystemNotificationSound.stage(option: .dshChime, customPath: nil,
                                                directory: stagingDir) == stagedChime)
        }
        if let systemSound = SystemNotificationSound.sound(option: .dshChime,
                                                           customPath: nil,
                                                           stagingDirectory: stagingDir) {
            check("系统音送达方式可构造 UNNotificationSound", systemSound !== UNNotificationSound.default,
                  "dshChime")
        } else {
            check("系统音送达方式可构造 UNNotificationSound", false)
        }
        if let chimeURL {
            let custom = SystemNotificationSound.sound(option: .custom,
                                                       customPath: chimeURL.path,
                                                       stagingDirectory: stagingDir)
            check("自定义音色可构造 UNNotificationSound（系统送达）", custom != nil)
        }

        print("\n== 设置默认值与持久化 ==")
        let suiteName = "com.liyitong.dshstatus.selftest.\(getpid())"
        if let defaults = UserDefaults(suiteName: suiteName) {
            defaults.removePersistentDomain(forName: suiteName)
            let initial = AppSettings(persist: true, defaults: defaults)
            check("默认开启提示音", initial.soundEnabled)
            check("默认送达方式 = App 直接播放", initial.soundDelivery == .app, initial.soundDelivery.rawValue)
            check("默认提示音 = DSH 提示音", initial.soundOption == .dshChime, initial.soundOption.rawValue)
            check("默认音量 = 90%", abs(initial.soundVolume - 0.9) < 0.0001,
                  String(format: "%.2f", initial.soundVolume))
            check("默认无自定义音频", initial.soundCustomPath.isEmpty)

            initial.soundEnabled = false
            initial.soundDelivery = .system
            initial.soundOption = .sosumi
            initial.soundVolume = 0.42
            initial.soundCustomPath = chimeURL?.path ?? "/tmp/x.wav"
            let restored = AppSettings(persist: true, defaults: defaults)
            check("开关持久化", restored.soundEnabled == false)
            check("送达方式持久化", restored.soundDelivery == .system, restored.soundDelivery.rawValue)
            check("声音选项持久化", restored.soundOption == .sosumi, restored.soundOption.rawValue)
            check("音量持久化", abs(restored.soundVolume - 0.42) < 0.0001,
                  String(format: "%.2f", restored.soundVolume))
            check("自定义路径持久化", restored.soundCustomPath == initial.soundCustomPath)

            restored.soundEnabled = true
            check("系统送达方式下不播放 App 内音频",
                  restored.playSound() == false)
            check("系统送达方式返回系统通知声音对象",
                  restored.systemNotificationSound(stagingDirectory: stagingDir) != nil)

            restored.soundDelivery = .app
            restored.soundOption = .systemDefault
            check("App 直接播放不返回系统通知声音对象",
                  restored.systemNotificationSound() == nil)

            defaults.set(1.7, forKey: "dshStatus.soundVolume")
            let clamped = AppSettings(persist: true, defaults: defaults)
            check("读取时音量夹取到 1.0", abs(clamped.soundVolume - 1.0) < 0.0001,
                  String(format: "%.2f", clamped.soundVolume))

            initial.reset()
            check("恢复默认后 = App 播放 / DSH 提示音 / 90%",
                  initial.soundEnabled && initial.soundDelivery == .app
                  && initial.soundOption == .dshChime
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

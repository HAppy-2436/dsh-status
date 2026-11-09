import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import UserNotifications

// MARK: - 设置模型

enum CenterNumberMode: String, CaseIterable, Identifiable {
    /// 全部非空闲任务（含运行中）——默认。
    case all
    /// 需要介入的数量（待回答 + 已停止 + 已完成）。
    case attention
    /// 与当前环颜色一致的那一类状态的数量。
    case matched
    case hidden

    var id: String { rawValue }

    /// 历史值 `nonIdle` 等价于 `all`。
    init(stored: String?) {
        switch stored {
        case "nonIdle": self = .all
        case CenterNumberMode.all.rawValue: self = .all
        case CenterNumberMode.attention.rawValue: self = .attention
        case CenterNumberMode.matched.rawValue: self = .matched
        case CenterNumberMode.hidden.rawValue: self = .hidden
        default: self = .all
        }
    }

    var label: String {
        switch self {
        case .all: return "全部任务数（含运行中）"
        case .attention: return "需要介入的数量"
        case .matched: return "与环颜色一致的数量"
        case .hidden: return "不显示数字"
        }
    }

    var shortLabel: String {
        switch self {
        case .all: return "全部任务"
        case .attention: return "需要介入"
        case .matched: return "与环色一致"
        case .hidden: return "不显示"
        }
    }
}

/// 应用图标样式（Dock / Finder / 系统通知横幅）。
enum AppIconStyle: String, CaseIterable, Identifiable {
    /// 品牌「双层环」（默认）。
    case brand
    /// DeepSeek 官方蓝色鲸鱼（经 MIT 许可的鲸鱼矢量路径，配色沿用官方主色）。
    case whale

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brand: return "品牌双层环（默认）"
        case .whale: return "DeepSeek 蓝色鲸鱼"
        }
    }
}

/// 菜单栏「空闲」（没有任何非空闲任务）时可以显示的品牌图标。
enum MenuBarIdleStyle: String, CaseIterable, Identifiable {
    /// DeepSeek 鲸鱼（默认；借助其 MIT 许可与出处声明）。
    case whale
    /// 「未连接」状态的单虚线圆环样式（复用同一绘制素材；中性、不与状态色环混淆）。
    case dashedRing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .whale: return "鲸鱼 Logo（默认）"
        case .dashedRing: return "虚线圆环（未连接样式）"
        }
    }

    /// 兼容 0.4.0 曾使用过的 `dashedDoubleRing` 存档值。
    init(storedValue: String?) {
        switch storedValue {
        case MenuBarIdleStyle.dashedRing.rawValue, "dashedDoubleRing": self = .dashedRing
        case MenuBarIdleStyle.whale.rawValue: self = .whale
        default: self = .whale
        }
    }
}

enum PanelBackgroundStyle: String, CaseIterable, Identifiable {
    case liquidGlass
    case classicMaterial
    case solid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .liquidGlass: return "液态玻璃"
        case .classicMaterial: return "经典磨砂"
        case .solid: return "实色"
        }
    }

    var available: Bool {
        if self == .liquidGlass {
            if #available(macOS 26.0, *) { return true }
            return false
        }
        return true
    }

    static var systemDefault: PanelBackgroundStyle {
        if #available(macOS 26.0, *) { return .liquidGlass }
        return .classicMaterial
    }

    static var availableStyles: [PanelBackgroundStyle] {
        allCases.filter(\.available)
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults?
    private let persist: Bool

    @Published var visibleStatuses: Set<SessionStatus> {
        didSet { save("visibleStatuses", visibleStatuses.map(\.rawValue)) }
    }
    @Published var hiddenWorkspaces: Set<String> {
        didSet { save("hiddenWorkspaces", Array(hiddenWorkspaces)) }
    }
    @Published var centerNumberMode: CenterNumberMode {
        didSet { save("centerNumberMode", centerNumberMode.rawValue) }
    }
    /// 菜单栏空闲时显示的品牌图标（默认鲸鱼；可选品牌虚线双环）。
    @Published var menuBarIdleStyle: MenuBarIdleStyle {
        didSet { save("menuBarIdleStyle", menuBarIdleStyle.rawValue) }
    }
    /// 应用图标（Dock / Finder / 系统通知）：品牌双层环或 DeepSeek 蓝色鲸鱼。
    @Published var appIconStyle: AppIconStyle {
        didSet { save("appIconStyle", appIconStyle.rawValue) }
    }
    @Published var runAnimation: Bool { didSet { save("runAnimation", runAnimation) } }
    @Published var transitionAnimation: Bool { didSet { save("transitionAnimation", transitionAnimation) } }
    @Published var notifyWaiting: Bool { didSet { save("notifyWaiting", notifyWaiting) } }
    @Published var notifyCompleted: Bool { didSet { save("notifyCompleted", notifyCompleted) } }
    @Published var notifyStopped: Bool { didSet { save("notifyStopped", notifyStopped) } }
    /// 勿扰：总开关式静音全部系统通知（保留上面三项单项设置）。
    @Published var doNotDisturb: Bool { didSet { save("doNotDisturb", doNotDisturb) } }
    @Published var confirmBeforeQuit: Bool { didSet { save("confirmBeforeQuit", confirmBeforeQuit) } }
    @Published var panelBackgroundStyle: PanelBackgroundStyle {
        didSet { save("panelBackgroundStyle", panelBackgroundStyle.rawValue) }
    }
    /// 有会话运行中时阻止 Mac 进入闲置睡眠（默认关；等价 `caffeinate -i`）。
    @Published var preventSleepWhileRunning: Bool {
        didSet { save("preventSleepWhileRunning", preventSleepWhileRunning) }
    }

    // MARK: 提示音（App 内独立播放，音量与系统通知音量无关）

    /// 提示音总开关：关闭后状态变化只发系统通知横幅、不发声。
    @Published var soundEnabled: Bool { didSet { save("soundEnabled", soundEnabled) } }
    /// 提示音送达方式：App 直接播放（独立音量，不受专注模式限制）或系统通知音（跟随系统专注模式/通知音量）。
    @Published var soundDelivery: SoundDeliveryMode {
        didSet { save("soundDelivery", soundDelivery.rawValue) }
    }
    /// 提示音音色（内置 DSH 提示音 / macOS 系统声音 / 自定义文件 / 静音）。
    @Published var soundOption: NotificationSoundOption {
        didSet { save("soundOption", soundOption.rawValue) }
    }
    /// App 内独立音量（0…1）；与系统通知音量 / 提醒音量无关，仍受系统总输出音量限制。
    /// 范围由 Slider（0...1）与播放器（`clampedVolume`）保证，读取时在 init 里夹取；
    /// didSet 内不写回自身，避免 `@Published` 包装器重入。
    @Published var soundVolume: Double { didSet { save("soundVolume", soundVolume) } }
    /// 自定义音频文件的绝对路径（`soundOption == .custom` 时使用）。
    @Published var soundCustomPath: String { didSet { save("soundCustomPath", soundCustomPath) } }

    private static let legacyDefaultsDomains = [
        "com.liyitong.dshstatus", "com.liyitong.dshstatus.app",
        "com.liyitong.dshstatus.path", "com.liyitong.dsh-status"
    ]

    /// 首次以新 bundle id 启动时，把旧域的设置搬过来（通知图标缓存按 bundle id 绑定，
    /// 换 id 才能让系统重新解析通知图标）。
    private static func migrateLegacyDefaultsIfNeeded(into defaults: UserDefaults) {
        guard defaults.object(forKey: "dshStatus.centerNumberMode") == nil else { return }
        guard let bundleId = Bundle.main.bundleIdentifier,
              !legacyDefaultsDomains.contains(bundleId) else { return }
        for domain in legacyDefaultsDomains {
            guard let legacy = UserDefaults(suiteName: domain),
                  legacy.object(forKey: "dshStatus.centerNumberMode") != nil else { continue }
            for key in ["visibleStatuses", "hiddenWorkspaces", "centerNumberMode", "runAnimation", "transitionAnimation", "soundDelivery",
                        "notifyWaiting", "notifyCompleted", "notifyStopped", "doNotDisturb", "confirmBeforeQuit",
                        "panelBackgroundStyle", "soundEnabled", "soundOption", "soundVolume", "soundCustomPath",
                        "preventSleepWhileRunning", "menuBarIdleStyle", "appIconStyle"] {
                if let value = legacy.object(forKey: "dshStatus.\(key)") {
                    defaults.set(value, forKey: "dshStatus.\(key)")
                }
            }
            return
        }
    }

    init(persist: Bool = true, defaults: UserDefaults = .standard) {
        self.persist = persist
        self.defaults = persist ? defaults : nil
        if persist { AppSettings.migrateLegacyDefaultsIfNeeded(into: defaults) }
        // 预览/演示（persist == false）不读真实用户设置：离屏出图必须可复现，不受本机配置影响。
        let store: UserDefaults? = persist ? defaults : nil
        let storedStatuses = store?.stringArray(forKey: "dshStatus.visibleStatuses")
        let statuses = storedStatuses?.compactMap { SessionStatus(rawValue: $0) } ?? []
        visibleStatuses = Set(statuses.isEmpty ? SessionStatus.allCases.filter { $0 != .idle } : statuses)
        hiddenWorkspaces = Set(store?.stringArray(forKey: "dshStatus.hiddenWorkspaces") ?? [])
        var storedCenterMode = CenterNumberMode(stored: store?.string(forKey: "dshStatus.centerNumberMode"))
        if persist, defaults.object(forKey: "dshStatus.centerNumberModeVersion") == nil {
            // 旧版默认是「关注数」，新版默认「全部任务数」；只有「不显示」视为用户明确选择
            if storedCenterMode != .hidden { storedCenterMode = .all }
            defaults.set(2, forKey: "dshStatus.centerNumberModeVersion")
        }
        centerNumberMode = storedCenterMode
        menuBarIdleStyle = MenuBarIdleStyle(storedValue: store?.string(forKey: "dshStatus.menuBarIdleStyle"))
        appIconStyle = AppIconStyle(rawValue: store?.string(forKey: "dshStatus.appIconStyle") ?? "") ?? .brand
        runAnimation = store?.object(forKey: "dshStatus.runAnimation") as? Bool ?? true
        transitionAnimation = store?.object(forKey: "dshStatus.transitionAnimation") as? Bool ?? true
        notifyWaiting = store?.object(forKey: "dshStatus.notifyWaiting") as? Bool ?? true
        notifyCompleted = store?.object(forKey: "dshStatus.notifyCompleted") as? Bool ?? false
        notifyStopped = store?.object(forKey: "dshStatus.notifyStopped") as? Bool ?? false
        doNotDisturb = store?.object(forKey: "dshStatus.doNotDisturb") as? Bool ?? false
        confirmBeforeQuit = store?.object(forKey: "dshStatus.confirmBeforeQuit") as? Bool ?? true
        let storedPanel = PanelBackgroundStyle(rawValue: store?.string(forKey: "dshStatus.panelBackgroundStyle") ?? "")
        panelBackgroundStyle = storedPanel ?? PanelBackgroundStyle.systemDefault

        soundEnabled = store?.object(forKey: "dshStatus.soundEnabled") as? Bool ?? true
        soundOption = NotificationSoundOption(rawValue: store?.string(forKey: "dshStatus.soundOption") ?? "") ?? .dshChime
        soundDelivery = SoundDeliveryMode(rawValue: store?.string(forKey: "dshStatus.soundDelivery") ?? "") ?? .app
        let storedVolume = store?.object(forKey: "dshStatus.soundVolume") as? Double
        soundVolume = min(max(storedVolume ?? 0.9, 0), 1)
        soundCustomPath = store?.string(forKey: "dshStatus.soundCustomPath") ?? ""
        preventSleepWhileRunning = store?.object(forKey: "dshStatus.preventSleepWhileRunning") as? Bool ?? false
    }

    /// 预览/演示用：不落盘，也不读取本机真实设置（离屏出图可复现）。
    static func preview() -> AppSettings {
        AppSettings(persist: false)
    }

    func reset() {
        visibleStatuses = Set(SessionStatus.allCases.filter { $0 != .idle })
        hiddenWorkspaces = []
        centerNumberMode = .all
        menuBarIdleStyle = .whale
        appIconStyle = .brand
        runAnimation = true
        transitionAnimation = true
        notifyWaiting = true
        notifyCompleted = false
        notifyStopped = false
        doNotDisturb = false
        confirmBeforeQuit = true
        panelBackgroundStyle = PanelBackgroundStyle.systemDefault
        soundEnabled = true
        soundDelivery = .app
        soundOption = .dshChime
        soundVolume = 0.9
        soundCustomPath = ""
        preventSleepWhileRunning = false
    }

    /// 当前自定义音频文件 URL（未选择 / 路径为空时为 nil）。
    var soundCustomURL: URL? {
        let path = soundCustomPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }

    /// 用当前设置播放一次提示音（设置页「试听」与状态跃迁共用）。
    /// 仅「App 直接播放」送达方式生效；「系统通知音」由通知本身携带声音（见 `systemNotificationSound`）。
    @discardableResult
    func playSound() -> Bool {
        guard soundEnabled, soundDelivery == .app else { return false }
        return NotificationSoundPlayer.shared.play(option: soundOption,
                                                   volume: soundVolume,
                                                   customPath: soundCustomPath)
    }

    /// 系统通知音送达方式下交给 `UNNotificationSound` 的声音；App 直接播放模式返回 nil。
    /// - Parameter stagingDirectory: 落地目录（默认 `~/Library/Sounds`；自检传临时目录用）。
    func systemNotificationSound(stagingDirectory: URL? = nil) -> UNNotificationSound? {
        guard soundEnabled, soundDelivery == .system else { return nil }
        return SystemNotificationSound.sound(option: soundOption,
                                             customPath: soundCustomPath,
                                             stagingDirectory: stagingDirectory)
    }

    /// 某状态是否在面板/图标中显示。
    func shows(_ status: SessionStatus) -> Bool {
        status == .idle ? false : visibleStatuses.contains(status)
    }

    /// 某会话是否在面板/图标中显示（状态 + 隐藏项目）。
    func isVisible(_ row: SessionRow) -> Bool {
        guard shows(row.statusKind) else { return false }
        if let workspaceId = row.workspaceId, hiddenWorkspaces.contains(workspaceId) { return false }
        return true
    }

    private func save(_ key: String, _ value: Any) {
        guard persist else { return }
        defaults?.set(value, forKey: "dshStatus.\(key)")
    }
}

// MARK: - 设置页（原生 grouped Form）

/// 设置页：macOS System Settings 风格的单页 grouped Form（见 docs/ui-redesign-spec.md §3）。
///
/// 卡片背景、圆角、分隔线、分区标题与行内边距全部交给系统 `Form`；
/// 这里只负责「22pt 图标块 + 13pt 标题 + 11pt 副标题 + 原生控件」的行内容与分区顺序。
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
    /// 「试听」回调（由设置窗口注入；nil 时退化为 App 内播放）。
    var onPreviewSound: (() -> Void)? = nil
    /// 登录项状态以系统 `SMAppService` 为准（见 LaunchAtLogin.swift）。
    @StateObject private var launchAtLogin = LaunchAtLoginController()
    /// 应用图标（Dock / Finder / 通知）切换（见 AppIconController.swift）。
    @ObservedObject private var appIcon = AppIconController.shared

    private let statuses: [SessionStatus] = [.waiting, .running, .completed, .stopped]

    var body: some View {
        Form {
            menuBarSection
            displaySection
            projectSection
            notificationSection
            soundSection
            panelSection
            backgroundSection
            generalSection
            aboutSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.settingsContentBackground)
        .onAppear { launchAtLogin.refresh() }
    }

    // MARK: 菜单栏图标

    private var menuBarSection: some View {
        Section {
            SettingsRow(symbol: "number.circle.fill",
                        color: Theme.uiNSColor(.running),
                        title: "中心数字") {
                Picker("中心数字", selection: $settings.centerNumberMode) {
                    ForEach(CenterNumberMode.allCases) { mode in
                        Text(mode.shortLabel).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            SettingsRow(symbol: "circle.circle",
                        color: Theme.uiNSColor(.completed),
                        title: "空闲时图标",
                        subtitle: "没有任务时菜单栏显示鲸鱼，或「未连接」样式的虚线圆环") {
                Picker("空闲时图标", selection: $settings.menuBarIdleStyle) {
                    ForEach(MenuBarIdleStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            SettingsRow(symbol: "circle.dashed",
                        color: Theme.uiNSColor(.completed),
                        title: "状态切换动效",
                        subtitle: "状态变化时内容淡化、外环扫入、数字滚动") {
                Toggle("状态切换动效", isOn: $settings.transitionAnimation)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(symbol: "arrow.triangle.2.circlepath",
                        color: Theme.uiNSColor(.running),
                        title: "播放运行动画",
                        subtitle: "关闭可省电；低电量或「减弱动态效果」时自动关闭") {
                Toggle("播放运行动画", isOn: $settings.runAnimation)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        } header: {
            Text("菜单栏图标")
        } footer: {
            SettingsFootnote("中心数字：全部任务包含运行中；需要介入 = 待回答 + 已停止 + 已完成；与环色一致 = 只统计外环颜色对应状态的数量。")
        }
    }

    // MARK: 显示

    private var displaySection: some View {
        Section {
            ForEach(statuses, id: \.self) { status in
                SettingsRow(symbol: statusSymbol(status),
                            color: Theme.uiNSColor(status),
                            title: status.label,
                            subtitle: "当前 \(count(status)) 个") {
                    Toggle(status.label, isOn: binding(for: status))
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        } header: {
            Text("显示")
        } footer: {
            SettingsFootnote("关闭后该状态既不出现在面板中，也不计入菜单栏数字与外环。")
        }
    }

    // MARK: 项目显示

    private var projectSection: some View {
        let workspaces = workspaceRows()
        return Section {
            if workspaces.isEmpty {
                Text("暂无已知项目（连接 DSH 后出现）")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowBackground(Theme.settingsCardBackground)
            } else {
                ForEach(workspaces) { workspace in
                    SettingsRow(symbol: "folder.fill",
                                color: .systemBlue,
                                title: workspace.title,
                                subtitle: "\(workspace.count) 个会话") {
                        Toggle(workspace.title, isOn: binding(workspaceId: workspace.id))
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }
            }
        } header: {
            Text("项目显示")
        } footer: {
            if !workspaces.isEmpty {
                SettingsFootnote("关闭开关只会把这个项目的会话从面板中隐藏，不影响会话本身。")
            }
        }
    }

    // MARK: 通知

    private var notificationSection: some View {
        Section {
            SettingsRow(symbol: notificationSymbol,
                        color: notificationColor,
                        title: "系统通知",
                        subtitle: notificationSubtitle) {
                notificationAction
            }
            SettingsRow(symbol: settings.doNotDisturb ? "moon.fill" : "moon",
                        color: .systemIndigo,
                        title: "勿扰模式",
                        subtitle: "关闭全部系统通知与提示音；下面的单项开关会保留") {
                Toggle("勿扰模式", isOn: $settings.doNotDisturb)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(symbol: "bell.badge.fill",
                        color: Theme.uiNSColor(.waiting),
                        title: "待回答（推荐）") {
                Toggle("待回答", isOn: $settings.notifyWaiting)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(symbol: "checkmark.circle.fill",
                        color: Theme.uiNSColor(.completed),
                        title: "已完成") {
                Toggle("已完成", isOn: $settings.notifyCompleted)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(symbol: "stop.circle.fill",
                        color: Theme.uiNSColor(.stopped),
                        title: "已停止") {
                Toggle("已停止", isOn: $settings.notifyStopped)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        } header: {
            Text("通知")
        } footer: {
            SettingsFootnote("点击通知会打开对应会话；同一会话的横幅提醒 30 秒内不重复（提示音每次状态跃迁都会响）。上面三个状态开关同时决定是否弹横幅与是否播放提示音（声音在下方「提示音」分区单独配置）。勿扰模式开启时通知与提示音全部静音。")
        }
    }

    // MARK: 提示音

    private var soundSection: some View {
        Section {
            SettingsRow(symbol: settings.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                        color: .systemOrange,
                        title: "播放提示音",
                        subtitle: "状态变化时提醒；可选择 App 直接播放或走系统通知音") {
                Toggle("播放提示音", isOn: $settings.soundEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(symbol: "arrow.triangle.swap",
                        color: .systemBlue,
                        title: "播放方式",
                        subtitle: deliverySubtitle) {
                Picker("播放方式", selection: soundDeliveryBinding) {
                    ForEach(SoundDeliveryMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!settings.soundEnabled)
            }
            SettingsRow(symbol: "music.note",
                        color: .systemPink,
                        title: "声音") {
                HStack(spacing: 8) {
                    Picker("声音", selection: soundOptionBinding) {
                        ForEach(availableSoundOptions) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .disabled(!settings.soundEnabled)

                    Button("试听") { previewSound() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!canPreviewSound)
                }
            }
            SettingsRow(symbol: "speaker.wave.1.fill",
                        color: .systemTeal,
                        title: "音量",
                        subtitle: volumeSubtitle) {
                HStack(spacing: 8) {
                    Slider(value: $settings.soundVolume, in: 0...1)
                        .frame(width: 150)
                        .accessibilityLabel("提示音音量")
                    Text(settings.soundDelivery == .app ? "\(volumePercent)%" : "系统")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .disabled(!settings.soundEnabled || settings.soundOption == .none || settings.soundDelivery == .system)
            }
            if settings.soundOption == .custom {
                SettingsRow(symbol: "waveform",
                            color: .systemGray,
                            title: "自定义音频",
                            subtitle: customSoundSubtitle) {
                    Button(settings.soundCustomPath.isEmpty ? "选择文件…" : "重新选择…") {
                        chooseCustomSoundFile()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!settings.soundEnabled)
                }
            }
        } header: {
            Text("提示音")
        } footer: {
            SettingsFootnote("「App 直接播放」由 App 直接发声：独立音量，不受系统「专注模式/勿扰」限制；「系统通知音」随系统通知播放：专注模式/勿扰会静音，音量由系统通知音量控制（所选音色会复制到 ~/Library/Sounds 供系统读取）。两种方式都受本页总开关与「勿扰模式」控制。注意：App 内音量是相对系统输出音量的比例——系统总音量越低最终越小声，系统静音时两种方式都不会响。")
        }
    }

    private var volumePercent: Int {
        Int((settings.soundVolume * 100).rounded())
    }

    private var canPreviewSound: Bool {
        guard settings.soundEnabled, settings.soundOption.producesSound else { return false }
        if settings.soundOption == .custom {
            guard let url = settings.soundCustomURL else { return false }
            return FileManager.default.fileExists(atPath: url.path)
        }
        return true
    }

    private var customSoundSubtitle: String {
        guard let url = settings.soundCustomURL else {
            return "支持 WAV / AIFF / MP3 / M4A / CAF"
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            return "\(url.lastPathComponent)（文件不存在，请重新选择）"
        }
        return url.lastPathComponent
    }

    /// 当前送达方式下可选的声音（「系统默认通知音」只有系统通知音通道能播放）。
    private var availableSoundOptions: [NotificationSoundOption] {
        NotificationSoundOption.allCases.filter { option in
            option != .systemDefault || settings.soundDelivery == .system
        }
    }

    private var deliverySubtitle: String {
        switch settings.soundDelivery {
        case .app: return "独立音量；不受系统「专注模式/勿扰」限制"
        case .system: return "专注模式/勿扰会静音，音量由系统控制"
        }
    }

    private var volumeSubtitle: String {
        settings.soundDelivery == .app ? "独立于系统通知音量" : "系统模式下由系统通知音量控制"
    }

    /// 播放方式 Picker 的绑定：切回 App 播放时，把只属于系统通道的「系统默认通知音」换掉。
    private var soundDeliveryBinding: Binding<SoundDeliveryMode> {
        Binding(
            get: { settings.soundDelivery },
            set: { newValue in
                settings.soundDelivery = newValue
                if newValue == .app, settings.soundOption == .systemDefault {
                    settings.soundOption = .dshChime
                }
            }
        )
    }

    /// 声音 Picker 的绑定：选到「自定义音频文件…」且还没有文件时直接弹选择框，
    /// 取消则退回上一个选项（避免停在「自定义但没选文件」的半残状态）。
    private var soundOptionBinding: Binding<NotificationSoundOption> {
        Binding(
            get: { settings.soundOption },
            set: { newValue in
                let previous = settings.soundOption
                settings.soundOption = newValue
                guard newValue == .custom, settings.soundCustomPath.isEmpty else { return }
                DispatchQueue.main.async {
                    if !chooseCustomSoundFile() { settings.soundOption = previous }
                }
            }
        )
    }

    private func previewSound() {
        if let onPreviewSound {
            onPreviewSound()
        } else {
            settings.playSound()
        }
    }

    /// 选择自定义提示音：写入路径后立即试听，方便判断音量/音色是否合适。
    /// - Returns: 用户是否选定了文件（取消/关闭面板返回 false）。
    @discardableResult
    private func chooseCustomSoundFile() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "选择提示音音频文件"
        panel.message = "支持 WAV / AIFF / MP3 / M4A / CAF 等系统可解码的音频格式。"
        panel.prompt = "选择"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        settings.soundEnabled = true
        settings.soundOption = .custom
        settings.soundCustomPath = url.path
        previewSound()
        return true
    }

    // MARK: 面板

    private var panelSection: some View {
        Section {
            SettingsRow(symbol: "rectangle.on.rectangle",
                        color: .systemGray,
                        title: "材质") {
                Picker("材质", selection: $settings.panelBackgroundStyle) {
                    ForEach(PanelBackgroundStyle.availableStyles) { style in
                        Text(style.label).tag(style)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        } header: {
            Text("面板")
        } footer: {
            SettingsFootnote("「液态玻璃」需要 macOS 26 或更高版本；开启系统「降低透明度」时自动使用实色。")
        }
    }

    // MARK: 后台

    private var backgroundSection: some View {
        Section {
            SettingsRow(symbol: "arrow.up.forward.app.fill",
                        color: .systemBlue,
                        title: "登录时自动启动",
                        subtitle: launchAtLogin.detailText) {
                Toggle("登录时自动启动", isOn: Binding(
                    get: { launchAtLogin.isOn },
                    set: { launchAtLogin.setEnabled($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if case .requiresApproval = launchAtLogin.state {
                SettingsRow(symbol: "checkmark.shield.fill",
                            color: .systemOrange,
                            title: "允许登录项",
                            subtitle: "系统需要你在登录项列表中确认一次") {
                    Button("打开系统设置") { launchAtLogin.openLoginItemsSettings() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            SettingsRow(symbol: "moon.zzz.fill",
                        color: .systemIndigo,
                        title: "运行时阻止睡眠",
                        subtitle: model.sleepPrevented
                            ? "当前已阻止闲置睡眠（屏幕仍可关闭）"
                            : "有会话运行中时，阻止 Mac 进入闲置睡眠") {
                Toggle("运行时阻止睡眠", isOn: $settings.preventSleepWhileRunning)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        } header: {
            Text("后台")
        } footer: {
            SettingsFootnote("「登录时自动启动」由 macOS 登录项管理（可在「系统设置 → 通用 → 登录项」查看）。\n「运行时阻止睡眠」仅阻止「闲置系统睡眠」（等价 caffeinate -i）：屏幕仍可关闭，合盖与手动睡眠不受影响。需要 DSH Status App 保持运行；断线或会话全部结束后自动释放。")
        }
    }

    // MARK: 通用

    private var generalSection: some View {
        Section {
            SettingsRow(symbol: "app.badge.fill",
                        color: .systemBlue,
                        title: "应用图标",
                        subtitle: appIcon.needsRestart
                            ? "已切换；重启 App 后 Finder / 系统通知图标生效"
                            : (appIcon.message ?? "影响 Dock、Finder 与系统通知横幅的图标")) {
                HStack(spacing: 8) {
                    Picker("应用图标", selection: Binding(
                        get: { appIcon.style },
                        set: { appIcon.apply($0) }
                    )) {
                        ForEach(AppIconStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    if appIcon.needsRestart {
                        Button("重启 App") { appIcon.relaunch() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            SettingsRow(symbol: "power",
                        color: .systemGray,
                        title: "退出前确认",
                        subtitle: "点面板电源键或菜单「退出」时先弹确认框") {
                Toggle("退出前确认", isOn: $settings.confirmBeforeQuit)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            SettingsRow(symbol: "arrow.counterclockwise",
                        color: .systemOrange,
                        title: "恢复默认设置",
                        subtitle: "把所有选项恢复为推荐值") {
                Button("恢复所有设置…") { confirmReset() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } header: {
            Text("通用")
        }
    }

    // MARK: 关于（脚注）

    private var aboutSection: some View {
        Section {
        } footer: {
            Text("DSH Status v\(AppConfig.appVersion) · \(model.connected ? "已连接到 DSH" : "未连接")")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
        }
    }

    // MARK: 通知状态展示

    @ViewBuilder
    private var notificationAction: some View {
        switch model.notificationPermission {
        case .authorized:
            Text("已开启")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .denied:
            Button("打开系统设置") { model.onOpenNotificationSettings?() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .notDetermined:
            Button("允许通知") { model.onRequestNotificationPermission?() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        case .unknown:
            EmptyView()
        }
    }

    private var notificationSymbol: String {
        switch model.notificationPermission {
        case .authorized, .notDetermined: return "bell.fill"
        case .denied: return "bell.slash.fill"
        case .unknown: return "bell"
        }
    }

    private var notificationColor: NSColor {
        switch model.notificationPermission {
        case .authorized: return .systemGreen
        case .denied: return .systemRed
        case .notDetermined: return .systemYellow
        case .unknown: return .systemGray
        }
    }

    private var notificationSubtitle: String? {
        switch model.notificationPermission {
        case .authorized: return "任务状态变化时提醒"
        case .denied: return "被系统关闭，不会弹出任何提醒"
        case .notDetermined: return "尚未授权，不会弹出提醒"
        case .unknown: return "暂时无法读取通知授权状态"
        }
    }

    // MARK: 恢复默认（二次确认）

    private func confirmReset() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "恢复所有设置？"
        alert.informativeText = "所有选项将恢复为推荐默认值，已隐藏的状态和项目也会重置。此操作不可撤销。"
        alert.addButton(withTitle: "恢复所有设置")
        alert.addButton(withTitle: "取消")

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn { settings.reset() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            settings.reset()
        }
    }

    // MARK: 数据与绑定

    private func statusSymbol(_ status: SessionStatus) -> String {
        switch status {
        case .waiting: return "questionmark.circle.fill"
        case .running: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .idle: return "circle"
        }
    }

    private func binding(for status: SessionStatus) -> Binding<Bool> {
        Binding(
            get: { settings.visibleStatuses.contains(status) },
            set: { visible in
                if visible { settings.visibleStatuses.insert(status) }
                else { settings.visibleStatuses.remove(status) }
            }
        )
    }

    private func binding(workspaceId: String) -> Binding<Bool> {
        Binding(
            get: { !settings.hiddenWorkspaces.contains(workspaceId) },
            set: { shown in
                if shown { settings.hiddenWorkspaces.remove(workspaceId) }
                else { settings.hiddenWorkspaces.insert(workspaceId) }
            }
        )
    }

    private struct WorkspaceRow: Identifiable {
        let id: String
        let title: String
        let count: Int
    }

    private func workspaceRows() -> [WorkspaceRow] {
        var byId: [String: (title: String, count: Int)] = [:]
        for row in model.state.sessions where row.statusKind != .idle {
            guard let id = row.workspaceId else { continue }
            var entry = byId[id] ?? (row.workspaceTitle ?? "未分组", 0)
            entry.count += 1
            byId[id] = entry
        }
        return byId
            .map { WorkspaceRow(id: $0.key, title: $0.value.title, count: $0.value.count) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    private func count(_ status: SessionStatus) -> Int {
        model.state.sessions.filter { $0.statusKind == status }.count
    }
}

// MARK: - 行组件（System Settings 风格）

/// 22×22 continuous 圆角色块 + 白色 SF Symbol 12pt semibold。
private struct SettingsIconBlock: View {
    let symbol: String
    let color: NSColor

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.Metrics.settingsIconCorner, style: .continuous)
            .fill(Theme.iconBlockGradient(color))
            .frame(width: Theme.Metrics.settingsIconSize,
                   height: Theme.Metrics.settingsIconSize)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// 设置行：图标块 + 13pt 标题（可选 11pt 副标题）+ Spacer + 原生控件。
private struct SettingsRow<Trailing: View>: View {
    let symbol: String
    let color: NSColor
    let title: String
    let subtitle: String?
    let trailing: Trailing

    init(symbol: String,
         color: NSColor,
         title: String,
         subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing) {
        self.symbol = symbol
        self.color = color
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingsIconBlock(symbol: symbol, color: color)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Theme.settingsCardBackground)
    }
}

/// 分区脚注：11pt secondary、左对齐；不居中、不随 Form 默认排版漂移。
private struct SettingsFootnote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

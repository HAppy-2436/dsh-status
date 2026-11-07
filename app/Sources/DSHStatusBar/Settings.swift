import AppKit
import SwiftUI
import Combine

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
            for key in ["visibleStatuses", "hiddenWorkspaces", "centerNumberMode", "runAnimation", "transitionAnimation",
                        "notifyWaiting", "notifyCompleted", "notifyStopped", "doNotDisturb", "confirmBeforeQuit",
                        "panelBackgroundStyle"] {
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
        let storedStatuses = defaults.stringArray(forKey: "dshStatus.visibleStatuses")
        let statuses = storedStatuses?.compactMap { SessionStatus(rawValue: $0) } ?? []
        visibleStatuses = Set(statuses.isEmpty ? SessionStatus.allCases.filter { $0 != .idle } : statuses)
        hiddenWorkspaces = Set(defaults.stringArray(forKey: "dshStatus.hiddenWorkspaces") ?? [])
        var storedCenterMode = CenterNumberMode(stored: defaults.string(forKey: "dshStatus.centerNumberMode"))
        if persist, defaults.object(forKey: "dshStatus.centerNumberModeVersion") == nil {
            // 旧版默认是「关注数」，新版默认「全部任务数」；只有「不显示」视为用户明确选择
            if storedCenterMode != .hidden { storedCenterMode = .all }
            defaults.set(2, forKey: "dshStatus.centerNumberModeVersion")
        }
        centerNumberMode = storedCenterMode
        runAnimation = defaults.object(forKey: "dshStatus.runAnimation") as? Bool ?? true
        transitionAnimation = defaults.object(forKey: "dshStatus.transitionAnimation") as? Bool ?? true
        notifyWaiting = defaults.object(forKey: "dshStatus.notifyWaiting") as? Bool ?? true
        notifyCompleted = defaults.object(forKey: "dshStatus.notifyCompleted") as? Bool ?? false
        notifyStopped = defaults.object(forKey: "dshStatus.notifyStopped") as? Bool ?? false
        doNotDisturb = defaults.object(forKey: "dshStatus.doNotDisturb") as? Bool ?? false
        confirmBeforeQuit = defaults.object(forKey: "dshStatus.confirmBeforeQuit") as? Bool ?? true
        let storedPanel = PanelBackgroundStyle(rawValue: defaults.string(forKey: "dshStatus.panelBackgroundStyle") ?? "")
        panelBackgroundStyle = storedPanel ?? PanelBackgroundStyle.systemDefault
    }

    /// 预览/演示用：不落盘。
    static func preview() -> AppSettings {
        AppSettings(persist: false)
    }

    func reset() {
        visibleStatuses = Set(SessionStatus.allCases.filter { $0 != .idle })
        hiddenWorkspaces = []
        centerNumberMode = .all
        runAnimation = true
        transitionAnimation = true
        notifyWaiting = true
        notifyCompleted = false
        notifyStopped = false
        doNotDisturb = false
        confirmBeforeQuit = true
        panelBackgroundStyle = PanelBackgroundStyle.systemDefault
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

    private let statuses: [SessionStatus] = [.waiting, .running, .completed, .stopped]

    var body: some View {
        Form {
            menuBarSection
            displaySection
            projectSection
            notificationSection
            panelSection
            generalSection
            aboutSection
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.settingsContentBackground)
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
                        subtitle: "关闭全部系统通知；下面的单项开关会保留") {
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
            SettingsFootnote("点击通知会打开对应会话；同一会话 30 秒内不重复提醒。勿扰模式开启时以上所有通知都不弹（单项设置保留）。")
        }
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

    // MARK: 通用

    private var generalSection: some View {
        Section {
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

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
                        "notifyWaiting", "notifyCompleted", "notifyStopped", "confirmBeforeQuit",
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

// MARK: - 设置窗口

final class SettingsWindowController {
    private let settings: AppSettings
    private let model: AppModel
    private var window: NSWindow?

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
    }

    func show() {
        if window == nil {
            let view = SettingsView(settings: settings, model: model)
            let hosting = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: hosting)
            window.title = "DSH Status 设置"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 470, height: 780))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 设置页视觉组件（参考 Status Trio / macOS 系统设置）

private enum SettingsMetrics {
    static let pageMargin: CGFloat = 14
    static let groupSpacing: CGFloat = 12
    static let cardCorner: CGFloat = 10
    static let rowPaddingH: CGFloat = 14
    static let rowPaddingV: CGFloat = 6
    static let iconSize: CGFloat = 26
    static let iconCorner: CGFloat = 6.5
    static let dividerInset: CGFloat = rowPaddingH + iconSize + 12
}

private struct SettingsGroup<Content: View>: View {
    var title: String
    var footnote: String? = nil
    @ViewBuilder let content: Content

    init(_ title: String, footnote: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.cardCorner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
                    .padding(.top, 1)
            }
        }
    }
}

private struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        RoundedRectangle(cornerRadius: SettingsMetrics.iconCorner, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.98), tint.opacity(0.72)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(width: SettingsMetrics.iconSize, height: SettingsMetrics.iconSize)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: SettingsMetrics.iconSize * 0.52, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}

private struct SettingsRowChrome<Content: View>: View {
    var showDivider: Bool = true
    @ViewBuilder let content: Content

    init(showDivider: Bool = true, @ViewBuilder content: () -> Content) {
        self.showDivider = showDivider
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, SettingsMetrics.rowPaddingH)
            .padding(.vertical, SettingsMetrics.rowPaddingV)
            .overlay(alignment: .bottom) {
                if showDivider {
                    Divider().padding(.leading, SettingsMetrics.dividerInset)
                }
            }
    }
}

private struct SettingsToggleRow: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool
    var showDivider: Bool = true

    var body: some View {
        SettingsRowChrome(showDivider: showDivider) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }
}

private struct SettingsMenuRow<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let trailing: Trailing
    var showDivider: Bool = true

    var body: some View {
        SettingsRowChrome(showDivider: showDivider) {
            HStack(spacing: 10) {
                SettingsIcon(symbol: symbol, tint: tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 13))
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                trailing
            }
        }
    }
}

// MARK: - 设置页

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private let statuses: [SessionStatus] = [.waiting, .running, .completed, .stopped]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
                    displaySettings
                    iconSettings
                    panelSettings
                    notificationSettings
                    projectSettings
                }
                .padding(SettingsMetrics.pageMargin)
            }
            Divider()
            footerBar
        }
        .frame(width: 470, height: 780)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 分组

    private var displaySettings: some View {
        SettingsGroup("显示状态",
                      footnote: "隐藏的状态既不在面板里出现，也不计入菜单栏圆环与数字。") {
            ForEach(Array(statuses.enumerated()), id: \.element) { index, status in
                SettingsToggleRow(
                    symbol: statusSymbol(status),
                    tint: Theme.statusColor(status, scheme: colorScheme),
                    title: status.label,
                    subtitle: "\(count(status)) 个",
                    isOn: binding(for: status),
                    showDivider: index < statuses.count - 1
                )
            }
        }
    }

    @ViewBuilder
    private var projectSettings: some View {
        let workspaces = workspaceRows()
        SettingsGroup("项目显示",
                      footnote: workspaces.isEmpty ? nil : "关闭开关即隐藏该项目；会话本身不受影响。") {
            if workspaces.isEmpty {
                SettingsRowChrome(showDivider: false) {
                    Text("暂无已知项目（连接 DSH 后出现）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(workspaces.enumerated()), id: \.element.id) { index, workspace in
                    SettingsToggleRow(
                        symbol: "folder.fill",
                        tint: Color(red: 0.36, green: 0.56, blue: 0.88),
                        title: workspace.title,
                        subtitle: "\(workspace.count) 个会话",
                        isOn: binding(workspaceId: workspace.id),
                        showDivider: index < workspaces.count - 1
                    )
                }
            }
        }
    }

    private var iconSettings: some View {
        SettingsGroup("菜单栏图标",
                      footnote: "外环单色 = 当前最高优先级待办（红停止 > 黄待答 > 绿完成）；彗星弧 = 运行中。流畅动画由 GPU 驱动（常驻 CPU≈0），静态则完全不耗电。") {
            SettingsMenuRow(
                symbol: "number.circle.fill",
                tint: Theme.statusColor(.running, scheme: colorScheme),
                title: "中心数字",
                subtitle: settings.centerNumberMode.shortLabel
            ) {
                Picker("", selection: $settings.centerNumberMode) {
                    ForEach(CenterNumberMode.allCases) { mode in
                        Text(mode.shortLabel).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 150)
            }
            SettingsToggleRow(
                symbol: "circle.dashed",
                tint: Theme.statusColor(.completed, scheme: colorScheme),
                title: "状态切换动效",
                subtitle: "状态变化时外环扫一圈 + 颜色渐变过渡",
                isOn: $settings.transitionAnimation
            )
            SettingsMenuRow(
                symbol: "arrow.triangle.2.circlepath",
                tint: Theme.statusColor(.running, scheme: colorScheme),
                title: "运行中动画",
                subtitle: settings.runAnimation ? "流畅（GPU，60fps）" : "静态（不耗电）",
                showDivider: false
            ) {
                Picker("", selection: $settings.runAnimation) {
                    Text("流畅").tag(true)
                    Text("静态").tag(false)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110)
            }
        }
    }

    private var panelSettings: some View {
        SettingsGroup("面板背景",
                      footnote: "开启系统「降低透明度」时会自动使用实色。") {
            SettingsMenuRow(
                symbol: "rectangle.on.rectangle",
                tint: Color(red: 0.45, green: 0.50, blue: 0.62),
                title: "材质",
                subtitle: settings.panelBackgroundStyle.label,
                showDivider: false
            ) {
                Picker("", selection: $settings.panelBackgroundStyle) {
                    ForEach(PanelBackgroundStyle.availableStyles) { style in
                        Text(style.label).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 130)
            }
        }
    }

    private var notificationSettings: some View {
        SettingsGroup("通知",
                      footnote: "点击通知会打开对应会话；同会话 30 秒内不重复。") {
            SettingsMenuRow(
                symbol: notificationSymbol,
                tint: notificationTint,
                title: "系统通知",
                subtitle: notificationSubtitle,
                showDivider: true
            ) {
                switch model.notificationPermission {
                case .authorized:
                    Text("已开启").font(.system(size: 11)).foregroundStyle(.secondary)
                case .denied:
                    Button("打开系统设置") { model.onOpenNotificationSettings?() }
                        .controlSize(.small)
                case .notDetermined:
                    Button("允许通知") { model.onRequestNotificationPermission?() }
                        .controlSize(.small)
                case .unknown:
                    EmptyView()
                }
            }
            SettingsToggleRow(
                symbol: "bell.badge.fill",
                tint: Theme.statusColor(.waiting, scheme: colorScheme),
                title: "待回答（推荐）",
                isOn: $settings.notifyWaiting
            )
            SettingsToggleRow(
                symbol: "checkmark.circle.fill",
                tint: Theme.statusColor(.completed, scheme: colorScheme),
                title: "已完成",
                isOn: $settings.notifyCompleted
            )
            SettingsToggleRow(
                symbol: "stop.circle.fill",
                tint: Theme.statusColor(.stopped, scheme: colorScheme),
                title: "已停止",
                isOn: $settings.notifyStopped,
                showDivider: false
            )
        }
    }

    // MARK: 底栏

    private var footerBar: some View {
        HStack {
            Button("恢复默认") { settings.reset() }
                .controlSize(.small)
            Toggle("退出前确认", isOn: $settings.confirmBeforeQuit)
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .font(.system(size: 10.5))
                .help("点面板电源键或右键菜单「退出」时先弹确认框")
            Spacer()
            Text("v\(AppConfig.appVersion) · \(model.connected ? "已连接" : "未连接")")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    private var notificationSymbol: String {
        switch model.notificationPermission {
        case .authorized: return "bell.badge.fill"
        case .denied: return "bell.slash.fill"
        case .notDetermined, .unknown: return "bell.badge.fill"
        }
    }

    private var notificationTint: Color {
        switch model.notificationPermission {
        case .authorized: return Theme.statusColor(.completed, scheme: colorScheme)
        case .denied: return Theme.statusColor(.stopped, scheme: colorScheme)
        case .notDetermined, .unknown: return Theme.statusColor(.waiting, scheme: colorScheme)
        }
    }

    private var notificationSubtitle: String {
        switch model.notificationPermission {
        case .authorized: return "系统通知已开启"
        case .denied: return "被系统关闭，不会弹出任何提醒"
        case .notDetermined: return "尚未授权"
        case .unknown: return "状态未知"
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

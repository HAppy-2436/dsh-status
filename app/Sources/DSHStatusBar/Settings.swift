import AppKit
import SwiftUI
import Combine

// MARK: - 设置模型

enum CenterNumberMode: String, CaseIterable, Identifiable {
    case attention
    case nonIdle
    case hidden

    var id: String { rawValue }

    var label: String {
        switch self {
        case .attention: return "关注数（待回答+已完成+已停止）"
        case .nonIdle: return "非空闲总数（含运行中）"
        case .hidden: return "不显示数字"
        }
    }

    var shortLabel: String {
        switch self {
        case .attention: return "关注数"
        case .nonIdle: return "非空闲总数"
        case .hidden: return "不显示"
        }
    }
}

enum SegmentCap: Int, CaseIterable, Identifiable {
    case four = 4
    case six = 6
    case eight = 8
    case twelve = 12
    case unlimited = 0

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .four: return "4"
        case .six: return "6"
        case .eight: return "8"
        case .twelve: return "12"
        case .unlimited: return "不限"
        }
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
    @Published var segmentCap: SegmentCap {
        didSet { save("segmentCap", segmentCap.rawValue) }
    }
    @Published var notifyWaiting: Bool { didSet { save("notifyWaiting", notifyWaiting) } }
    @Published var notifyCompleted: Bool { didSet { save("notifyCompleted", notifyCompleted) } }
    @Published var notifyStopped: Bool { didSet { save("notifyStopped", notifyStopped) } }
    @Published var confirmBeforeQuit: Bool { didSet { save("confirmBeforeQuit", confirmBeforeQuit) } }

    init(persist: Bool = true, defaults: UserDefaults = .standard) {
        self.persist = persist
        self.defaults = persist ? defaults : nil
        let storedStatuses = defaults.stringArray(forKey: "dshStatus.visibleStatuses")
        let statuses = storedStatuses?.compactMap { SessionStatus(rawValue: $0) } ?? []
        visibleStatuses = Set(statuses.isEmpty ? SessionStatus.allCases.filter { $0 != .idle } : statuses)
        hiddenWorkspaces = Set(defaults.stringArray(forKey: "dshStatus.hiddenWorkspaces") ?? [])
        centerNumberMode = CenterNumberMode(rawValue: defaults.string(forKey: "dshStatus.centerNumberMode") ?? "") ?? .attention
        segmentCap = SegmentCap(rawValue: defaults.integer(forKey: "dshStatus.segmentCap")) ?? .eight
        notifyWaiting = defaults.object(forKey: "dshStatus.notifyWaiting") as? Bool ?? true
        notifyCompleted = defaults.object(forKey: "dshStatus.notifyCompleted") as? Bool ?? false
        notifyStopped = defaults.object(forKey: "dshStatus.notifyStopped") as? Bool ?? false
        confirmBeforeQuit = defaults.object(forKey: "dshStatus.confirmBeforeQuit") as? Bool ?? true
    }

    /// 预览/演示用：不落盘。
    static func preview() -> AppSettings {
        AppSettings(persist: false)
    }

    func reset() {
        visibleStatuses = Set(SessionStatus.allCases.filter { $0 != .idle })
        hiddenWorkspaces = []
        centerNumberMode = .attention
        segmentCap = .eight
        notifyWaiting = true
        notifyCompleted = false
        notifyStopped = false
        confirmBeforeQuit = true
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
                    projectSettings
                    iconSettings
                    notificationSettings
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
                      footnote: "任务数超过上限时，按优先级只画前 N 段；中心数字仍表示完整数量。") {
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
            SettingsMenuRow(
                symbol: "chart.pie.fill",
                tint: Theme.statusColor(.completed, scheme: colorScheme),
                title: "圆环段数上限",
                subtitle: settings.segmentCap == .unlimited ? "不限" : "最多 \(settings.segmentCap.label) 段",
                showDivider: false
            ) {
                Picker("", selection: $settings.segmentCap) {
                    ForEach(SegmentCap.allCases) { cap in
                        Text(cap.label).tag(cap)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 90)
            }
        }
    }

    private var notificationSettings: some View {
        SettingsGroup("通知",
                      footnote: "点击通知会打开 DSH 主页面；同会话 30 秒内不重复。") {
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

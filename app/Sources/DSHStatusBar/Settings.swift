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
            window.setContentSize(NSSize(width: 470, height: 760))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - 设置页

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header

                card(title: "显示状态") {
                    ForEach([SessionStatus.waiting, .running, .completed, .stopped], id: \.self) { status in
                        Toggle(isOn: binding(for: status)) {
                            HStack(spacing: 8) {
                                Circle().fill(color(status)).frame(width: 8, height: 8)
                                Text(status.label).font(.system(size: 12.5))
                                Text("\(count(status)) 个")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    }
                    Text("隐藏的状态既不在面板里出现，也不计入菜单栏圆环与数字。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                card(title: "项目显示") {
                    let workspaces = workspaceRows()
                    if workspaces.isEmpty {
                        Text("暂无已知项目（连接 DSH 后出现）")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(workspaces, id: \.id) { workspace in
                            Toggle(isOn: binding(workspaceId: workspace.id)) {
                                HStack(spacing: 8) {
                                    Text(workspace.title).font(.system(size: 12.5))
                                    Text("\(workspace.count) 个会话")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                        Text("关闭开关即隐藏该项目；会话本身不受影响。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                }

                card(title: "菜单栏图标") {
                    Text("中心数字")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $settings.centerNumberMode) {
                        ForEach(CenterNumberMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    Text("圆环段数上限")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    Picker("", selection: $settings.segmentCap) {
                        ForEach(SegmentCap.allCases) { cap in
                            Text(cap.label).tag(cap)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("任务数超过上限时，按优先级只画前 N 段；中心数字仍表示完整数量。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                card(title: "通知") {
                    Toggle("待回答（推荐）", isOn: $settings.notifyWaiting)
                        .toggleStyle(.switch).controlSize(.small)
                    Toggle("已完成", isOn: $settings.notifyCompleted)
                        .toggleStyle(.switch).controlSize(.small)
                    Toggle("已停止", isOn: $settings.notifyStopped)
                        .toggleStyle(.switch).controlSize(.small)
                    Text("点击通知会打开 DSH 主页面；同会话 30 秒内不重复。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                }
                .padding(18)
            }
            Divider()
            footerBar
        }
        .frame(width: 470, height: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var footerBar: some View {
        HStack {
            Button("恢复默认") { settings.reset() }
                .controlSize(.small)
            Spacer()
            Text("v\(AppConfig.appVersion) · \(model.connected ? "已连接" : "未连接")")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.subtleFill(colorScheme)).frame(width: 34, height: 34)
                Image(nsImage: WhaleLogo.templateImage(height: 13))
                    .renderingMode(.template)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("DSH Status 设置").font(.system(size: 14, weight: .semibold))
                Text("菜单栏图标与面板的显示规则").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                content()
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .fill(Theme.cardFill(colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .stroke(Theme.cardStroke(colorScheme), lineWidth: 1)
            )
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

    private func color(_ status: SessionStatus) -> Color {
        Theme.statusColor(status, scheme: colorScheme)
    }
}

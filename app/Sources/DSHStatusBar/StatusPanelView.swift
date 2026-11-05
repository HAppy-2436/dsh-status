import SwiftUI

/// 弹出面板：macOS 26/27 原生浮层观感（见 docs/ui-redesign-spec.md §2）。
///
/// 结构：header（鲸鱼 + 标题 + 连接状态）/ 通知提示 / 分组会话列表 / 动作行 / footer。
/// 视觉：320pt 宽、20pt 圆角（由 NSPanel 提供材质）、13pt 行标题 + 11pt 副标题、
/// 系统语义色 + 系统状态色、全宽分隔线、hover 仅轻微底色。
struct StatusPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.panelUsesMaterial) private var usesMaterial

    private var width: CGFloat { Theme.Metrics.panelWidth }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showsNotificationHint {
                notificationHint
                Divider()
            }
            content
            Divider()
            footer
        }
        .frame(width: width)
        .background(usesMaterial ? Color.clear : Theme.panelFallbackBackground)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: WhaleLogo.templateImage(height: 13))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
            Text("DSH 会话")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            connectionBadge
        }
        .padding(.horizontal, Theme.Metrics.panelHorizontalPadding)
        .frame(height: Theme.Metrics.headerHeight)
    }

    private var connectionBadge: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(model.connected
                      ? Theme.uiColor(.completed)
                      : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 6, height: 6)
            Text(model.connected ? "实时" : "未连接")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .help(model.connected ? "与 DeepSeek Harness 实时同步" : "等待 DeepSeek Harness 连接")
    }

    // MARK: - 通知提示（未授权时）

    private var showsNotificationHint: Bool {
        guard model.connected else { return false }
        return model.notificationPermission == .denied
            || model.notificationPermission == .notDetermined
    }

    private var notificationHint: some View {
        PanelRowButton(action: {
            if model.notificationPermission == .notDetermined {
                model.onRequestNotificationPermission?()
            } else {
                model.onOpenNotificationSettings?()
            }
        }, height: 32, horizontalPadding: 0, cornerRadius: 0) {
            HStack(spacing: 8) {
                Image(systemName: "bell.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.uiColor(.waiting))
                Text("通知未开启，任务结束不会提醒")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("去开启")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Metrics.panelHorizontalPadding)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if !model.connected {
            disconnected
        } else if model.sections.isEmpty {
            empty
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(model.sections.enumerated()), id: \.element.status) { index, section in
                        if index > 0 { groupSeparator }
                        sectionView(status: section.status, rows: section.rows)
                    }
                    groupSeparator
                    openDSHRow
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .frame(height: contentHeight)
        }
    }

    private var groupSeparator: some View {
        Divider()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }

    private func sectionView(status: SessionStatus, rows: [SessionRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(status.label) · \(rows.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .frame(height: Theme.Metrics.sectionHeaderHeight, alignment: .bottomLeading)
                .padding(.bottom, 2)
            ForEach(rows) { row in
                SessionRowView(row: row,
                               onOpen: { model.onOpenSession?(row.id) })
                ForEach(model.subagents(for: row.id)) { sub in
                    SubagentRowView(subagent: sub,
                                    onOpen: { model.onOpenSession?(row.id) })
                }
            }
        }
    }

    private var openDSHRow: some View {
        PanelRowButton(action: { model.onOpenDSH?() }, height: Theme.Metrics.actionRowHeight) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                Text("打开 DSH")
                    .font(.system(size: 13))
                Spacer(minLength: 6)
            }
        }
        .help("打开 DeepSeek Harness 主窗口")
    }

    /// 与上面布局常量保持一致的高度估算（ScrollView 需要显式高度）。
    private var contentHeight: CGFloat {
        let m = Theme.Metrics.self
        let rows = model.sections.reduce(0) { $0 + $1.rows.count }
        let subRows = model.sections.reduce(0) { total, section in
            total + section.rows.reduce(0) { $0 + model.subagents(for: $1.id).count }
        }
        let sections = model.sections.count
        let separators = sections // 组间 + 动作行前
        let height = CGFloat(rows) * m.rowHeight
            + CGFloat(subRows) * m.subagentRowHeight
            + CGFloat(sections) * (m.sectionHeaderHeight + 2)
            + CGFloat(separators) * 9
            + m.actionRowHeight
            + 12
        return min(max(height, 96), m.maxContentHeight)
    }

    // MARK: - 空 / 未连接

    private var empty: some View {
        VStack(spacing: 6) {
            Image(nsImage: WhaleLogo.templateImage(height: 24))
                .renderingMode(.template)
                .foregroundStyle(.tertiary)
            Text("全部空闲")
                .font(.system(size: 13, weight: .semibold))
            Text("没有需要关注的会话")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 132)
    }

    private var disconnected: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text("DSH 未连接")
                    .font(.system(size: 13, weight: .semibold))
            }
            Text("等待 DeepSeek Harness 启动…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("打开 DSH") { model.onOpenDSH?() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 4) {
            FooterButton(action: { model.onOpenSettings?() },
                         help: "设置…（⌘,）") {
                HStack(spacing: 5) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                    Text("设置…")
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(height: 24)
                .contentShape(Rectangle())
            }

            Spacer(minLength: 0)

            if model.notificationPermission == .authorized {
                FooterButton(action: { model.settings.notifyWaiting.toggle() },
                             help: "待回答通知（更多设置见设置页）") {
                    footerIcon(model.settings.notifyWaiting ? "bell" : "bell.slash")
                }
            } else {
                FooterButton(action: {
                    if model.notificationPermission == .notDetermined {
                        model.onRequestNotificationPermission?()
                    } else {
                        model.onOpenNotificationSettings?()
                    }
                }, help: "通知未开启，点此开启") {
                    footerIcon("bell.slash")
                }
            }

            FooterButton(action: { model.onQuit?() }, help: "退出 DSH Status") {
                footerIcon("power")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.Metrics.footerHeight)
    }

    private func footerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }
}

// MARK: - 行按钮（hover 底色 + 整行命中）

private struct PanelRowButton<Content: View>: View {
    let action: () -> Void
    var height: CGFloat = 44
    var horizontalPadding: CGFloat = 6
    var cornerRadius: CGFloat = 6
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    init(action: @escaping () -> Void,
         height: CGFloat = 44,
         horizontalPadding: CGFloat = 6,
         cornerRadius: CGFloat = 6,
         @ViewBuilder content: () -> Content) {
        self.action = action
        self.height = height
        self.horizontalPadding = horizontalPadding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
    }
}

private struct FooterButton<Content: View>: View {
    let action: () -> Void
    let help: String
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    init(action: @escaping () -> Void, help: String, @ViewBuilder content: () -> Content) {
        self.action = action
        self.help = help
        self.content = content()
    }

    var body: some View {
        Button(action: action) {
            content
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
        .help(help)
    }
}

// MARK: - 子智能体行

private struct SubagentRowView: View {
    let subagent: SubagentRow
    let onOpen: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.uiColor(subagent.statusKind).opacity(0.9))
                    .frame(width: 4, height: 4)
                Text(subagent.displayTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, 38)
            .padding(.trailing, 6)
            .frame(height: Theme.Metrics.subagentRowHeight)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
        .help("子智能体 · 点击打开所属会话")
    }
}

// MARK: - 会话行

private struct SessionRowView: View {
    let row: SessionRow
    let onOpen: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.uiColor(row.statusKind))
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .frame(height: Theme.Metrics.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
        .help(row.pendingSummary ?? row.displayTitle)
    }

    private var symbol: String {
        switch row.statusKind {
        case .waiting: return "questionmark.circle.fill"
        case .running: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .idle: return "circle"
        }
    }

    private var subtitle: String {
        switch row.statusKind {
        case .waiting:
            let summary = row.pendingSummary ?? "等待你的回复"
            if summary == row.displayTitle { return "\(row.projectName) · 等待你的回复" }
            return "\(row.projectName) · \(summary)"
        case .running:
            let elapsed = Fmt.elapsed(row.since)
            return elapsed.isEmpty ? row.projectName : "\(row.projectName) · 已运行 \(elapsed)"
        case .completed, .stopped:
            let rel = Fmt.relative(row.updatedAt ?? row.lastTurn?.at)
            return rel.isEmpty ? row.projectName : "\(row.projectName) · \(rel)"
        case .idle:
            return row.projectName
        }
    }
}

import SwiftUI

/// 弹出面板：macOS 26/27 原生浮层观感（见 docs/ui-redesign-spec.md §2）。
///
/// 结构：通知提示（仅未授权时）/ 扁平会话列表 / footer（状态点 + 设置 + 勿扰 + 退出）。
/// - 会话不再按状态分组：按 `since`（最近一次状态变化）倒序，最近变化的在最上面；
/// - 行首 8pt 状态圆点：红=已停止、黄=待回答、蓝=运行中、绿=已完成；
/// - 子智能体默认折叠，父行最左侧 Finder 风格披露三角展开；
/// - 有会话时不出现「打开 DSH」行，空闲 / 未连接时在空状态给按钮。
/// 视觉：330pt 宽、16pt 圆角（由 NSPanel 提供材质）、13pt 行标题 + 11pt 副标题、系统语义色。
struct StatusPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.panelUsesMaterial) private var usesMaterial

    private var width: CGFloat { Theme.Metrics.panelWidth }

    var body: some View {
        VStack(spacing: 0) {
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

    // MARK: - 通知提示（未授权时；仅此一处占一行）

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
        } else if model.orderedSessions.isEmpty {
            empty
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.orderedSessions) { row in
                        sessionBlock(row)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .frame(height: contentHeight)
        }
    }

    @ViewBuilder
    private func sessionBlock(_ row: SessionRow) -> some View {
        let subagents = model.subagents(for: row.id)
        SessionRowView(row: row,
                       subagentCount: subagents.count,
                       expanded: model.isSubagentsExpanded(row.id),
                       onToggleSubagents: { model.toggleSubagents(for: row.id) },
                       onOpen: { model.onOpenSession?(row.id) })
        if model.isSubagentsExpanded(row.id) {
            ForEach(subagents) { sub in
                SubagentRowView(subagent: sub,
                                onOpen: { model.onOpenSession?(row.id) })
            }
        }
    }

    /// 与上面布局常量保持一致的高度估算（ScrollView 需要显式高度）。
    private var contentHeight: CGFloat {
        var height: CGFloat = 12
        for row in model.orderedSessions {
            height += Theme.Metrics.rowHeight
            if model.isSubagentsExpanded(row.id) {
                height += CGFloat(model.subagents(for: row.id).count) * Theme.Metrics.subagentRowHeight
            }
        }
        return min(max(height, Theme.Metrics.rowHeight + 12), Theme.Metrics.maxContentHeight)
    }

    // MARK: - 空 / 未连接（此时才出现「打开 DSH」）

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
            Button("打开 DSH") { model.onOpenDSH?() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 164)
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
        .frame(height: 168)
    }

    // MARK: - 底部一行：状态点 · 设置 · 勿扰 · 退出

    private var footer: some View {
        HStack(spacing: 2) {
            Circle()
                .fill(model.connected
                      ? Theme.uiColor(.completed)
                      : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 7, height: 7)
                .padding(.leading, 6)
                .help(model.connected ? "已连接 DeepSeek Harness（实时同步）" : "等待 DeepSeek Harness 连接")
                .accessibilityLabel(model.connected ? "已连接" : "未连接")

            Spacer(minLength: 0)

            FooterButton(action: { model.onOpenSettings?() },
                         help: "设置…（⌘,）") {
                footerIcon("gearshape")
            }

            FooterButton(action: { model.settings.doNotDisturb.toggle() },
                         help: model.settings.doNotDisturb
                            ? "勿扰模式已开启（点击关闭）"
                            : "勿扰模式：关闭所有系统通知") {
                footerIcon(model.settings.doNotDisturb ? "moon.fill" : "moon",
                           tint: model.settings.doNotDisturb ? Color.accentColor : nil)
            }

            FooterButton(action: { model.onQuit?() }, help: "退出 DSH Status") {
                footerIcon("power")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.Metrics.footerHeight)
    }

    private func footerIcon(_ name: String, tint: Color? = nil) -> some View {
        Image(systemName: name)
            .font(.system(size: 13))
            .foregroundStyle(tint ?? Color.secondary)
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

// MARK: - 会话行（行首状态圆点 + Finder 风格披露三角）

private struct SessionRowView: View {
    let row: SessionRow
    let subagentCount: Int
    let expanded: Bool
    let onToggleSubagents: () -> Void
    let onOpen: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .leading) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(Theme.uiColor(row.statusKind))
                        .frame(width: 8, height: 8)
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
                .padding(.leading, disclosureColumn)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Theme.Metrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if subagentCount > 0 {
                Button(action: onToggleSubagents) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: disclosureColumn, height: Theme.Metrics.rowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(expanded ? "收起 \(subagentCount) 个子智能体"
                               : "展开 \(subagentCount) 个子智能体")
            }
        }
        .frame(height: Theme.Metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
        .help(row.pendingSummary ?? row.displayTitle)
    }

    /// 披露三角占位列宽：所有行的状态圆点因此左对齐。
    private let disclosureColumn: CGFloat = 18

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

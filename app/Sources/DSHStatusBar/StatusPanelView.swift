import SwiftUI

/// 弹出面板：**只显示会话**（docs/app-design.md §3.2）。
///
/// - 不按状态分组，按 `since`（进入当前状态时刻）倒序，最近变化的在最上；
/// - 行首 8pt 状态圆点：红=已停止、黄=待回答、蓝=运行中、绿=已完成；
/// - 行尾（trailing）统一是导航提示：没有子会话 = `chevron.right`（点卡片任意位置跳转会话）；
///   有子会话 = 「子智能体数量 + `chevron.down`」披露按钮（点它展开/收起，展开时下箭头旋转成上箭头）；
/// - 没有 header / footer：设置、勿扰、退出、打开 DSH 都在状态项**右键菜单**里；
/// - 有会话时不出现「打开 DSH」，全部空闲 / 未连接时在空状态给按钮。
struct StatusPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.panelUsesMaterial) private var usesMaterial

    private var width: CGFloat { Theme.Metrics.panelWidth }

    var body: some View {
        content
            .frame(width: width)
            .background(usesMaterial ? Color.clear : Theme.panelFallbackBackground)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if !model.connected {
            disconnected
        } else if model.orderedSessions.isEmpty {
            empty
        } else {
            sessionList
        }
    }

    private var sessionList: some View {
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
        .frame(height: 150)
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
        .frame(height: 160)
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
            .padding(.leading, 18)
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

// MARK: - 会话行（行首状态圆点 + 行尾导航/披露控件）

private struct SessionRowView: View {
    let row: SessionRow
    let subagentCount: Int
    let expanded: Bool
    let onToggleSubagents: () -> Void
    let onOpen: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    private var hasSubagents: Bool { subagentCount > 0 }

    var body: some View {
        ZStack(alignment: .trailing) {
            // 卡片本体：点任意位置打开会话。
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
                    // 给行尾控件留位：没有子会话时让出箭头宽度，有子会话时让出「数量 + 箭头」宽度。
                    Color.clear
                        .frame(width: trailingReserve)
                }
                .padding(.leading, 12)
                .padding(.trailing, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Theme.Metrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if hasSubagents {
                subagentToggle
                    .padding(.trailing, 8)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 10)
                    .allowsHitTesting(false)
            }
        }
        .frame(height: Theme.Metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.08), value: hovering)
        .help(hasSubagents
              ? (expanded ? "点右侧箭头收起 \(subagentCount) 个子智能体 · 点其它区域打开会话"
                          : "点右侧箭头展开 \(subagentCount) 个子智能体 · 点其它区域打开会话")
              : (row.pendingSummary ?? row.displayTitle))
    }

    /// 行尾「子智能体数量 + 披露箭头」：独立命中区，点展开/收起，不跳转会话。
    private var subagentToggle: some View {
        Button(action: onToggleSubagents) {
            HStack(spacing: 4) {
                Text("\(subagentCount)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .frame(height: Theme.Metrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: expanded)
        .help(expanded ? "收起 \(subagentCount) 个子智能体"
                       : "展开 \(subagentCount) 个子智能体")
    }

    /// 行尾为箭头 / 「数量 + 箭头」预留的宽度，保证标题截断不与控件重叠。
    private var trailingReserve: CGFloat {
        if hasSubagents { return subagentCount >= 10 ? 38 : 28 }
        return 12
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

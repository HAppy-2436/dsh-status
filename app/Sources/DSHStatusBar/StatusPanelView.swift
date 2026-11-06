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
            .padding(.horizontal, Theme.Metrics.panelContentInset)
            .padding(.vertical, 6)
        }
        .frame(height: contentHeight)
        .clipped()
        // 展开/收起时纯高度动画（不缩放文字），与面板窗口的高度跟随同一曲线。
        .animation(Theme.respectingReduceMotion(Theme.Motion.panelResize),
                   value: model.expandedSubagentParents)
    }

    @ViewBuilder
    private func sessionBlock(_ row: SessionRow) -> some View {
        let subagents = model.subagents(for: row.id)
        let expanded = model.isSubagentsExpanded(row.id)
        SessionRowView(row: row,
                       subagentCount: subagents.count,
                       expanded: expanded,
                       previewHover: model.previewHover.flatMap { $0.rowId == row.id ? $0.trailing : nil },
                       onToggleSubagents: { model.toggleSubagents(for: row.id) },
                       onOpen: { model.onOpenSession?(row.id) })
        if expanded {
            // 逐条错开淡入 + 轻微下移（系统「列表展开」的节奏）；减弱动态效果时瞬时出现。
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(subagents.enumerated()), id: \.element.id) { index, sub in
                    SubagentRowView(subagent: sub,
                                    onOpen: { model.onOpenSession?(row.id) })
                        .modifier(StaggeredReveal(index: index))
                }
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
            .padding(.leading, Theme.Metrics.subagentIndent)
            .padding(.trailing, Theme.Metrics.subagentTrailingPadding)
            .frame(height: Theme.Metrics.subagentRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.rowCornerRadius, style: .continuous)
                    .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PanelRowButtonStyle(cornerRadius: Theme.Metrics.rowCornerRadius))
        .onHover { hovering = $0 }
        .animation(Theme.respectingReduceMotion(Theme.Motion.hover), value: hovering)
        .help("子智能体 · 点击打开所属会话")
    }
}

// MARK: - 会话行（行首状态圆点 + 行尾导航/披露控件）

private struct SessionRowView: View {
    let row: SessionRow
    let subagentCount: Int
    let expanded: Bool
    /// 离屏预览用的强制悬停（真机永远 nil）。
    let previewHover: AppModel.PreviewHoverTrailing?
    let onToggleSubagents: () -> Void
    let onOpen: () -> Void
    @State private var hoverRow = false
    @State private var hoverToggle = false
    @Environment(\.colorScheme) private var colorScheme

    private var hasSubagents: Bool { subagentCount > 0 }
    private var hovering: Bool { hoverRow || previewHover == .row }
    private var toggleHovering: Bool { hoverToggle || previewHover == .control }

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
            .buttonStyle(PanelRowButtonStyle(cornerRadius: Theme.Metrics.rowCornerRadius))

            if hasSubagents {
                subagentToggle
                    .padding(.trailing, 8)
            }
        }
        // 没有子会话：行尾只放一个右箭头作导航提示（不可单独点，点卡片任意位置都能进会话）。
        .overlay(alignment: .trailing) {
            if !hasSubagents {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 10)
                }
                .frame(height: Theme.Metrics.rowHeight)
                .allowsHitTesting(false)
            }
        }
        .frame(height: Theme.Metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.rowCornerRadius, style: .continuous)
                .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
        )
        .onHover { hoverRow = $0 }
        .animation(Theme.respectingReduceMotion(Theme.Motion.hover), value: hovering)
        .help(hasSubagents
              ? (expanded ? "点右侧箭头收起 \(subagentCount) 个子智能体 · 点其它区域打开会话"
                          : "点右侧箭头展开 \(subagentCount) 个子智能体 · 点其它区域打开会话")
              : (row.pendingSummary ?? row.displayTitle))
    }

    /// 行尾「子智能体数量 + 披露箭头」：独立命中区 + 独立悬停胶囊（点它展开/收起，不跳转会话）。
    private var subagentToggle: some View {
        Button(action: onToggleSubagents) {
            HStack(spacing: 3) {
                Text("\(subagentCount)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .animation(Theme.respectingReduceMotion(Theme.Motion.disclosure), value: expanded)
            }
            .foregroundStyle(toggleHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .frame(height: 26)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Metrics.inlineControlCornerRadius, style: .continuous)
                    .fill(toggleHovering ? Theme.controlHoverFill(colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(InlineControlButtonStyle(cornerRadius: Theme.Metrics.inlineControlCornerRadius))
        .onHover { hoverToggle = $0 }
        .animation(Theme.respectingReduceMotion(Theme.Motion.hover), value: toggleHovering)
        .help(expanded ? "收起 \(subagentCount) 个子智能体"
                       : "展开 \(subagentCount) 个子智能体")
    }

    /// 行尾为箭头 / 「数量 + 箭头」预留的宽度。
    /// 预留 = 控件实际宽度 + 间隙：标题截断不会压到控件，行尾也不会留出大片空白。
    private var trailingReserve: CGFloat {
        guard hasSubagents else { return 12 }
        // 数字（11pt 等宽 ≈ 7pt/位）+ 3 间隙 + 9 箭头 + 6×2 胶囊内距 + 额外余量
        // （SwiftUI 内建布局先于 overlay 排版，留一点余量保证标题截断后不会压到胶囊）
        let numberWidth = CGFloat(String(subagentCount).count) * 7
        return ceil(numberWidth + 3 + 9 + 12 + 14)
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

// MARK: - 行按钮样式（按住时轻微压暗/下沉，接近 macOS 原生列表行）

/// 行卡片：按下时整体轻微变暗（系统列表行也是按住即反馈），松开交给 action。
private struct PanelRowButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.pressedFill(colorScheme) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Theme.respectingReduceMotion(Theme.Motion.hover), value: configuration.isPressed)
    }
}

/// 行内小控件：按下时胶囊再深一档。
private struct InlineControlButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Theme.controlPressedFill(colorScheme) : Color.clear)
            )
            .animation(Theme.respectingReduceMotion(Theme.Motion.hover), value: configuration.isPressed)
    }
}

// MARK: - 动效修饰器

/// 子行插入时的错班淡入：每条延迟 `Theme.Motion.stagger × index`，淡入 + 4pt 下移。
/// 减弱动态效果时直接显示（不改透明度/位移）。
private struct StaggeredReveal: ViewModifier {
    let index: Int
    @State private var shown = false

    func body(content: Content) -> some View {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : -4)
            .onAppear {
                guard !reduceMotion else { shown = true; return }
                withAnimation(.easeOut(duration: 0.18)
                    .delay(Theme.Motion.stagger * Double(index))) {
                    shown = true
                }
            }
    }
}

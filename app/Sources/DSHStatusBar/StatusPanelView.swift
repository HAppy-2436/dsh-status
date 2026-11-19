import SwiftUI

/// 弹出面板：**只显示会话**（docs/app-design.md §3.2）。
///
/// - 不按状态分组，按 `since`（进入当前状态时刻）倒序，最近变化的在最上；
/// - 行首 8pt 状态圆点：红=已停止、黄=待回答、蓝=运行中、绿=已完成；
/// - 行尾（trailing）统一是导航提示：没有子会话 = `chevron.right`（点卡片任意位置跳转会话）；
///   有子会话 = 「子智能体数量 + `chevron.down`」披露按钮（点它展开/收起，展开时下箭头旋转成上箭头）；
/// - 没有 header / footer：设置、勿扰、退出、打开 DSH 都在状态项**右键菜单**里；
/// - **空闲态（全部空闲 / 未连接）只显示「Logo + 全部空闲」一行**，整块可点 → 直接打开 DSH；
///   有会话时才显示列表。
struct StatusPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.panelUsesMaterial) private var usesMaterial

    private var width: CGFloat { Theme.Metrics.panelWidth }

    var body: some View {
        content
            .frame(width: width)
            // 高度由外层窗口逐帧动画控制；这里把内容放在一块固定高度的画布顶部。
            // 若让根视图高度跟着内容走，`NSHostingView` 会在「根视图比宿主高」时把它垂直居中，
            // 展开/收起的第一帧内容会整体上下跳一下（观感就是闪/抖）。固定画布 + 顶部对齐后，
            // 无论宿主此刻多高，内容的布局位置都不变，窗口只负责从底部揭幕。
            .frame(maxHeight: .infinity, alignment: .top)
            .background(usesMaterial ? Color.clear : Theme.panelFallbackBackground)
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if !model.connected {
            idleCompact(connected: false)
        } else if model.orderedSessions.isEmpty {
            idleCompact(connected: true)
        } else {
            sessionList
        }
    }

    /// 空闲 / 未连接：**整块面板就是一个按钮**——中间是「鲸鱼 Logo + 状态文字」，
    /// 点面板任意位置都打开 DSH（不再只有文字那一小块可点）。
    ///
    /// 内容区比会话行（44pt）再高一档（52pt）：整块面板 = 8 + 52 + 8 = 68pt，
    /// 悬停/按下底色铺满整块内容区，点哪里都能打开 DSH，不是一条细长的小胶囊。
    private func idleCompact(connected: Bool) -> some View {
        Button { model.onOpenDSH?() } label: {
            HStack(spacing: 11) {
                Image(nsImage: WhaleLogo.templateImage(height: 22))
                    .renderingMode(.template)
                    .foregroundStyle(connected ? AnyShapeStyle(.primary)
                                               : AnyShapeStyle(.secondary))
                Text(connected ? "全部空闲" : "未连接")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(connected ? AnyShapeStyle(.primary)
                                               : AnyShapeStyle(.secondary))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(IdleOpenButtonStyle())
        .help(connected ? "DSH 已连接 · 点面板任意位置打开 DSH"
                        : "DSH 未连接 · 点面板任意位置打开 DSH")
        .padding(Theme.Metrics.panelContentInset)
        .frame(height: Theme.Metrics.idleContentHeight + Theme.Metrics.panelContentInset * 2)
    }

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.orderedSessions) { row in
                    sessionBlock(row)
                }
            }
            .padding(.horizontal, Theme.Metrics.panelContentInset)
            // 上下内距与左右一致（8）：行 hover 底色的圆角（8）= 面板圆角（16）− 内距（8），
            // 两个方向的内距必须相同，内外圆角才是同一条 continuous 曲线的同心嵌套。
            .padding(.vertical, Theme.Metrics.panelContentInset)
        }
        .frame(height: contentHeight, alignment: .top)
        .clipped()
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
                       // 点行 = 跳转 + 当作已读：临时「已完成」行跳转后自动删掉（和普通未读行点开即清一致）
                       onOpen: {
                           if row.isTransient { model.onDismissSession?(row.id) }
                           model.onOpenSession?(row.id)
                       },
                       onDismiss: { model.onDismissSession?(row.id) })
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
        var height: CGFloat = Theme.Metrics.panelContentInset * 2
        for row in model.orderedSessions {
            height += Theme.Metrics.rowHeight
            if model.isSubagentsExpanded(row.id) {
                height += CGFloat(model.subagents(for: row.id).count) * Theme.Metrics.subagentRowHeight
            }
        }
        return min(max(height, Theme.Metrics.rowHeight + Theme.Metrics.panelContentInset * 2),
                   Theme.Metrics.maxContentHeight)
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
    let onDismiss: () -> Void
    @State private var hoverRow = false
    @State private var hoverToggle = false
    @State private var hoverDismiss = false
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
            .buttonStyle(PanelRowButtonStyle(cornerRadius: Theme.Metrics.rowHighlightCornerRadius))

            // 行尾统一轨道：右箭头（导航提示）/ 忽略 × / 子智能体披露按钮，
            // 三者共用 22pt 槽位与右边距，图标中心落在同一条竖线上。
            trailingRail
                .padding(.trailing, Theme.Metrics.rowTrailingInset)
        }
        .frame(height: Theme.Metrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Metrics.rowHighlightCornerRadius, style: .continuous)
                .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
        )
        .onHover { hoverRow = $0 }
        .animation(Theme.respectingReduceMotion(Theme.Motion.hover), value: hovering)
        .help(helpText)
    }

    /// 行尾「忽略」：只出现在桥补的临时「已完成」行上（点它删掉该行、角标减一，不跳转会话）。
    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hoverDismiss ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: Theme.Metrics.rowControlSize, height: Theme.Metrics.rowControlSize)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.inlineControlCornerRadius, style: .continuous)
                        .fill(hoverDismiss ? Theme.controlHoverFill(colorScheme) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(InlineControlButtonStyle(cornerRadius: Theme.Metrics.inlineControlCornerRadius))
        .onHover { hoverDismiss = $0 }
        .animation(Theme.respectingReduceMotion(Theme.Motion.hover), value: hoverDismiss)
        .help("忽略这条已完成（角标减一，不影响会话）")
    }

    private var helpText: String {
        var parts: [String] = []
        if row.isTransient { parts.append("点右侧 × 忽略这条已完成") }
        if hasSubagents {
            parts.append(expanded ? "点箭头收起 \(subagentCount) 个子智能体"
                                  : "点箭头展开 \(subagentCount) 个子智能体")
        }
        parts.append("点其它区域打开会话")
        return parts.joined(separator: " · ")
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
            .frame(height: Theme.Metrics.rowControlSize)
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

    /// 行尾统一轨道：与 `trailingRail` 一一对应（右箭头 / × / 披露按钮）。
    private var trailingRail: some View {
        HStack(spacing: Theme.Metrics.rowControlSpacing) {
            if row.isTransient { dismissButton }
            if hasSubagents { subagentToggle }
            if !hasSubagents && !row.isTransient { navigationChevron }
        }
    }

    /// 无子会话时的右箭头导航提示（不可单独点，点卡片任意位置都能进会话）。
    private var navigationChevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: Theme.Metrics.rowControlSize, height: Theme.Metrics.rowControlSize)
            .allowsHitTesting(false)
    }

    /// 行尾为箭头 / 「数量 + 箭头」预留的宽度：标题截断不会压到控件，行尾也不会留出大片空白。
    private var trailingReserve: CGFloat {
        if !row.isTransient && !hasSubagents { return Theme.Metrics.rowControlSize }
        var width: CGFloat = 0
        if row.isTransient { width += Theme.Metrics.rowControlSize }
        if hasSubagents {
            if width > 0 { width += Theme.Metrics.rowControlSpacing }
            // 数字（11pt 等宽 ≈ 7pt/位）+ 3 间隙 + 9 箭头 + 6×2 胶囊内距 + 余量
            width += ceil(CGFloat(String(subagentCount).count) * 7 + 26)
        }
        return width
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

/// 空闲态的整块「Logo + 全部空闲」：默认无底色，悬停出现与行同款的 8pt 圆角底色，
/// 按下再深一档 —— 三种状态都用菜单面板里唯一的行形状，观感与会话行一致。
private struct IdleOpenButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        IdleOpenLabel(configuration: configuration, colorScheme: colorScheme)
    }

    private struct IdleOpenLabel: View {
        let configuration: ButtonStyleConfiguration
        let colorScheme: ColorScheme
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: Theme.Metrics.rowHighlightCornerRadius, style: .continuous)
                        .fill(configuration.isPressed
                              ? Theme.pressedFill(colorScheme)
                              : (hovering ? Theme.hoverFill(colorScheme) : Color.clear))
                )
                .onHover { hovering = $0 }
                .animation(Theme.respectingReduceMotion(Theme.Motion.hover), value: hovering)
                .animation(Theme.respectingReduceMotion(Theme.Motion.hover), value: configuration.isPressed)
        }
    }
}

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

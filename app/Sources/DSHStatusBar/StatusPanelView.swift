import SwiftUI

/// 面板：参考 Status Trio 的 popover 设计——
/// 330pt 宽、14pt 边距、单色文字 + 小面积状态色 SF Symbol、
/// 细分隔线、chevron 指示、底部「设置…」+ 电源操作。
struct StatusPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.panelUsesMaterial) private var usesMaterial

    private let width: CGFloat = 330

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            content
            Divider().opacity(0.6)
            footer
        }
        .frame(width: width)
        .background(
            Group {
                if usesMaterial {
                    VisualEffectBackground()
                } else {
                    Color(nsColor: .windowBackgroundColor)
                }
            }
        )
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: WhaleLogo.templateImage(height: 12))
                .renderingMode(.template)
                .foregroundStyle(.secondary)
            Text("DSH 会话")
                .font(.headline)
            Spacer()
            Circle()
                .fill(model.connected
                      ? Theme.statusColor(.completed, scheme: colorScheme)
                      : Theme.disconnectedColor(colorScheme))
                .frame(width: 5, height: 5)
            Text(model.connected ? "实时" : "未连接")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    // MARK: 内容

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
                        if index > 0 {
                            Divider().opacity(0.6).padding(.vertical, 6)
                        }
                        sectionView(status: section.status, rows: section.rows)
                    }
                    Divider().opacity(0.6).padding(.vertical, 6)
                    openDSHRow
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(height: contentHeight)
        }
    }

    private func sectionView(status: SessionStatus, rows: [SessionRow]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(status.label) · \(rows.count)")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
                .padding(.bottom, 2)
            ForEach(rows) { row in
                SessionRowView(row: row,
                               onOpen: { model.onOpenSession?(row.id) })
            }
        }
    }

    private var openDSHRow: some View {
        Button {
            model.onOpenDSH?()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                Text("打开 DSH")
                    .font(.headline)
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var contentHeight: CGFloat {
        let rows = model.sections.reduce(0) { $0 + $1.rows.count }
        let sections = model.sections.count
        let height = CGFloat(rows) * 44 + CGFloat(sections) * 30 + 52
        return min(max(height, 96), 480)
    }

    // MARK: 空 / 未连接

    private var empty: some View {
        VStack(spacing: 6) {
            Image(nsImage: WhaleLogo.templateImage(height: 22))
                .renderingMode(.template)
                .foregroundStyle(.tertiary)
            Text("全部空闲")
                .font(.headline)
            Text("没有需要关注的会话")
                .font(.caption)
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
                    .font(.headline)
            }
            Text("等待 DeepSeek Harness 启动…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("打开 DSH") { model.onOpenDSH?() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 148)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.onOpenSettings?()
            } label: {
                Label("设置…", systemImage: "gearshape")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            iconButton(systemName: model.settings.notifyWaiting ? "bell" : "bell.slash",
                       help: "待回答通知（更多设置见设置页）") {
                model.settings.notifyWaiting.toggle()
            }
            iconButton(systemName: "power", help: "退出") {
                model.onQuit?()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Theme.statusColor(row.statusKind, scheme: colorScheme).opacity(0.95))
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayTitle)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Theme.hoverFill(colorScheme) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(row.pendingSummary ?? row.displayTitle)
    }

    private var symbol: String {
        switch row.statusKind {
        case .waiting: return "questionmark.circle"
        case .running: return "play.circle"
        case .completed: return "checkmark.circle"
        case .stopped: return "stop.circle"
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

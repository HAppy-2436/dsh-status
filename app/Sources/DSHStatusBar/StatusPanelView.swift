import SwiftUI

/// 面板主视图（深色优先）。
struct StatusPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.panelUsesMaterial) private var usesMaterial

    private let width: CGFloat = 344

    var body: some View {
        VStack(spacing: 0) {
            header
            hairline
            content
            hairline
            footer
        }
        .frame(width: width)
        .background(Group {
            if usesMaterial {
                VisualEffectBackground()
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        })
    }

    private var hairline: some View {
        Rectangle()
            .fill(Theme.hairline(colorScheme))
            .frame(height: 1)
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Theme.subtleFill(colorScheme))
                    .frame(width: 26, height: 26)
                Image(nsImage: WhaleLogo.templateImage(height: 11))
                    .renderingMode(.template)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("DSH 会话")
                    .font(.system(size: 13, weight: .semibold))
                Text("DeepSeek Harness")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            statusPill
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(model.connected
                      ? Theme.statusColor(.completed, scheme: colorScheme)
                      : Theme.statusColor(.stopped, scheme: colorScheme))
                .frame(width: 6, height: 6)
            Text(model.connected ? "实时" : "未连接")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill((model.connected
                            ? Theme.statusColor(.completed, scheme: colorScheme)
                            : Theme.statusColor(.stopped, scheme: colorScheme)).opacity(0.12))
        )
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
                VStack(spacing: 2) {
                    ForEach(model.sections, id: \.status) { section in
                        sectionView(status: section.status, rows: section.rows)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(height: contentHeight)
        }
    }

    private func sectionView(status: SessionStatus, rows: [SessionRow]) -> some View {
        VStack(spacing: 1) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor(status))
                    .frame(width: 6, height: 6)
                Text(status.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(rows.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.subtleFill(colorScheme)))
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(rows) { row in
                SessionRowView(row: row,
                               color: statusColor(status),
                               emphasized: status == .waiting,
                               onOpen: { model.onOpenSession?(row.id) })
            }
        }
    }

    private var contentHeight: CGFloat {
        let rows = model.sections.reduce(0) { $0 + $1.rows.count }
        let sections = model.sections.count
        let height = CGFloat(sections) * 34 + CGFloat(rows) * 48 + 12
        return min(max(height, 90), 470)
    }

    // MARK: 空 / 未连接

    private var empty: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Theme.subtleFill(colorScheme))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(.tertiary)
            }
            Text("全部空闲")
                .font(.system(size: 13, weight: .medium))
            Text("没有需要关注的会话")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 136)
    }

    private var disconnected: some View {
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                Circle().fill(Theme.statusColor(.stopped, scheme: colorScheme)).frame(width: 7, height: 7)
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
        .frame(height: 150)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.onOpenDSH?()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.forward.app").font(.system(size: 11))
                    Text("打开 DSH").font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Theme.subtleFill(colorScheme)))
            }
            .buttonStyle(.plain)

            Spacer()

            iconButton(systemName: model.notificationsEnabled ? "bell" : "bell.slash",
                       help: "待回答通知") {
                model.notificationsEnabled.toggle()
                model.onToggleNotifications?()
            }
            iconButton(systemName: "gearshape", help: "设置") {
                model.onOpenSettings?()
            }
            iconButton(systemName: "power", help: "退出") {
                model.onQuit?()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private func iconButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Theme.subtleFill(colorScheme)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        Theme.statusColor(status, scheme: colorScheme)
    }
}

// MARK: - 单行

private struct SessionRowView: View {
    let row: SessionRow
    let color: Color
    let emphasized: Bool
    let onOpen: () -> Void
    @State private var hovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 15, height: 15)
                    Circle().fill(color).frame(width: 6.5, height: 6.5)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayTitle)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if hovering {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 46)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row)
                    .fill(background)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(row.pendingSummary ?? row.displayTitle)
    }

    private var background: Color {
        if hovering { return Theme.hoverFill(colorScheme) }
        if emphasized { return Theme.statusColor(.waiting, scheme: colorScheme).opacity(0.055) }
        return .clear
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

import SwiftUI

/// 面板主视图（docs/app-design.md §3）。
struct StatusPanelView: View {
    @ObservedObject var model: AppModel

    private let width: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)

            if !model.connected {
                disconnected
            } else if model.sections.isEmpty {
                empty
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(model.sections, id: \.status) { section in
                            sectionView(status: section.status, rows: section.rows)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: contentHeight)
            }

            Divider().opacity(0.6)
            footer
        }
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "fish.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("DSH 会话")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Circle()
                .fill(model.connected ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(model.connected ? "实时" : "未连接")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    // MARK: 分组

    private func sectionView(status: SessionStatus, rows: [SessionRow]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(statusColor(status)).frame(width: 7, height: 7)
                Text(status.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(rows.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            ForEach(rows) { row in
                SessionRowView(row: row,
                               color: statusColor(status),
                               onOpen: { model.onOpenSession?(row.id) })
            }
        }
    }

    private var contentHeight: CGFloat {
        let rows = model.sections.reduce(0) { $0 + $1.rows.count }
        let sections = model.sections.count
        let height = CGFloat(sections) * 26 + CGFloat(rows) * 46 + 8
        return min(max(height, 88), 460)
    }

    // MARK: 空 / 未连接

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("全部空闲")
                .font(.system(size: 13, weight: .medium))
            Text("没有需要关注的会话")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
    }

    private var disconnected: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(Color.orange).frame(width: 7, height: 7)
                Text("DSH 未连接")
                    .font(.system(size: 13, weight: .medium))
            }
            Text("等待 DeepSeek Harness 启动…")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button("打开 DSH") { model.onOpenDSH?() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                model.onOpenDSH?()
            } label: {
                Label("打开 DSH", systemImage: "arrow.up.forward.app")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                model.notificationsEnabled.toggle()
                model.onToggleNotifications?()
            } label: {
                Image(systemName: model.notificationsEnabled ? "bell" : "bell.slash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("待回答通知")

            Button {
                model.onQuit?()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("退出")
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .waiting: return .red
        case .running: return .blue
        case .completed: return .green
        case .stopped: return .orange
        case .idle: return .gray
        }
    }
}

// MARK: - 单行

private struct SessionRowView: View {
    let row: SessionRow
    let color: Color
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 9) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
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
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
            )
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(row.pendingSummary ?? row.displayTitle)
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

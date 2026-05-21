import SwiftUI

/// 侧边栏 — Gemini 风格轻抽屉
/// 顶部：品牌 + 设置入口
/// 中间：按日期分组的历史对话列表（今天/昨天/更早）
/// 底部：新对话 FAB
/// 支持：右滑删除、长按重命名
struct SidebarView: View {
    let sessions: [SessionItem]
    let onSelectSession: (String) -> Void
    let onNewChat: () -> Void
    let onDeleteSession: (String) -> Void
    let onRenameSession: (String, String) -> Void
    let onOpenSettings: () -> Void
    var runningSessionId: String? = nil // 正在运行的对话 ID

    @State private var searchText = ""
    @State private var renamingSession: SessionItem? = nil
    @State private var renameText = ""

    // MARK: - Date Groups

    private var todaySessions: [SessionItem] {
        filteredSessions.filter { Calendar.current.isDateInToday($0.createdAt) }
    }

    private var yesterdaySessions: [SessionItem] {
        filteredSessions.filter { Calendar.current.isDateInYesterday($0.createdAt) }
    }

    private var olderSessions: [SessionItem] {
        filteredSessions.filter {
            !Calendar.current.isDateInToday($0.createdAt) && !Calendar.current.isDateInYesterday($0.createdAt)
        }
    }

    private var filteredSessions: [SessionItem] {
        if searchText.isEmpty { return sessions }
        return sessions.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                HStack(spacing: SageTheme.Spacing.sm) {
                    Image("SageLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.sm, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sage")
                            .font(.system(size: 20, weight: .semibold))
                        Text("金融助手")
                            .font(.system(size: 12))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                    }
                }
                Spacer()
                SageIconButton(
                    systemName: "person.crop.circle",
                    color: SageTheme.ColorToken.brand,
                    background: SageTheme.ColorToken.brandSoft
                ) {
                    onOpenSettings()
                }
            }
            .padding(.horizontal, SageTheme.Spacing.lg)
            .padding(.top, SageTheme.Spacing.lg)
            .padding(.bottom, SageTheme.Spacing.md)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 14))
                TextField("搜索对话", text: $searchText)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, SageTheme.Spacing.sm)
            .padding(.vertical, 10)
            .background(SageTheme.ColorToken.surfaceSecondary)
            .clipShape(Capsule())
            .padding(.horizontal, SageTheme.Spacing.md)
            .padding(.bottom, SageTheme.Spacing.sm)

            Button(action: onNewChat) {
                HStack(spacing: SageTheme.Spacing.sm) {
                    Image(systemName: "plus.message.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("新对话")
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.7)
                }
                .foregroundColor(.white)
                .padding(.horizontal, SageTheme.Spacing.md)
                .padding(.vertical, 13)
                .background(SageTheme.ColorToken.brand)
                .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, SageTheme.Spacing.md)
            .padding(.bottom, SageTheme.Spacing.sm)

            // Session list (grouped by date)
            if filteredSessions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    SageEmptyStateView(
                        systemName: "bubble.left.and.bubble.right",
                        title: "暂无对话",
                        message: "开始一次新的市场研究或复盘。"
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 今天
                        if !todaySessions.isEmpty {
                            sectionHeader("今天")
                            ForEach(todaySessions) { session in
                                sessionRow(session)
                            }
                        }

                        // 昨天
                        if !yesterdaySessions.isEmpty {
                            sectionHeader("昨天")
                            ForEach(yesterdaySessions) { session in
                                sessionRow(session)
                            }
                        }

                        // 更早
                        if !olderSessions.isEmpty {
                            sectionHeader("更早")
                            ForEach(olderSessions) { session in
                                sessionRow(session)
                            }
                        }
                    }
                }
            }

            Spacer()

            Button(action: onOpenSettings) {
                HStack(spacing: SageTheme.Spacing.sm) {
                    Image(systemName: "gearshape")
                    Text("设置与账号")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, SageTheme.Spacing.md)
                .padding(.vertical, 12)
                .background(SageTheme.ColorToken.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, SageTheme.Spacing.md)
            .padding(.bottom, SageTheme.Spacing.lg)
        }
        .background(
            SageTheme.ColorToken.surface
                .clipShape(RoundedRectangle(cornerRadius: 0, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 24, x: 8, y: 0)
        )
        .alert("重命名对话", isPresented: .init(
            get: { renamingSession != nil },
            set: { if !$0 { renamingSession = nil } }
        )) {
            TextField("对话标题", text: $renameText)
            Button("取消", role: .cancel) { renamingSession = nil }
            Button("确定") {
                if let session = renamingSession, !renameText.isEmpty {
                    onRenameSession(session.id, renameText)
                }
                renamingSession = nil
            }
        } message: {
            Text("请输入新的对话标题")
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding(.horizontal, SageTheme.Spacing.lg)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    // MARK: - Session Row (swipe to delete + long press menu)

    private func sessionRow(_ session: SessionItem) -> some View {
        Button {
            onSelectSession(session.id)
        } label: {
            HStack(spacing: 10) {
                // 运行中绿色脉冲点
                if session.id == runningSessionId {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color.green.opacity(0.4), lineWidth: 2)
                                .scaleEffect(1.5)
                        )
                } else {
                    Image(systemName: "bubble.left")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Text(session.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, SageTheme.Spacing.md)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: SageTheme.Radius.sm, style: .continuous)
                    .fill(session.id == runningSessionId ? SageTheme.ColorToken.brandSoft.opacity(0.75) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SageTheme.Spacing.xs)
        .contextMenu {
            Button {
                renamingSession = session
                renameText = session.title
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                onDeleteSession(session.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDeleteSession(session.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

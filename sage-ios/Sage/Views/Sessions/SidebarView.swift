import SwiftUI

/// 侧边栏 — ChatGPT 风格
/// 顶部：品牌 + 设置头像
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
                Text("Sage")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // Session list (grouped by date)
            if filteredSessions.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("暂无对话")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
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

            // New chat FAB
            HStack {
                Spacer()
                Button {
                    onNewChat()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14, weight: .medium))
                        Text("新对话")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.primary)
                    .cornerRadius(24)
                }
                .padding(.trailing, 20)
                .padding(.bottom, 20)
            }
        }
        .background(Color(.systemBackground))
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
            .padding(.horizontal, 20)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

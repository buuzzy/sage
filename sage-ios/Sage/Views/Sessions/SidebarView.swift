import SwiftUI

/// 侧边栏 — ChatGPT 风格
/// 顶部：品牌 + 搜索 + 头像
/// 中间：历史对话列表
/// 底部：新对话 FAB
struct SidebarView: View {
    let sessions: [SessionItem]
    let onSelectSession: (String) -> Void
    let onNewChat: () -> Void
    let onOpenSettings: () -> Void

    @State private var searchText = ""

    var filteredSessions: [SessionItem] {
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
                Button { } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18))
                        .foregroundColor(.primary)
                }
                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 24))
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
                TextField("搜索", text: $searchText)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            // Session list
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
                        Text("最近")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 8)

                        ForEach(filteredSessions) { session in
                            Button {
                                onSelectSession(session.id)
                            } label: {
                                Text(session.title)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                            }
                            .background(Color.clear)
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
    }
}

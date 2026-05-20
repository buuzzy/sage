import Foundation

/// 会话列表 ViewModel
@MainActor
class SessionListViewModel: ObservableObject {
    @Published var sessions: [SessionItem] = []

    func loadSessions() {
        // TODO: Load from SwiftData / Supabase
        // For now, sessions are added dynamically when user chats
    }

    func addSession(_ session: SessionItem) {
        // Insert at top
        if !sessions.contains(where: { $0.id == session.id }) {
            sessions.insert(session, at: 0)
        }
    }

    func deleteSession(_ id: String) {
        sessions.removeAll { $0.id == id }
    }

    func updateTitle(_ id: String, title: String) {
        if let idx = sessions.firstIndex(where: { $0.id == id }) {
            sessions[idx].title = title
        }
    }
}

/// 会话项
struct SessionItem: Identifiable {
    let id: String
    var title: String
    var lastMessage: String?
    var createdAt: Date

    init(id: String = UUID().uuidString, title: String, lastMessage: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.lastMessage = lastMessage
        self.createdAt = createdAt
    }
}

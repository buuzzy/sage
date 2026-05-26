import Foundation
import Combine

/// 会话列表 ViewModel
@MainActor
class SessionListViewModel: ObservableObject {
    @Published var sessions: [SessionItem] = []
    @Published var isRestoring = false
    private var cancellables = Set<AnyCancellable>()
    private var hasRestoredFromCloud = false

    init() {
        // Listen for cron result updates to refresh session list
        NotificationCenter.default.publisher(for: .cronSessionsUpdated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.loadSessions() }
            .store(in: &cancellables)
    }

    func loadSessions() {
        // Load from UserDefaults
        sessions = ChatViewModel.loadAllSessionsFromStorage()

        // If local is empty and haven't tried cloud restore yet, auto-restore
        if sessions.isEmpty && !hasRestoredFromCloud {
            restoreFromCloud()
        }
    }

    /// 从 Supabase 恢复会话列表（合并到本地，不覆盖）
    func restoreFromCloud() {
        guard !isRestoring else { return }
        guard let userId = AuthService.shared.userId else { return }

        hasRestoredFromCloud = true
        isRestoring = true

        Task {
            let cloudSessions = await CloudSyncService.shared.restoreSessions(userId: userId)

            if !cloudSessions.isEmpty {
                // Merge: cloud sessions that don't exist locally
                var localIds = Set(sessions.map { $0.id })
                var merged = sessions
                for cs in cloudSessions {
                    if !localIds.contains(cs.id) {
                        merged.append(cs)
                        localIds.insert(cs.id)
                    }
                }
                // Sort by createdAt descending
                merged.sort { $0.createdAt > $1.createdAt }
                sessions = merged
                // Persist merged list locally
                ChatViewModel.saveAllSessionsToStorage(sessions)
                print("[SessionList] Restored \(cloudSessions.count) sessions from cloud, merged total: \(sessions.count)")
            }

            isRestoring = false
        }
    }

    func addSession(_ session: SessionItem) {
        // Insert at top
        if !sessions.contains(where: { $0.id == session.id }) {
            sessions.insert(session, at: 0)
        }
    }

    func deleteSession(_ id: String) {
        sessions.removeAll { $0.id == id }
        // Persist deletion
        ChatViewModel.saveAllSessionsToStorage(sessions)
        // Also remove messages
        UserDefaults.standard.removeObject(forKey: "sage_messages_\(id)")
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

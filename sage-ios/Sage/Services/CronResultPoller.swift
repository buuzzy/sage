import Foundation

/// 轮询 Supabase 检测新的 Cron 执行结果会话
/// 后端 cron 执行成功后会将结果写入 Supabase sessions + messages 表（platform='cron'）。
/// 本服务在 App 进入前台时检查是否有新结果，并触发本地通知 + 会话列表刷新。
class CronResultPoller {
    static let shared = CronResultPoller()

    private let lastCheckKey = "sage_cron_last_check_at"

    private var lastCheckAt: Date {
        get { UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? Date.distantPast }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckKey) }
    }

    private init() {}

    /// 检查 Supabase 中是否有新的 cron 结果会话，有则插入本地 + 发通知
    func checkForNewResults() async {
        // AuthService 和 ChatViewModel 是 @MainActor 隔离的，需要在 MainActor 上访问
        let userId = await MainActor.run { AuthService.shared.userId }
        let token = await AuthService.shared.getAccessToken()
        guard let userId, let token else { return }

        let since = ISO8601DateFormatter().string(from: lastCheckAt)
        let baseUrl = SupabaseConfig.url.absoluteString
        let anonKey = SupabaseConfig.anonKey

        // Query: sessions where title starts with [定时] and created_at > lastCheckAt
        let encodedPrefix = "[定时]".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "[定时]"
        let urlString = "\(baseUrl)/rest/v1/sessions?user_id=eq.\(userId)&title=like.\(encodedPrefix)*&created_at=gt.\(since)&order=created_at.desc&limit=10"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            guard let sessions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            if sessions.isEmpty { return }

            // Insert new sessions into local storage (MainActor-isolated)
            var allSessions = await MainActor.run { ChatViewModel.loadAllSessionsFromStorage() }
            var newCount = 0

            for dict in sessions {
                guard let id = dict["id"] as? String,
                      let title = dict["title"] as? String else { continue }

                // Skip if already exists locally
                if allSessions.contains(where: { $0.id == id }) { continue }

                let createdAt: Date
                if let dateStr = dict["created_at"] as? String {
                    createdAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()
                } else {
                    createdAt = Date()
                }

                let newSession = SessionItem(id: id, title: title, createdAt: createdAt)
                allSessions.insert(newSession, at: 0)
                newCount += 1

                // Send local notification for each new cron result
                NotificationService.shared.sendCronJobNotification(
                    jobName: title.replacingOccurrences(of: "[定时] ", with: ""),
                    result: nil
                )
            }

            if newCount > 0 {
                await MainActor.run { ChatViewModel.saveAllSessionsToStorage(allSessions) }
                // Post notification so UI reloads session list
                await MainActor.run {
                    NotificationCenter.default.post(name: .cronSessionsUpdated, object: nil)
                }
                print("[CronPoller] Found \(newCount) new cron result session(s)")
            }

            // Update checkpoint
            lastCheckAt = Date()
        } catch {
            print("[CronPoller] Check failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notification name for UI refresh

extension Notification.Name {
    static let cronSessionsUpdated = Notification.Name("sage_cron_sessions_updated")
}

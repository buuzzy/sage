import Foundation

/// 轮询 Supabase 检测新的 Cron 执行结果，进前台时触发本地推送。
///
/// 后端 cron 执行成功后会：
///   1. 写入 Supabase sessions + messages（事实源）
///   2. 写入 mobile_actions 一条行动卡（在「行动」Tab 展示）
///
/// 本服务只负责「有新结果时弹本地通知」。结果的 UI 落地由 /mobile/actions 承载，
/// 不再往本地 UserDefaults 写会话/消息（投资对讲机已无会话档案 UI）。
class CronResultPoller {
    static let shared = CronResultPoller()

    private let lastCheckKey = "sage_cron_last_check_at"

    private var lastCheckAt: Date {
        get { UserDefaults.standard.object(forKey: lastCheckKey) as? Date ?? Date.distantPast }
        set { UserDefaults.standard.set(newValue, forKey: lastCheckKey) }
    }

    private init() {}

    /// 检查是否有新的 cron 结果会话，有则发本地通知。
    func checkForNewResults() async {
        let userId = await MainActor.run { AuthService.shared.userId }
        let token = await AuthService.shared.getAccessToken()
        guard let userId, let token else { return }

        let since = ISO8601DateFormatter().string(from: lastCheckAt)
        let baseUrl = SupabaseConfig.url.absoluteString
        let anonKey = SupabaseConfig.anonKey

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

            for dict in sessions {
                guard let id = dict["id"] as? String,
                      let title = dict["title"] as? String else { continue }
                let preview = dict["preview"] as? String
                NotificationService.shared.sendCronJobNotification(
                    jobName: title.replacingOccurrences(of: "[定时] ", with: ""),
                    result: preview,
                    sessionId: id
                )
            }

            print("[CronPoller] Found \(sessions.count) new cron result session(s)")
            lastCheckAt = Date()
        } catch {
            print("[CronPoller] Check failed: \(error.localizedDescription)")
        }
    }
}

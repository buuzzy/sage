import Foundation

/// 云端数据同步服务 — 火忘式双写
/// 本地 UserDefaults 写成功后，异步同步到 Supabase
/// 对标桌面端 sync/ 模块（简化版）
class CloudSyncService {
    static let shared = CloudSyncService()

    private let supabaseUrl = "https://wymqgwtagpsjuonsclye.supabase.co"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Ind5bXFnd3RhZ3BzanVvbnNjbHllIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzU3OTcwMTUsImV4cCI6MjA1MTM3MzAxNX0.eO7VZFXQ_VeMkTwKI3V1gq-9F5jAqS-y7yJCJy-xEq4"

    private var syncQueue: [(table: String, data: [String: Any])] = []
    private var isSyncing = false

    private init() {}

    // MARK: - Session Sync

    /// 同步会话元数据到云端
    func syncSession(sessionId: String, title: String, userId: String) {
        let data: [String: Any] = [
            "id": sessionId,
            "user_id": userId,
            "title": title,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "platform": "ios"
        ]
        enqueue(table: "sessions", data: data)
    }

    /// 同步消息到云端
    func syncMessage(taskId: String, type: String, content: String, userId: String) {
        let data: [String: Any] = [
            "id": UUID().uuidString,
            "task_id": taskId,
            "user_id": userId,
            "type": type,
            "content": content,
            "created_at": ISO8601DateFormatter().string(from: Date())
        ]
        enqueue(table: "messages", data: data)
    }

    /// 同步设置到云端
    func syncSettings(userId: String, settings: [String: Any]) {
        var data = settings
        data["user_id"] = userId
        data["updated_at"] = ISO8601DateFormatter().string(from: Date())
        enqueue(table: "user_settings", data: data)
    }

    // MARK: - Cloud Restore

    /// 从云端恢复会话列表
    func restoreSessions(userId: String) async -> [SessionItem] {
        guard let token = await AuthService.shared.getAccessToken() else { return [] }

        do {
            var request = URLRequest(url: URL(string: "\(supabaseUrl)/rest/v1/sessions?user_id=eq.\(userId)&order=created_at.desc&limit=50")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }

            if let sessions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return sessions.compactMap { dict in
                    guard let id = dict["id"] as? String,
                          let title = dict["title"] as? String else { return nil }
                    let createdAt: Date
                    if let dateStr = dict["created_at"] as? String {
                        createdAt = ISO8601DateFormatter().date(from: dateStr) ?? Date()
                    } else {
                        createdAt = Date()
                    }
                    return SessionItem(id: id, title: title, createdAt: createdAt)
                }
            }
        } catch { }
        return []
    }

    // MARK: - Cloud Delete (Clear Data)

    /// 删除当前用户在云端的所有对话数据：messages → tasks → sessions
    /// 顺序遵循 FK 依赖：messages 依赖 tasks，tasks 依赖 sessions，必须先删子后删父
    /// 不影响 persona_memory / user_settings / auth.users — 那些留给「注销」流程
    /// 返回 true 表示三张表都成功；任何一张失败都返回 false（前端可展示部分失败）
    func clearAllConversationData(userId: String) async -> Bool {
        guard let token = await AuthService.shared.getAccessToken() else { return false }

        let tablesInDeleteOrder = ["messages", "tasks", "sessions"]
        var allOk = true
        for table in tablesInDeleteOrder {
            let ok = await deleteRows(table: table, userId: userId, token: token)
            if !ok { allOk = false }
        }
        return allOk
    }

    private func deleteRows(table: String, userId: String, token: String) async -> Bool {
        guard let url = URL(string: "\(supabaseUrl)/rest/v1/\(table)?user_id=eq.\(userId)") else {
            print("[CloudSync][delete] ❌ \(table): bad URL")
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        // 让 PostgREST 返回被删除的行数，用于明确诊断（return=representation 也能用，但响应大）
        request.setValue("return=minimal,count=exact", forHTTPHeaderField: "Prefer")

        print("[CloudSync][delete] ▶ \(table) — DELETE \(url.absoluteString)")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                print("[CloudSync][delete] ❌ \(table): non-HTTP response")
                return false
            }
            let bodyText = String(data: data, encoding: .utf8) ?? "<binary \(data.count) bytes>"
            let contentRange = http.value(forHTTPHeaderField: "Content-Range") ?? "—"

            if (200...299).contains(http.statusCode) {
                print("[CloudSync][delete] ✅ \(table): status=\(http.statusCode) range=\(contentRange) body=\(bodyText.prefix(200))")
                return true
            } else {
                print("[CloudSync][delete] ❌ \(table): status=\(http.statusCode) range=\(contentRange) body=\(bodyText.prefix(500))")
                return false
            }
        } catch {
            print("[CloudSync][delete] ❌ \(table): network error \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Queue Worker

    private func enqueue(table: String, data: [String: Any]) {
        syncQueue.append((table: table, data: data))
        processQueue()
    }

    private func processQueue() {
        guard !isSyncing, !syncQueue.isEmpty else { return }
        isSyncing = true

        Task {
            while !syncQueue.isEmpty {
                let item = syncQueue.removeFirst()
                await upload(table: item.table, data: item.data)
            }
            isSyncing = false
        }
    }

    private func upload(table: String, data: [String: Any]) async {
        guard let token = await AuthService.shared.getAccessToken() else { return }

        do {
            var request = URLRequest(url: URL(string: "\(supabaseUrl)/rest/v1/\(table)")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: data)

            _ = try await URLSession.shared.data(for: request)
        } catch {
            // 火忘式 — 失败不阻塞用户
            print("[CloudSync] Upload failed for \(table): \(error.localizedDescription)")
        }
    }
}

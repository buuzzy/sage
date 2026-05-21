import Foundation
import UIKit

/// API 客户端 — 负责与 Railway 后端通信
/// 使用 URLSession 实现 SSE 流式传输
/// 通过 beginBackgroundTask 实现后台保活（最多约 30 秒）
/// 通过 background URLSession configuration 实现长时间后台传输
actor APIClient {
    static let shared = APIClient()

    private let baseURL = "https://sage-production-28e1.up.railway.app"
    private let apiToken = "b2cbe89f938ee822f4a7efa45315346429fa1c34f9534e08f558e649cc46f3ed"

    private let decoder = JSONDecoder()

    // MARK: - Agent Endpoints

    /// 发送消息到 Agent（SSE 流式响应）
    func streamAgent(request: AgentRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        return streamRequest(endpoint: "/agent", body: request)
    }

    /// 请求生成计划
    func streamPlan(request: AgentRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        return streamRequest(endpoint: "/agent/plan", body: request)
    }

    /// 执行已批准的计划
    func streamExecute(request: AgentRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        return streamRequest(endpoint: "/agent/execute", body: request)
    }

    /// 生成标题
    func generateTitle(prompt: String, modelConfig: ModelConfig?, language: String) async throws -> String {
        struct TitleRequest: Codable {
            let prompt: String
            let modelConfig: ModelConfig?
            let language: String
        }
        struct TitleResponse: Codable {
            let title: String
        }

        let body = TitleRequest(prompt: prompt, modelConfig: modelConfig, language: language)
        let data = try await postJSON(endpoint: "/agent/title", body: body)
        let response = try decoder.decode(TitleResponse.self, from: data)
        return response.title
    }

    /// 停止当前会话
    func stopSession(_ sessionId: String) async throws {
        let url = URL(string: "\(baseURL)/agent/stop/\(sessionId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    /// 响应权限请求
    func respondToPermission(sessionId: String, permissionId: String, approved: Bool) async throws {
        struct PermissionResponse: Codable {
            let sessionId: String
            let permissionId: String
            let approved: Bool
        }
        let body = PermissionResponse(sessionId: sessionId, permissionId: permissionId, approved: approved)
        _ = try await postJSON(endpoint: "/agent/permission", body: body)
    }

    /// 获取 Cron 任务列表
    func getCronJobs() async throws -> Data {
        return try await getJSON(endpoint: "/cron/jobs")
    }

    /// 切换 Cron 任务启用状态
    func toggleCronJob(jobId: String, enabled: Bool) async throws {
        struct ToggleBody: Codable { let enabled: Bool }
        _ = try await postJSON(endpoint: "/cron/jobs/\(jobId)/toggle", body: ToggleBody(enabled: enabled))
    }

    /// 删除 Cron 任务
    func deleteCronJob(jobId: String) async throws {
        let url = URL(string: "\(baseURL)/cron/jobs/\(jobId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: request)
    }

    /// 手动触发 Cron 任务
    func triggerCronJob(jobId: String) async throws {
        struct EmptyBody: Codable {}
        _ = try await postJSON(endpoint: "/cron/jobs/\(jobId)/run", body: EmptyBody())
    }

    /// 切换 Skill 启用状态
    func toggleSkill(name: String, enabled: Bool) async throws {
        struct ToggleBody: Codable {
            let name: String
            let enabled: Bool
        }

        _ = try await postJSON(endpoint: "/skills/toggle", body: ToggleBody(name: name, enabled: enabled))
    }

    /// 获取 task 缺失事件（iOS 后台恢复补偿）
    func getTaskEvents(taskId: String, afterSeq: Int) async throws -> Data {
        return try await getJSON(endpoint: "/agent/task/\(taskId)/events?after=\(afterSeq)")
    }

    /// 获取 task 状态
    func getTaskStatus(taskId: String) async throws -> Data {
        return try await getJSON(endpoint: "/agent/task/\(taskId)/status")
    }

    /// 获取当前用户画像。这里使用 Supabase JWT，让后端按 RLS 返回当前用户数据。
    func getPersona(accessToken: String) async throws -> Data {
        return try await getJSON(endpoint: "/persona/memory", bearerToken: accessToken)
    }

    // MARK: - SSE Stream Implementation (with background task support)

    private func streamRequest<T: Encodable>(endpoint: String, body: T) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // 请求后台执行时间（防止切后台时连接被立即杀掉）
                let bgTaskId = await MainActor.run {
                    UIApplication.shared.beginBackgroundTask(withName: "SageSSEStream") {
                        // 系统要求结束后台任务时的回调
                    }
                }

                defer {
                    // 结束后台任务
                    Task { @MainActor in
                        if bgTaskId != .invalid {
                            UIApplication.shared.endBackgroundTask(bgTaskId)
                        }
                    }
                }

                do {
                    let url = URL(string: "\(self.baseURL)\(endpoint)")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(self.apiToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)
                    // 延长超时 — 长时间流式响应
                    request.timeoutInterval = 300

                    // 创建支持后台的 URLSession 配置
                    let config = URLSessionConfiguration.default
                    config.timeoutIntervalForRequest = 300
                    config.timeoutIntervalForResource = 600
                    config.shouldUseExtendedBackgroundIdleMode = true
                    let session = URLSession(configuration: config)

                    // Use bytes for streaming
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw APIError.httpError(statusCode: httpResponse.statusCode)
                    }

                    // Parse SSE using lines (correctly handles UTF-8 multi-byte characters)
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if line.hasPrefix("data: ") {
                            let jsonStr = String(line.dropFirst(6))
                            if let jsonData = jsonStr.data(using: .utf8),
                               let event = try? self.decoder.decode(SSEEvent.self, from: jsonData) {
                                continuation.yield(event)
                                if event.type == .done {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    if !Task.isCancelled {
                        continuation.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func postJSON<T: Encodable>(endpoint: String, body: T) async throws -> Data {
        let url = URL(string: "\(baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }

    func getJSON(endpoint: String) async throws -> Data {
        return try await getJSON(endpoint: endpoint, bearerToken: apiToken)
    }

    private func getJSON(endpoint: String, bearerToken: String) async throws -> Data {
        let url = URL(string: "\(baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return data
    }
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器返回了无效响应"
        case .httpError(let code):
            return "请求失败 (HTTP \(code))"
        case .decodingError(let msg):
            return "数据解析失败: \(msg)"
        }
    }
}

import Foundation
import UIKit

/// API 客户端 — 负责与 Railway 后端通信
/// 使用 URLSession 实现 SSE 流式传输
/// 通过 beginBackgroundTask 实现后台保活（最多约 30 秒）
/// 通过 background URLSession configuration 实现长时间后台传输
actor APIClient {
    static let shared = APIClient()

    private let baseURL = "https://sage-production-28e1.up.railway.app"
    /// Railway 后端共享 Bearer token。来自 Secrets.xcconfig 的 SAGE_API_TOKEN，
    /// 经 Info.plist substitution 注入，禁止在源码 hardcode（参考 SupabaseConfig）。
    private let apiToken = APIClient.loadAPIToken()

    private let decoder = JSONDecoder()

    private static func loadAPIToken() -> String {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "SAGE_API_TOKEN") as? String,
              !token.isEmpty,
              token != "your-sage-api-token-here" else {
            fatalError(
                "[APIClient] 缺失或未填入的 SAGE_API_TOKEN。\n" +
                "请检查 sage-ios/Sage/Config/Secrets.xcconfig 是否存在并填入正确值\n" +
                "（参考 Secrets.xcconfig.example）"
            )
        }
        return token
    }

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

    /// 获取 iOS 投资对讲机资产首页。
    func getMobileDashboard() async throws -> MobileDashboard {
        let data = try await getJSON(endpoint: "/mobile/dashboard")
        return try decoder.decode(MobileDashboardResponse.self, from: data).dashboard
    }

    /// 行动 / 想法卡接口按 user_id 隔离持久化，必须带用户 Supabase JWT（而非共享 token）。
    func getMobileActions() async throws -> [InvestmentActionItem] {
        let token = try await userToken()
        let data = try await getJSON(endpoint: "/mobile/actions", bearerToken: token)
        return try decoder.decode(MobileActionsResponse.self, from: data).actions
    }

    /// 上传 push-to-talk 录音到后端转写（SenseVoice）。需用户 JWT；key 留服务端。
    func transcribe(audioURL: URL) async throws -> String {
        let token = try await userToken()
        let audioData = try Data(contentsOf: audioURL)
        let boundary = "Boundary-\(UUID().uuidString)"

        let url = URL(string: "\(baseURL)/mobile/transcribe")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        var body = Data()
        func appendString(_ string: String) { body.append(string.data(using: .utf8)!) }
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
        appendString("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        appendString("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        struct TranscribeResponse: Codable {
            let ok: Bool
            let text: String?
        }
        return try decoder.decode(TranscribeResponse.self, from: data).text ?? ""
    }

    func createIdeaNote(transcript: String? = nil, symbol: String? = nil, intent: String? = nil) async throws -> CreateIdeaNoteResponse {
        let token = try await userToken()
        let body = CreateIdeaNoteRequest(transcript: transcript, symbol: symbol, intent: intent)
        let data = try await postJSON(endpoint: "/mobile/notes", body: body, bearerToken: token)
        return try decoder.decode(CreateIdeaNoteResponse.self, from: data)
    }

    func confirmIdeaNote(noteId: String) async throws {
        struct EmptyBody: Codable {}
        let token = try await userToken()
        _ = try await postJSON(endpoint: "/mobile/notes/\(noteId)/confirm", body: EmptyBody(), bearerToken: token)
    }

    /// 取当前用户的 Supabase access token；未登录时抛出 401。
    private func userToken() async throws -> String {
        guard let token = await AuthService.shared.getAccessToken() else {
            throw APIError.httpError(statusCode: 401)
        }
        return token
    }

    /// 获取持仓 K 线。后端当前是富途语义 mock，后续替换 adapter 后接口不变。
    func getPositionKline(code: String, name: String, count: Int = 60) async throws -> KLineChartData {
        let encodedCode = code.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? code
        let data = try await getJSON(endpoint: "/broker/positions/\(encodedCode)/kline?period=day&count=\(count)")
        let response = try decoder.decode(BrokerKlineResponse.self, from: data)
        let points = response.kline.map {
            KLineDataPoint(
                time: $0.time,
                open: $0.open,
                close: $0.close,
                high: $0.high,
                low: $0.low,
                vol: $0.volume,
                turnover: nil
            )
        }
        return KLineChartData(code: response.code, name: name, ktype: response.period, data: points)
    }

    // MARK: - SSE Stream Implementation (with retry + background task support)

    /// 最大自动重试次数
    private let maxRetries = 2
    /// 可重试的网络错误码
    private let retryableErrorCodes: Set<Int> = [
        -1005, // NSURLErrorNetworkConnectionLost — 网络连接已中断
        -1001, // NSURLErrorTimedOut — 请求超时
        -1009, // NSURLErrorNotConnectedToInternet — 无网络
        -1004, // NSURLErrorCannotConnectToHost — 无法连接服务器
    ]

    private func streamRequest<T: Encodable>(endpoint: String, body: T) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // 请求后台执行时间（防止切后台时连接被立即杀掉）
                let bgTaskId = await MainActor.run {
                    UIApplication.shared.beginBackgroundTask(withName: "SageSSEStream") {
                        // 系统要求结束后台任务时的回调 — 不做额外处理，defer 会 endBackgroundTask
                    }
                }

                defer {
                    Task { @MainActor in
                        if bgTaskId != .invalid {
                            UIApplication.shared.endBackgroundTask(bgTaskId)
                        }
                    }
                }

                var lastError: Error?
                var attempt = 0

                while attempt <= self.maxRetries {
                    if Task.isCancelled { break }

                    // 重试时等待（指数退避：1s, 2s）
                    if attempt > 0 {
                        let delay = UInt64(pow(2.0, Double(attempt - 1))) * 1_000_000_000
                        try? await Task.sleep(nanoseconds: delay)
                        if Task.isCancelled { break }
                    }

                    do {
                        let url = URL(string: "\(self.baseURL)\(endpoint)")!
                        var request = URLRequest(url: url)
                        request.httpMethod = "POST"
                        request.setValue("Bearer \(self.apiToken)", forHTTPHeaderField: "Authorization")
                        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                        request.httpBody = try JSONEncoder().encode(body)
                        request.timeoutInterval = 300

                        let config = URLSessionConfiguration.default
                        config.timeoutIntervalForRequest = 300
                        config.timeoutIntervalForResource = 600
                        config.shouldUseExtendedBackgroundIdleMode = true
                        // 网络切换时允许等待连接恢复
                        config.waitsForConnectivity = true
                        let session = URLSession(configuration: config)

                        let (bytes, response) = try await session.bytes(for: request)

                        guard let httpResponse = response as? HTTPURLResponse else {
                            throw APIError.invalidResponse
                        }

                        guard httpResponse.statusCode == 200 else {
                            throw APIError.httpError(statusCode: httpResponse.statusCode)
                        }

                        // 成功连接 — 开始解析 SSE
                        // Parse SSE lines
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
                        // 正常结束（stream exhausted without done event）
                        continuation.finish()
                        return

                    } catch {
                        lastError = error

                        // 判断是否可重试
                        let nsError = error as NSError
                        let isRetryable = self.retryableErrorCodes.contains(nsError.code)

                        if isRetryable && attempt < self.maxRetries {
                            attempt += 1
                            continue
                        } else {
                            // 不可重试或已耗尽重试 — 失败
                            break
                        }
                    }
                }

                // 最终失败
                if !Task.isCancelled {
                    if let error = lastError {
                        let nsError = error as NSError
                        if self.retryableErrorCodes.contains(nsError.code) {
                            // 网络错误 — 给用户更友好的提示
                            continuation.finish(throwing: APIError.networkLost)
                        } else {
                            continuation.finish(throwing: error)
                        }
                    } else {
                        continuation.finish()
                    }
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func postJSON<T: Encodable>(endpoint: String, body: T, bearerToken: String? = nil) async throws -> Data {
        let url = URL(string: "\(baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(bearerToken ?? apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
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
    case networkLost

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "服务器返回了无效响应"
        case .httpError(let code):
            return "请求失败 (HTTP \(code))"
        case .decodingError(let msg):
            return "数据解析失败: \(msg)"
        case .networkLost:
            return "网络连接不稳定，请检查网络后重试"
        }
    }
}

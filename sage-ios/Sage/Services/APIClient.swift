import Foundation

/// API 客户端 — 负责与 Railway 后端通信
/// 使用 URLSession 实现 SSE 流式传输，支持后台运行
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

    // MARK: - SSE Stream Implementation

    private func streamRequest<T: Encodable>(endpoint: String, body: T) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let url = URL(string: "\(baseURL)\(endpoint)")!
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(body)

                    // Use bytes for streaming
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw APIError.invalidResponse
                    }

                    guard httpResponse.statusCode == 200 else {
                        throw APIError.httpError(statusCode: httpResponse.statusCode)
                    }

                    // Parse SSE using lines (correctly handles UTF-8 multi-byte characters)
                    for try await line in bytes.lines {
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

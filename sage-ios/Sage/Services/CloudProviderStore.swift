import Foundation
import Supabase

/// 云端 Provider 管理（Phase 4 — 完全云端化）
///
/// 数据源：user_providers 表（通过 /user-providers REST API）
/// API Key 由 Supabase Vault KMS 加密存储，客户端不持有明文。
///
/// 职责：
/// - 拉取用户所有 provider 配置
/// - 创建 / 更新 / 删除 provider
/// - 设置默认 provider
/// - 服务端代测连通性
@MainActor
class CloudProviderStore: ObservableObject {
    static let shared = CloudProviderStore()

    @Published var providers: [CloudProvider] = []
    @Published var isLoading = false
    @Published var error: String?

    private let baseURL: String

    private init() {
        self.baseURL = APIClient.shared.baseURL
    }

    // MARK: - Auth Helper

    private func authHeaders() async throws -> [String: String] {
        guard let session = try? await SupabaseConfig.shared.client.auth.session else {
            throw CloudProviderError.notAuthenticated
        }
        return [
            "Content-Type": "application/json",
            "Authorization": "Bearer \(session.accessToken)"
        ]
    }

    var isAuthenticated: Bool {
        get async {
            do {
                _ = try await SupabaseConfig.shared.client.auth.session
                return true
            } catch {
                return false
            }
        }
    }

    // MARK: - CRUD

    /// 拉取所有 provider（不含明文 key）
    func refresh() async {
        isLoading = true
        error = nil
        do {
            let headers = try await authHeaders()
            let url = URL(string: "\(baseURL)/user-providers")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw CloudProviderError.serverError("Failed to fetch providers")
            }

            let decoded = try JSONDecoder().decode(ProvidersResponse.self, from: data)
            self.providers = decoded.providers
        } catch let err as CloudProviderError {
            self.error = err.localizedDescription
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// 创建 provider
    func create(_ input: CreateProviderInput) async throws -> CloudProvider {
        let headers = try await authHeaders()
        let url = URL(string: "\(baseURL)/user-providers")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONEncoder().encode(input)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            let errBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw CloudProviderError.serverError(errBody?.error ?? "Failed to create provider")
        }

        let decoded = try JSONDecoder().decode(ProviderResponse.self, from: data)
        await refresh()
        return decoded.provider
    }

    /// 更新 provider（字段级 PATCH）
    func update(id: String, patch: UpdateProviderInput) async throws {
        let headers = try await authHeaders()
        let url = URL(string: "\(baseURL)/user-providers/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONEncoder().encode(patch)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw CloudProviderError.serverError(errBody?.error ?? "Failed to update provider")
        }
        await refresh()
    }

    /// 删除 provider
    func delete(id: String) async throws {
        let headers = try await authHeaders()
        let url = URL(string: "\(baseURL)/user-providers/\(id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errBody = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw CloudProviderError.serverError(errBody?.error ?? "Failed to delete provider")
        }
        await refresh()
    }

    /// 设为默认
    func setDefault(id: String) async throws {
        let headers = try await authHeaders()
        let url = URL(string: "\(baseURL)/user-providers/\(id)/default")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw CloudProviderError.serverError("Failed to set default provider")
        }
        await refresh()
    }

    /// 服务端代测连通性
    func test(id: String) async throws -> TestResult {
        let headers = try await authHeaders()
        let url = URL(string: "\(baseURL)/user-providers/\(id)/test")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return TestResult(success: false, error: "Server error")
        }

        return try JSONDecoder().decode(TestResult.self, from: data)
    }

    // MARK: - Convenience

    /// 获取默认 provider（用于聊天时传 modelConfig）
    var defaultProvider: CloudProvider? {
        providers.first(where: { $0.isDefault && $0.enabled }) ?? providers.first(where: { $0.enabled })
    }
}

// MARK: - Models

struct CloudProvider: Codable, Identifiable {
    let id: String
    let userId: String
    let providerKind: String
    let displayName: String
    let apiType: String
    let baseUrl: String
    let endpointPath: String
    let models: [String]
    let defaultModel: String?
    let enabled: Bool
    let isDefault: Bool
    let sortOrder: Int
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case providerKind = "provider_kind"
        case displayName = "display_name"
        case apiType = "api_type"
        case baseUrl = "base_url"
        case endpointPath = "endpoint_path"
        case models
        case defaultModel = "default_model"
        case enabled
        case isDefault = "is_default"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CreateProviderInput: Codable {
    let providerKind: String
    let displayName: String
    let apiType: String
    let baseUrl: String
    let endpointPath: String
    let models: [String]?
    let defaultModel: String?
    let apiKey: String
    let enabled: Bool?
    let isDefault: Bool?
    let sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case providerKind = "provider_kind"
        case displayName = "display_name"
        case apiType = "api_type"
        case baseUrl = "base_url"
        case endpointPath = "endpoint_path"
        case models
        case defaultModel = "default_model"
        case apiKey = "api_key"
        case enabled
        case isDefault = "is_default"
        case sortOrder = "sort_order"
    }
}

struct UpdateProviderInput: Codable {
    var displayName: String?
    var apiType: String?
    var baseUrl: String?
    var endpointPath: String?
    var models: [String]?
    var defaultModel: String?
    var apiKey: String?
    var enabled: Bool?
    var isDefault: Bool?
    var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case apiType = "api_type"
        case baseUrl = "base_url"
        case endpointPath = "endpoint_path"
        case models
        case defaultModel = "default_model"
        case apiKey = "api_key"
        case enabled
        case isDefault = "is_default"
        case sortOrder = "sort_order"
    }
}

struct TestResult: Codable {
    let success: Bool
    let status: Int?
    let error: String?
    let warning: String?
}

// MARK: - Internal Response Types

private struct ProvidersResponse: Codable {
    let providers: [CloudProvider]
}

private struct ProviderResponse: Codable {
    let provider: CloudProvider
}

private struct ErrorResponse: Codable {
    let error: String?
}

// MARK: - Errors

enum CloudProviderError: LocalizedError {
    case notAuthenticated
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "未登录，请先登录后再管理模型配置"
        case .serverError(let msg):
            return msg
        }
    }
}

// MARK: - Built-in Provider Templates

struct ProviderTemplate {
    let kind: String
    let name: String
    let apiType: String
    let baseUrl: String
    let endpointPath: String
    let models: [String]
    let defaultModel: String
    let icon: String
    let apiKeyUrl: String
}

extension ProviderTemplate {
    static let allBuiltins: [ProviderTemplate] = [
        ProviderTemplate(kind: "deepseek", name: "DeepSeek", apiType: "anthropic-messages",
                         baseUrl: "https://api.deepseek.com", endpointPath: "/anthropic/v1/messages",
                         models: ["deepseek-v4-flash", "deepseek-v4-pro"], defaultModel: "deepseek-v4-flash",
                         icon: "D", apiKeyUrl: "https://platform.deepseek.com/api_keys"),
        ProviderTemplate(kind: "minimax", name: "MiniMax", apiType: "anthropic-messages",
                         baseUrl: "https://api.minimaxi.com", endpointPath: "/anthropic/v1/messages",
                         models: ["MiniMax-M2", "MiniMax-M2.5", "MiniMax-M2.7"], defaultModel: "MiniMax-M2.7",
                         icon: "M", apiKeyUrl: "https://platform.minimax.io/subscribe/coding-plan?code=9hgHKlPO3G&source=link"),
        ProviderTemplate(kind: "zhipu", name: "智谱 BigModel", apiType: "anthropic-messages",
                         baseUrl: "https://open.bigmodel.cn", endpointPath: "/api/anthropic/v1/messages",
                         models: ["glm-5.1", "glm-5-turbo", "glm-4.7"], defaultModel: "glm-5.1",
                         icon: "Z", apiKeyUrl: "https://bigmodel.cn/usercenter/apikeys"),
        ProviderTemplate(kind: "volcengine", name: "火山方舟", apiType: "anthropic-messages",
                         baseUrl: "https://ark.cn-beijing.volces.com", endpointPath: "/api/coding/v1/messages",
                         models: ["ark-code-latest"], defaultModel: "ark-code-latest",
                         icon: "V", apiKeyUrl: "https://volcengine.com/L/Sq5rSgyFu_E"),
        ProviderTemplate(kind: "siliconflow", name: "SiliconFlow", apiType: "openai-completions",
                         baseUrl: "https://api.siliconflow.cn", endpointPath: "/v1/chat/completions",
                         models: ["MiniMaxAI/MiniMax-M2.1", "zai-org/GLM-4.7"], defaultModel: "zai-org/GLM-4.7",
                         icon: "S", apiKeyUrl: "https://cloud.siliconflow.com/me/account/ak"),
        ProviderTemplate(kind: "kimi", name: "Kimi (Moonshot)", apiType: "openai-completions",
                         baseUrl: "https://api.moonshot.cn", endpointPath: "/v1/chat/completions",
                         models: ["kimi-k2.6", "moonshot-v1-32k", "moonshot-v1-128k"], defaultModel: "kimi-k2.6",
                         icon: "K", apiKeyUrl: "https://platform.moonshot.cn/console/api-keys"),
        ProviderTemplate(kind: "qwen", name: "通义千问", apiType: "openai-completions",
                         baseUrl: "https://dashscope.aliyuncs.com", endpointPath: "/compatible-mode/v1/chat/completions",
                         models: ["qwen3.6-plus", "qwen-plus", "qwen-turbo"], defaultModel: "qwen3.6-plus",
                         icon: "Q", apiKeyUrl: "https://dashscope.console.aliyun.com/apiKey"),
    ]
}

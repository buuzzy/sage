import Foundation

/// 本地设置管理 — Provider 列表和 DMG 桌面版完全一致
class SettingsService: ObservableObject {
    static let shared = SettingsService()

    @Published var currentSettings: AppSettings

    private let defaults = UserDefaults.standard
    private let settingsKey = "sage_settings_v2"

    private init() {
        if let data = defaults.data(forKey: settingsKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            currentSettings = settings
        } else {
            currentSettings = AppSettings()
        }
        // 迁移：确保新增的 Provider 出现在列表中
        migrateNewProviders()
    }

    /// 将 allDefaults 中新增的 Provider 追加到用户已有列表；同时更新已有 Provider 的模型列表
    private func migrateNewProviders() {
        let existingIds = Set(currentSettings.providers.map(\.id))
        var changed = false

        for (index, defaultProvider) in ProviderConfig.allDefaults.enumerated() {
            if !existingIds.contains(defaultProvider.id) {
                // 新 Provider 插入到对应位置
                let insertAt = min(index, currentSettings.providers.count)
                currentSettings.providers.insert(defaultProvider, at: insertAt)
                changed = true
            } else if let existingIdx = currentSettings.providers.firstIndex(where: { $0.id == defaultProvider.id }) {
                // 已有 Provider — 更新模型列表（保留用户的 apiKey 和其他自定义配置）
                let existing = currentSettings.providers[existingIdx]
                if existing.models != defaultProvider.models {
                    currentSettings.providers[existingIdx].models = defaultProvider.models
                    currentSettings.providers[existingIdx].defaultModel = defaultProvider.defaultModel
                    changed = true
                }
            }
        }
        if changed { save() }
    }

    func save() {
        if let data = try? JSONEncoder().encode(currentSettings) {
            defaults.set(data, forKey: settingsKey)
        }
        objectWillChange.send()
    }

    var isModelConfigured: Bool {
        guard let config = currentSettings.modelConfig else { return false }
        guard let key = config.apiKey, !key.isEmpty else { return false }
        return true
    }
}

/// App 设置模型
struct AppSettings: Codable {
    var modelConfig: ModelConfig?
    var defaultProvider: String?
    var defaultModel: String?
    var theme: String = "system" // light, dark, system
    var providers: [ProviderConfig] = ProviderConfig.allDefaults
}

/// Provider 配置 — 和 DMG 桌面版 defaultProviders 完全一致
struct ProviderConfig: Codable, Identifiable {
    var id: String
    var name: String
    var apiKey: String?
    var baseUrl: String?
    var models: [String]
    var defaultModel: String?
    var apiType: String? // "openai-completions" or "anthropic-messages"
    var icon: String
    var apiKeyUrl: String?
    var canDelete: Bool?

    /// DMG 桌面版全部默认 Provider（9 个）
    static let allDefaults: [ProviderConfig] = [
        ProviderConfig(
            id: "deepseek",
            name: "DeepSeek",
            baseUrl: "https://api.deepseek.com/v1",
            models: ["deepseek-v4-flash", "deepseek-v4-pro"],
            defaultModel: "deepseek-v4-flash",
            apiType: "openai-completions",
            icon: "D",
            apiKeyUrl: "https://platform.deepseek.com/api_keys",
            canDelete: true
        ),
        ProviderConfig(
            id: "openrouter",
            name: "OpenRouter",
            baseUrl: "https://openrouter.ai/api",
            models: ["anthropic/claude-sonnet-4.5", "anthropic/claude-opus-4.5"],
            apiType: "openai-completions",
            icon: "O",
            apiKeyUrl: "https://openrouter.ai/keys",
            canDelete: true
        ),
        ProviderConfig(
            id: "minimax",
            name: "MiniMax",
            baseUrl: "https://api.minimaxi.com/anthropic",
            models: ["MiniMax-M2", "MiniMax-M2.5", "MiniMax-M2.5-highspeed", "MiniMax-M2.7", "MiniMax-M2.7-highspeed"],
            defaultModel: "MiniMax-M2",
            apiType: "anthropic-messages",
            icon: "M",
            apiKeyUrl: "https://platform.minimax.io/subscribe/coding-plan?code=9hgHKlPO3G&source=link",
            canDelete: true
        ),
        ProviderConfig(
            id: "zai",
            name: "Z.ai",
            baseUrl: "https://api.z.ai/api/anthropic",
            models: ["glm-4.7"],
            apiType: "anthropic-messages",
            icon: "Z",
            apiKeyUrl: "https://z.ai/subscribe?ic=7YS469UOXD",
            canDelete: true
        ),
        ProviderConfig(
            id: "volcengine",
            name: "Volcengine",
            baseUrl: "https://ark.cn-beijing.volces.com/api/coding",
            models: ["ark-code-latest"],
            apiType: "openai-completions",
            icon: "V",
            apiKeyUrl: "https://volcengine.com/L/Sq5rSgyFu_E",
            canDelete: true
        ),
        ProviderConfig(
            id: "302ai",
            name: "302.AI",
            baseUrl: "https://api.302.ai/cc",
            models: ["claude-sonnet-4-5-20250929"],
            apiType: "anthropic-messages",
            icon: "3",
            apiKeyUrl: "https://302.ai/?utm_source=sage_desktop",
            canDelete: true
        ),
        ProviderConfig(
            id: "ollama",
            name: "Ollama",
            baseUrl: "http://localhost:11434",
            models: ["glm-4.7-flash"],
            apiType: "openai-completions",
            icon: "O",
            apiKeyUrl: "https://docs.ollama.com/integrations/claude-code",
            canDelete: true
        ),
        ProviderConfig(
            id: "siliconflow",
            name: "SiliconFlow",
            baseUrl: "https://api.siliconflow.com/",
            models: ["MiniMaxAI/MiniMax-M2.1", "zai-org/GLM-4.7"],
            apiType: "openai-completions",
            icon: "S",
            apiKeyUrl: "https://cloud.siliconflow.com/me/account/ak",
            canDelete: true
        ),
        ProviderConfig(
            id: "kimi",
            name: "Kimi (Moonshot)",
            baseUrl: "https://api.moonshot.cn/v1",
            models: ["moonshot-v1-8k", "moonshot-v1-32k", "moonshot-v1-128k"],
            apiType: "openai-completions",
            icon: "K",
            apiKeyUrl: "https://platform.moonshot.cn/console/api-keys",
            canDelete: true
        ),
    ]
}

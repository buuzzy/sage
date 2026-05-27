import Foundation

/// 本地设置管理（Phase 0 — 最小骨架版）
///
/// 仅作为云端化改造期间的占位实现。未来 Phase 4 会把 providers 数据源换成 Supabase
/// `user_providers` 表，本类将被 CloudProviderStore 接管。当前版本只满足：
/// 1. 现有 ViewModel 引用的 `currentSettings.modelConfig / defaultProvider / providers / theme` 不爆
/// 2. 简单 UserDefaults 持久化
/// 3. 提供 7 家内置 Provider 的最终端点表（一次到位，避免后面再迁移）
///
/// 已删除的旧逻辑（Phase 0 清理）：
/// - chatCompletionsPath / messagesPath（无效字段）
/// - ProviderEndpointResolver（启发式拼接）
/// - migrateFromLegacy / sage_settings_v2/v3 schema bump
/// - resetProviderToDefault（兜底按钮）
class SettingsService: ObservableObject {
    static let shared = SettingsService()

    @Published var currentSettings: AppSettings

    private let defaults = UserDefaults.standard
    private let settingsKey = "sage_settings_v4"

    private init() {
        if let data = defaults.data(forKey: settingsKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            currentSettings = settings
        } else {
            currentSettings = AppSettings()
        }
        // 始终把内置 Provider 列表对齐到最新默认（保留用户已填的 apiKey）
        reconcileBuiltinProviders()
    }

    /// 把内置 Provider 列表对齐到最新默认值，保留用户已填的 apiKey 和 defaultModel。
    private func reconcileBuiltinProviders() {
        var changed = false
        var newProviders: [ProviderConfig] = []
        for builtin in ProviderConfig.allDefaults {
            if let userCopy = currentSettings.providers.first(where: { $0.id == builtin.id }) {
                var merged = builtin
                merged.apiKey = userCopy.apiKey
                if let m = userCopy.defaultModel, builtin.models.contains(m) {
                    merged.defaultModel = m
                }
                newProviders.append(merged)
                if merged != userCopy { changed = true }
            } else {
                newProviders.append(builtin)
                changed = true
            }
        }
        // 保留用户自定义 provider（custom-*）
        let customs = currentSettings.providers.filter { $0.id.hasPrefix("custom-") }
        newProviders.append(contentsOf: customs)
        currentSettings.providers = newProviders
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

/// Provider 配置（Phase 0 简化版 — 不再含 chatCompletionsPath/messagesPath，
/// 路径拼接交给后端 buildEndpointUrl 处理）
struct ProviderConfig: Codable, Identifiable, Equatable {
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

    /// 7 家内置 Provider + 终端端点（已逐家核对官方文档 2026-05-27）
    /// baseUrl 形态遵循后端 `buildEndpointUrl` 约定：直接附带版本路径，testConnection
    /// 时拼 /chat/completions 或 /messages 即可。
    static let allDefaults: [ProviderConfig] = [
        // —— Anthropic 协议 ——
        ProviderConfig(
            id: "deepseek",
            name: "DeepSeek",
            baseUrl: "https://api.deepseek.com/anthropic/v1",
            models: ["deepseek-v4-flash", "deepseek-v4-pro"],
            defaultModel: "deepseek-v4-flash",
            apiType: "anthropic-messages",
            icon: "D",
            apiKeyUrl: "https://platform.deepseek.com/api_keys",
            canDelete: true
        ),
        ProviderConfig(
            id: "minimax",
            name: "MiniMax",
            baseUrl: "https://api.minimaxi.com/anthropic/v1",
            models: ["MiniMax-M2", "MiniMax-M2.5", "MiniMax-M2.7"],
            defaultModel: "MiniMax-M2.7",
            apiType: "anthropic-messages",
            icon: "M",
            apiKeyUrl: "https://platform.minimax.io/subscribe/coding-plan?code=9hgHKlPO3G&source=link",
            canDelete: true
        ),
        ProviderConfig(
            id: "zhipu",
            name: "智谱 BigModel",
            baseUrl: "https://open.bigmodel.cn/api/anthropic/v1",
            models: ["glm-5.1", "glm-5-turbo", "glm-4.7"],
            defaultModel: "glm-5.1",
            apiType: "anthropic-messages",
            icon: "Z",
            apiKeyUrl: "https://open.bigmodel.cn/usercenter/apikeys",
            canDelete: true
        ),
        ProviderConfig(
            id: "volcengine",
            name: "火山方舟",
            baseUrl: "https://ark.cn-beijing.volces.com/api/coding/v1",
            models: ["ark-code-latest"],
            defaultModel: "ark-code-latest",
            apiType: "anthropic-messages",
            icon: "V",
            apiKeyUrl: "https://volcengine.com/L/Sq5rSgyFu_E",
            canDelete: true
        ),

        // —— OpenAI 协议 ——
        ProviderConfig(
            id: "siliconflow",
            name: "SiliconFlow",
            baseUrl: "https://api.siliconflow.cn/v1",
            models: ["MiniMaxAI/MiniMax-M2.1", "zai-org/GLM-4.7"],
            defaultModel: "zai-org/GLM-4.7",
            apiType: "openai-completions",
            icon: "S",
            apiKeyUrl: "https://cloud.siliconflow.cn/me/account/ak",
            canDelete: true
        ),
        ProviderConfig(
            id: "kimi",
            name: "Kimi (Moonshot)",
            baseUrl: "https://api.moonshot.cn/v1",
            models: ["kimi-k2.6", "moonshot-v1-32k", "moonshot-v1-128k"],
            defaultModel: "kimi-k2.6",
            apiType: "openai-completions",
            icon: "K",
            apiKeyUrl: "https://platform.moonshot.cn/console/api-keys",
            canDelete: true
        ),
        ProviderConfig(
            id: "qwen",
            name: "通义千问",
            baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            models: ["qwen3.6-plus", "qwen-plus", "qwen-turbo"],
            defaultModel: "qwen3.6-plus",
            apiType: "openai-completions",
            icon: "Q",
            apiKeyUrl: "https://bailian.console.aliyun.com/?apiKey=1",
            canDelete: true
        ),
    ]
}

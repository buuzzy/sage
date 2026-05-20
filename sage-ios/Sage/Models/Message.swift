import Foundation

/// SSE 事件类型
enum SSEEventType: String, Codable {
    case text
    case toolUse = "tool_use"
    case toolResult = "tool_result"
    case plan
    case error
    case done
    case result
    case directAnswer = "direct_answer"
    case permissionRequest = "permission_request"
    case session
    case sessionAction = "session_action"
    case compactResult = "compact_result"
}

/// SSE 事件数据
struct SSEEvent: Codable {
    let type: SSEEventType
    var content: String?
    var name: String?       // tool name
    var id: String?         // tool_use id
    var input: AnyCodable?  // tool input
    var subtype: String?
    var cost: Double?
    var duration: Int?
    var message: String?    // error message
    var sessionId: String?
    var plan: PlanData?
    var output: String?     // tool_result output
    var toolUseId: String?
    var isError: Bool?
    var permission: PermissionRequestData?  // permission_request 数据

    enum CodingKeys: String, CodingKey {
        case type, content, name, id, input, subtype, cost, duration
        case message, sessionId, plan, output, toolUseId, isError, permission
    }
}

/// 权限请求数据
struct PermissionRequestData: Codable, Identifiable {
    let id: String
    let tool: String?          // 请求执行的工具名
    let description: String?   // 描述
    let command: String?       // 具体命令
}

/// 计划数据
struct PlanData: Codable {
    let id: String
    let goal: String
    let steps: [PlanStep]
    var notes: String?
}

struct PlanStep: Codable, Identifiable {
    let id: String
    let description: String
    var status: String // pending, in_progress, completed, failed
}

/// Agent 请求体
struct AgentRequest: Codable {
    let prompt: String
    var workDir: String?
    var taskId: String?
    var modelConfig: ModelConfig?
    var sandboxConfig: SandboxConfig?
    var skillsConfig: SkillsConfig?
    var mcpConfig: MCPConfig?
    var language: String?
    var userId: String?
    var accessToken: String?
    var conversation: [ConversationMessage]?
    var images: [ImageAttachment]?
    var planId: String?  // 用于 /agent/execute
}

struct ModelConfig: Codable {
    var apiKey: String?
    var baseUrl: String?
    var model: String?
    var apiType: String?
}

struct SandboxConfig: Codable {
    var enabled: Bool
    var provider: String?
    var apiEndpoint: String?
}

struct SkillsConfig: Codable {
    var enabled: Bool
    var userDirEnabled: Bool?
    var appDirEnabled: Bool?
    var skillsPath: String?
}

struct MCPConfig: Codable {
    var enabled: Bool
    var userDirEnabled: Bool?
    var appDirEnabled: Bool?
    var mcpConfigPath: String?
}

struct ConversationMessage: Codable {
    let role: String  // "user" or "assistant"
    let content: String
}

struct ImageAttachment: Codable {
    let data: String
    let mediaType: String
}

/// 通用 JSON 值包装（处理 input 等 any 类型字段）
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let arr = try? container.decode([AnyCodable].self) {
            value = arr.map { $0.value }
        } else if let str = try? container.decode(String.self) {
            value = str
        } else if let num = try? container.decode(Double.self) {
            value = num
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let num = value as? Double { try container.encode(num) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else { try container.encodeNil() }
    }
}

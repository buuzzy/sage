import Foundation
import SwiftUI

// MARK: - Display Group Model (matches DMG desktop TaskMessageGroup)

/// 显示分组 — 对标桌面端 TaskMessageGroup 架构
/// AI 回复不再逐条渲染，而是分组为：用户消息 / 任务组（文字+工具列表）/ 纯文本 / 计划 / 错误
enum DisplayGroup: Identifiable {
    case userMessage(id: UUID, content: String)
    case taskGroup(id: UUID, title: String, tools: [ToolCallItem], isComplete: Bool)
    case assistantText(id: UUID, content: String, isStreaming: Bool)
    case plan(id: UUID, data: PlanData)
    case error(id: UUID, message: String)

    var id: UUID {
        switch self {
        case .userMessage(let id, _): return id
        case .taskGroup(let id, _, _, _): return id
        case .assistantText(let id, _, _): return id
        case .plan(let id, _): return id
        case .error(let id, _): return id
        }
    }
}

/// 工具调用记录
struct ToolCallItem: Identifiable {
    let id: String // use tool_use event id for matching
    let name: String
    var input: String?
    var output: String?
    var isError: Bool = false
    var isComplete: Bool = false
}

/// Artifact 数据
struct ArtifactData: Identifiable {
    let id = UUID()
    let type: String
    let jsonData: String
}

/// 对话 ViewModel — 核心状态管理
/// 维护 displayGroups 代替旧的 messages 列表
@MainActor
class ChatViewModel: ObservableObject {
    @Published var displayGroups: [DisplayGroup] = []
    @Published var isRunning = false
    @Published var currentSessionId: String?
    @Published var currentTitle: String?
    @Published var phase: String = "idle" // idle, planning, awaiting_approval, executing
    @Published var lastToolName: String? // for RunningIndicator dynamic text
    @Published var pendingPermission: PermissionRequestData? = nil // 权限请求弹窗

    /// 事件序号（用于后台恢复补偿）
    private var lastEventSeq: Int = -1
    /// 流是否被后台中断
    private var streamInterrupted = false

    /// 当前待审批的 Plan 数据（用于 approvePlan）
    private var currentPlan: PlanData?
    private var initialPrompt: String = "" // 用户首次发送的 prompt（plan execute 需要）

    private var backendSessionId: String?
    private var streamTask: Task<Void, Never>?

    // ─── 分组状态机 ───────────────────────────────────────────
    // 收到 text 时暂存到 pendingText；收到 tool_use 时，如果有 pendingText 则创建 TaskGroup
    private var pendingText: String = ""
    private var currentTaskGroupIndex: Int? = nil // 当前正在累积工具的 TaskGroup 索引

    /// Callback to notify SessionListViewModel about session changes
    var onSessionCreated: ((SessionItem) -> Void)?
    var onSessionTitleUpdated: ((String, String) -> Void)?

    // MARK: - Persistence Keys
    private static let sessionsKey = "sage_sessions_v1"
    private static let messagesKeyPrefix = "sage_messages_"

    // MARK: - Legacy compatibility
    /// 暴露 messages（供 MainView 判断 isEmpty）
    var messages: [DisplayGroup] { displayGroups }

    // MARK: - Public API

    func sendMessage(_ prompt: String) async {
        // Create session on first message
        if currentSessionId == nil {
            let newId = UUID().uuidString
            currentSessionId = newId
            let session = SessionItem(id: newId, title: String(prompt.prefix(30)), lastMessage: prompt, createdAt: Date())
            onSessionCreated?(session)
            saveSessionToStorage(session)
        }

        // Add user message group
        displayGroups.append(.userMessage(id: UUID(), content: prompt))

        // 保存初始 prompt（plan execute 需要）
        if initialPrompt.isEmpty {
            initialPrompt = prompt
        }

        isRunning = true
        phase = "executing"
        pendingText = ""
        currentTaskGroupIndex = nil
        lastToolName = nil

        // Build request with conversation history
        let settings = SettingsService.shared.currentSettings
        let conversation = buildConversationHistory()
        let request = AgentRequest(
            prompt: prompt,
            taskId: currentSessionId ?? UUID().uuidString,
            modelConfig: settings.modelConfig,
            language: "zh-CN",
            userId: AuthService.shared.userId,
            accessToken: await AuthService.shared.getAccessToken(),
            conversation: conversation.isEmpty ? nil : conversation
        )

        // Start streaming
        streamTask = Task {
            do {
                let stream = await APIClient.shared.streamAgent(request: request)
                for try await event in stream {
                    handleSSEEvent(event)
                }
            } catch {
                if !Task.isCancelled {
                    displayGroups.append(.error(id: UUID(), message: error.localizedDescription))
                }
            }

            // Finalize: if there's pending text that wasn't yet emitted as a group
            finalizePendingText()

            isRunning = false
            phase = "idle"
            lastToolName = nil

            // Mark last assistantText as not streaming
            finalizeStreaming()

            // Save messages
            saveMessagesToStorage()

            // Generate title for first user message
            let userMessageCount = displayGroups.filter {
                if case .userMessage = $0 { return true }
                return false
            }.count
            if userMessageCount == 1 {
                await generateTitle(for: prompt)
            }
        }
    }

    func stopGeneration() {
        streamTask?.cancel()
        streamTask = nil
        isRunning = false
        phase = "idle"
        lastToolName = nil
        finalizePendingText()
        finalizeStreaming()
        if let sessionId = backendSessionId {
            Task {
                try? await APIClient.shared.stopSession(sessionId)
            }
        }
    }

    // MARK: - Plan Approval (对标桌面端 approvePlan / rejectPlan)

    /// 批准计划 → 调用 /agent/execute
    func approvePlan() async {
        guard let plan = currentPlan, phase == "awaiting_approval" else { return }

        isRunning = true
        phase = "executing"
        pendingText = ""
        currentTaskGroupIndex = nil
        lastToolName = nil

        let settings = SettingsService.shared.currentSettings
        let request = AgentRequest(
            prompt: initialPrompt,
            taskId: currentSessionId ?? UUID().uuidString,
            modelConfig: settings.modelConfig,
            language: "zh-CN",
            userId: AuthService.shared.userId,
            accessToken: await AuthService.shared.getAccessToken(),
            planId: plan.id
        )

        streamTask = Task {
            do {
                let stream = await APIClient.shared.streamExecute(request: request)
                for try await event in stream {
                    handleSSEEvent(event)
                }
            } catch {
                if !Task.isCancelled {
                    displayGroups.append(.error(id: UUID(), message: error.localizedDescription))
                }
            }
            isRunning = false
            phase = "idle"
            lastToolName = nil
            finalizeStreaming()
            closeCurrentTaskGroup()
            saveMessagesToStorage()
        }
    }

    /// 拒绝计划
    func rejectPlan() {
        currentPlan = nil
        phase = "idle"
        displayGroups.append(.assistantText(id: UUID(), content: "计划已取消。", isStreaming: false))
        saveMessagesToStorage()
    }

    // MARK: - Permission Request (对标桌面端 respondToPermission)

    /// 响应权限请求
    func respondToPermission(permissionId: String, approved: Bool) async {
        guard let sessionId = backendSessionId else { return }

        do {
            try await APIClient.shared.respondToPermission(
                sessionId: sessionId,
                permissionId: permissionId,
                approved: approved
            )
        } catch {
            displayGroups.append(.error(id: UUID(), message: "权限响应失败: \(error.localizedDescription)"))
        }

        pendingPermission = nil

        // 添加响应消息
        let msg = approved ? "权限已授予，继续执行..." : "权限已拒绝，操作已取消。"
        displayGroups.append(.assistantText(id: UUID(), content: msg, isStreaming: false))
    }

    // MARK: - Background Resume (iOS 后台恢复补偿)

    /// APP 回到前台时调用 — 检查是否有中断的流，如果有则拉取缺失事件
    func resumeFromBackground() {
        guard let taskId = currentSessionId, streamInterrupted || isRunning else { return }

        Task {
            do {
                let data = try await APIClient.shared.getTaskEvents(taskId: taskId, afterSeq: lastEventSeq)
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let events = json["events"] as? [[String: Any]],
                      let isComplete = json["isComplete"] as? Bool else { return }

                // 处理缺失事件
                for eventDict in events {
                    if let seq = eventDict["seq"] as? Int {
                        lastEventSeq = seq
                    }
                    if let eventData = eventDict["data"] as? [String: Any],
                       let jsonData = try? JSONSerialization.data(withJSONObject: eventData),
                       let event = try? JSONDecoder().decode(SSEEvent.self, from: jsonData) {
                        handleSSEEvent(event)
                    }
                }

                // 如果 task 已完成，更新状态
                if isComplete {
                    isRunning = false
                    phase = "idle"
                    lastToolName = nil
                    streamInterrupted = false
                    finalizeStreaming()
                    closeCurrentTaskGroup()
                    saveMessagesToStorage()
                }
            } catch {
                // 补偿失败不报错，用户可以手动重新发送
                streamInterrupted = false
            }
        }
    }

    /// APP 进入后台时标记
    func willEnterBackground() {
        if isRunning {
            streamInterrupted = true
        }
    }

    func startNewChat() {
        displayGroups = []
        currentSessionId = nil
        currentTitle = nil
        backendSessionId = nil
        phase = "idle"
        isRunning = false
        pendingText = ""
        currentTaskGroupIndex = nil
        lastToolName = nil
        currentPlan = nil
        initialPrompt = ""
        pendingPermission = nil
    }

    func loadSession(_ sessionId: String) {
        currentSessionId = sessionId
        loadMessagesFromStorage(sessionId: sessionId)
    }

    // MARK: - Conversation History (多轮对话上下文)

    /// 从 displayGroups 构建对话历史，发送给后端以保持上下文
    private func buildConversationHistory() -> [ConversationMessage] {
        var messages: [ConversationMessage] = []
        for group in displayGroups {
            switch group {
            case .userMessage(_, let content):
                messages.append(ConversationMessage(role: "user", content: content))
            case .assistantText(_, let content, _):
                if !content.isEmpty {
                    messages.append(ConversationMessage(role: "assistant", content: content))
                }
            case .taskGroup(_, let title, let tools, _):
                // 将 TaskGroup 的标题+工具摘要作为 assistant 消息
                var summary = title
                let toolNames = tools.map { $0.name }.joined(separator: ", ")
                if !toolNames.isEmpty {
                    summary += " [使用工具: \(toolNames)]"
                }
                if !summary.isEmpty {
                    messages.append(ConversationMessage(role: "assistant", content: summary))
                }
            case .error, .plan:
                break
            }
        }
        return messages
    }

    // MARK: - SSE Event Handling (分组状态机)

    private func handleSSEEvent(_ event: SSEEvent) {
        switch event.type {
        case .text, .directAnswer:
            guard let content = event.content, !content.isEmpty else { return }

            if currentTaskGroupIndex != nil {
                // 如果当前有 TaskGroup 正在累积工具，说明新的 text 是"下一段"的开始
                // 关闭当前 TaskGroup
                closeCurrentTaskGroup()
            }

            // 追加到 pending text 或追加到已存在的 assistantText group
            if let lastIdx = lastAssistantTextIndex() {
                // 追加到已存在的 assistantText
                if case .assistantText(let id, let existingContent, _) = displayGroups[lastIdx] {
                    displayGroups[lastIdx] = .assistantText(id: id, content: existingContent + content, isStreaming: true)
                }
            } else {
                // 先把 pendingText 输出（如果有未输出的）
                // 创建新的 assistantText group
                let newId = UUID()
                displayGroups.append(.assistantText(id: newId, content: content, isStreaming: true))
            }
            pendingText += content

        case .session:
            if let sid = event.sessionId {
                backendSessionId = sid
            }

        case .plan:
            if let plan = event.plan {
                finalizePendingText()
                currentPlan = plan  // 保存用于 approvePlan
                displayGroups.append(.plan(id: UUID(), data: plan))
                phase = "awaiting_approval"
            }

        case .permissionRequest:
            // 后端请求权限确认
            if let permission = event.permission {
                pendingPermission = permission
            }

        case .error:
            let errorMsg = event.message ?? "未知错误"
            displayGroups.append(.error(id: UUID(), message: errorMsg))

        case .toolUse:
            let toolName = event.name ?? "工具"
            lastToolName = toolName

            let inputStr: String? = {
                if let input = event.input {
                    if let data = try? JSONSerialization.data(withJSONObject: input.value, options: []),
                       let str = String(data: data, encoding: .utf8) {
                        return str
                    }
                }
                return nil
            }()

            let toolItem = ToolCallItem(
                id: event.id ?? UUID().uuidString,
                name: toolName,
                input: inputStr
            )

            if let taskIdx = currentTaskGroupIndex {
                // 追加到当前 TaskGroup
                if case .taskGroup(let gId, let title, var tools, _) = displayGroups[taskIdx] {
                    tools.append(toolItem)
                    displayGroups[taskIdx] = .taskGroup(id: gId, title: title, tools: tools, isComplete: false)
                }
            } else {
                // 创建新的 TaskGroup
                // title 取之前累积的 pendingText（AI 描述文字）
                let title = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)

                // 如果之前有 assistantText group 作为这个 TaskGroup 的标题，移除它
                if let lastTextIdx = lastAssistantTextIndex() {
                    displayGroups.remove(at: lastTextIdx)
                }

                let newGroup = DisplayGroup.taskGroup(
                    id: UUID(),
                    title: title.isEmpty ? toolName : title,
                    tools: [toolItem],
                    isComplete: false
                )
                displayGroups.append(newGroup)
                currentTaskGroupIndex = displayGroups.count - 1
                pendingText = ""
            }

        case .toolResult:
            // 更新对应 tool 的状态
            if let taskIdx = currentTaskGroupIndex {
                if case .taskGroup(let gId, let title, var tools, _) = displayGroups[taskIdx] {
                    // Match by toolUseId or update last incomplete tool
                    let targetId = event.toolUseId
                    if let toolIdx = tools.lastIndex(where: { targetId != nil ? $0.id == targetId : !$0.isComplete }) {
                        tools[toolIdx].output = event.output
                        tools[toolIdx].isError = event.isError ?? false
                        tools[toolIdx].isComplete = true
                        displayGroups[taskIdx] = .taskGroup(id: gId, title: title, tools: tools, isComplete: false)
                    }
                }
            }

        case .result, .done:
            // 流结束 — 关闭所有 pending 状态
            closeCurrentTaskGroup()

        default:
            break
        }
    }

    // MARK: - State Machine Helpers

    /// 关闭当前 TaskGroup（标记为 complete）
    private func closeCurrentTaskGroup() {
        if let taskIdx = currentTaskGroupIndex, taskIdx < displayGroups.count {
            if case .taskGroup(let gId, let title, let tools, _) = displayGroups[taskIdx] {
                displayGroups[taskIdx] = .taskGroup(id: gId, title: title, tools: tools, isComplete: true)
            }
        }
        currentTaskGroupIndex = nil
    }

    /// 将 pendingText 刷出为 assistantText（如果尚未输出）
    private func finalizePendingText() {
        // pendingText 在 text 事件中已经通过 lastAssistantTextIndex 实时追加到 displayGroups 了
        // 这里只需要清理状态
        pendingText = ""
    }

    /// 标记最后一个 assistantText 为非 streaming
    private func finalizeStreaming() {
        for i in (0..<displayGroups.count).reversed() {
            if case .assistantText(let id, let content, let streaming) = displayGroups[i], streaming {
                displayGroups[i] = .assistantText(id: id, content: content, isStreaming: false)
            }
        }
    }

    /// 找到最后一个 assistantText group 的索引（必须是列表末尾的，中间不能有其他类型）
    private func lastAssistantTextIndex() -> Int? {
        guard let lastIdx = displayGroups.indices.last else { return nil }
        if case .assistantText = displayGroups[lastIdx] {
            return lastIdx
        }
        return nil
    }

    // MARK: - Title Generation

    private func generateTitle(for prompt: String) async {
        do {
            let settings = SettingsService.shared.currentSettings
            let title = try await APIClient.shared.generateTitle(
                prompt: prompt,
                modelConfig: settings.modelConfig,
                language: "zh-CN"
            )
            if !title.isEmpty && title != prompt {
                currentTitle = title
                if let sessionId = currentSessionId {
                    onSessionTitleUpdated?(sessionId, title)
                    updateSessionTitleInStorage(sessionId: sessionId, title: title)
                }
            }
        } catch {
            if currentTitle == nil, let sessionId = currentSessionId {
                currentTitle = String(prompt.prefix(30))
                onSessionTitleUpdated?(sessionId, currentTitle ?? "")
            }
        }
    }

    // MARK: - Local Persistence (UserDefaults)

    private func saveSessionToStorage(_ session: SessionItem) {
        var allSessions = Self.loadAllSessionsFromStorage()
        allSessions.removeAll { $0.id == session.id }
        allSessions.insert(session, at: 0)
        Self.saveAllSessionsToStorage(allSessions)
    }

    private func updateSessionTitleInStorage(sessionId: String, title: String) {
        var allSessions = Self.loadAllSessionsFromStorage()
        if let idx = allSessions.firstIndex(where: { $0.id == sessionId }) {
            allSessions[idx].title = title
            Self.saveAllSessionsToStorage(allSessions)
        }
    }

    private func saveMessagesToStorage() {
        guard let sessionId = currentSessionId else { return }
        let key = Self.messagesKeyPrefix + sessionId
        let storable = displayGroups.compactMap { group -> StorableMessage? in
            switch group {
            case .userMessage(_, let content):
                return StorableMessage(type: "user", content: content, title: nil, toolsJson: nil)
            case .assistantText(_, let content, _):
                return StorableMessage(type: "assistant_text", content: content, title: nil, toolsJson: nil)
            case .taskGroup(_, let title, let tools, _):
                let toolsData = tools.map { StorableTool(id: $0.id, name: $0.name, input: $0.input, output: $0.output, isError: $0.isError) }
                let toolsJson = (try? JSONEncoder().encode(toolsData)).flatMap { String(data: $0, encoding: .utf8) }
                return StorableMessage(type: "task_group", content: nil, title: title, toolsJson: toolsJson)
            case .plan(_, let data):
                let planJson = (try? JSONEncoder().encode(data)).flatMap { String(data: $0, encoding: .utf8) }
                return StorableMessage(type: "plan", content: planJson, title: nil, toolsJson: nil)
            case .error(_, let message):
                return StorableMessage(type: "error", content: message, title: nil, toolsJson: nil)
            }
        }
        if let data = try? JSONEncoder().encode(storable) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadMessagesFromStorage(sessionId: String) {
        let key = Self.messagesKeyPrefix + sessionId
        guard let data = UserDefaults.standard.data(forKey: key),
              let storable = try? JSONDecoder().decode([StorableMessage].self, from: data) else {
            displayGroups = []
            return
        }
        displayGroups = storable.compactMap { msg -> DisplayGroup? in
            switch msg.type {
            case "user":
                return .userMessage(id: UUID(), content: msg.content ?? "")
            case "assistant_text":
                return .assistantText(id: UUID(), content: msg.content ?? "", isStreaming: false)
            case "task_group":
                var tools: [ToolCallItem] = []
                if let toolsJson = msg.toolsJson,
                   let toolsData = toolsJson.data(using: .utf8),
                   let decoded = try? JSONDecoder().decode([StorableTool].self, from: toolsData) {
                    tools = decoded.map { ToolCallItem(id: $0.id, name: $0.name, input: $0.input, output: $0.output, isError: $0.isError, isComplete: true) }
                }
                return .taskGroup(id: UUID(), title: msg.title ?? "", tools: tools, isComplete: true)
            case "plan":
                if let content = msg.content, let planData = content.data(using: .utf8),
                   let plan = try? JSONDecoder().decode(PlanData.self, from: planData) {
                    return .plan(id: UUID(), data: plan)
                }
                return nil
            case "error":
                return .error(id: UUID(), message: msg.content ?? "未知错误")
            default:
                return nil
            }
        }
    }

    static func loadAllSessionsFromStorage() -> [SessionItem] {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let items = try? JSONDecoder().decode([StorableSession].self, from: data) else {
            return []
        }
        return items.map { SessionItem(id: $0.id, title: $0.title, lastMessage: $0.lastMessage, createdAt: Date(timeIntervalSince1970: $0.createdAt)) }
    }

    static func saveAllSessionsToStorage(_ sessions: [SessionItem]) {
        let storable = sessions.map { StorableSession(id: $0.id, title: $0.title, lastMessage: $0.lastMessage, createdAt: $0.createdAt.timeIntervalSince1970) }
        if let data = try? JSONEncoder().encode(storable) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
}

// MARK: - Storage Models

private struct StorableMessage: Codable {
    let type: String
    let content: String?
    let title: String?
    let toolsJson: String?
}

private struct StorableTool: Codable {
    let id: String
    let name: String
    let input: String?
    let output: String?
    let isError: Bool
}

private struct StorableSession: Codable {
    let id: String
    let title: String
    let lastMessage: String?
    let createdAt: Double
}

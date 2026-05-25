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

    /// Plan steps 进度追踪
    private var completedToolCount: Int = 0
    private var totalToolCount: Int = 0

    private var backendSessionId: String?
    private var streamTask: Task<Void, Never>?
    private var retryCount: Int = 0

    // ─── 分组状态机 ───────────────────────────────────────────
    // 收到 text 时暂存到 pendingText；收到 tool_use 时用 pendingText 创建/更新 TaskGroup
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

    // MARK: - Export (对标桌面端 "复制过程")

    /// 导出完整对话为文本（包括工具调用）
    func exportConversationAsText() -> String {
        var parts: [String] = []
        for group in displayGroups {
            switch group {
            case .userMessage(_, let content):
                parts.append("👤 用户:\n\(content)")
            case .assistantText(_, let content, _):
                if !content.isEmpty {
                    parts.append("🤖 Sage:\n\(content)")
                }
            case .taskGroup(_, let title, let tools, _):
                var taskText = "🔧 \(title)"
                for tool in tools {
                    taskText += "\n  ├ \(tool.name)"
                    if let input = tool.input { taskText += ": \(String(input.prefix(100)))" }
                    taskText += tool.isComplete ? (tool.isError ? " ❌" : " ✅") : " ⏳"
                }
                parts.append(taskText)
            case .plan(_, let data):
                var planText = "📋 计划: \(data.goal)"
                for step in data.steps {
                    let icon = step.status == "completed" ? "✅" : (step.status == "in_progress" ? "🔄" : "⬜")
                    planText += "\n  \(icon) \(step.description)"
                }
                parts.append(planText)
            case .error(_, let message):
                parts.append("⚠️ 错误: \(message)")
            }
        }
        return parts.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Public API

    func sendMessage(_ prompt: String, images: [SelectedImage] = []) async {
        // Create session on first message
        if currentSessionId == nil {
            let newId = UUID().uuidString
            currentSessionId = newId
            let sessionTitle = String(prompt.prefix(30))
            currentTitle = sessionTitle
            let session = SessionItem(id: newId, title: sessionTitle, lastMessage: prompt, createdAt: Date())
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
        retryCount = 0
        completedToolCount = 0
        totalToolCount = 0

        // Build request with conversation history
        let settings = SettingsService.shared.currentSettings
        let conversation = buildConversationHistory()
        let imageAttachments: [ImageAttachment]? = images.isEmpty ? nil : images.map {
            ImageAttachment(data: $0.base64, mediaType: $0.mediaType)
        }
        let request = AgentRequest(
            prompt: prompt,
            taskId: currentSessionId ?? UUID().uuidString,
            modelConfig: settings.modelConfig,
            language: "zh-CN",
            userId: AuthService.shared.userId,
            accessToken: await AuthService.shared.getAccessToken(),
            conversation: conversation.isEmpty ? nil : conversation,
            images: imageAttachments
        )

        // Start streaming
        streamTask = Task {
            do {
                let stream = await APIClient.shared.streamAgent(request: request)
                for try await event in stream {
                    handleSSEEvent(event)
                    lastEventSeq += 1
                }
            } catch {
                if !Task.isCancelled {
                    let classified = classifyError(error)
                    if classified.retryable && retryCount < 2 {
                        // 自动重试（最多 2 次）
                        retryCount += 1
                        displayGroups.append(.error(id: UUID(), message: "\(classified.message)（正在重试...）"))
                        try? await Task.sleep(nanoseconds: UInt64(retryCount) * 2_000_000_000)
                        if !Task.isCancelled {
                            do {
                                let retryStream = await APIClient.shared.streamAgent(request: request)
                                for try await event in retryStream {
                                    handleSSEEvent(event)
                                    lastEventSeq += 1
                                }
                            } catch {
                                displayGroups.append(.error(id: UUID(), message: classifyError(error).message))
                            }
                        }
                    } else {
                        displayGroups.append(.error(id: UUID(), message: classified.message))
                    }
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

            pendingText += content

            if currentTaskGroupIndex != nil {
                // 工具 card 已存在时先缓存文本：
                // - 后续出现 tool_use：这段文本替换 card 标题；
                // - 后续直接 done：这段文本作为最终回答输出。
                return
            } else if let lastIdx = lastAssistantTextIndex() {
                // 工具开始前的文本先流式展示；若随后出现 tool_use，会转为 card 标题。
                if case .assistantText(let id, let existingContent, _) = displayGroups[lastIdx] {
                    displayGroups[lastIdx] = .assistantText(id: id, content: existingContent + content, isStreaming: true)
                }
            } else {
                let newId = UUID()
                displayGroups.append(.assistantText(id: newId, content: content, isStreaming: true))
            }

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
            totalToolCount += 1

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
                // 同一轮 Agent 只保留一个 TaskGroup：新工具累加，标题用最新模型执行文本替换。
                if case .taskGroup(let gId, let title, var tools, _) = displayGroups[taskIdx] {
                    tools.append(toolItem)
                    let nextTitle = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    displayGroups[taskIdx] = .taskGroup(
                        id: gId,
                        title: nextTitle.isEmpty ? title : nextTitle,
                        tools: tools,
                        isComplete: false
                    )
                    pendingText = ""
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
            // 更新 Plan steps 进度
            completedToolCount += 1
            updatePlanStepsProgress()

        case .result, .done:
            // 流结束 — 关闭所有 pending 状态
            flushPendingTextAfterTaskGroup()
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

    /// 若工具结束后最后一段 text 没再触发 tool_use，则它是最终回答，应作为 assistantText 输出。
    private func flushPendingTextAfterTaskGroup() {
        guard currentTaskGroupIndex != nil else { return }
        let text = pendingText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            pendingText = ""
            return
        }
        displayGroups.append(.assistantText(id: UUID(), content: text, isStreaming: true))
        pendingText = ""
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

    // MARK: - Error Classification (对标桌面端 classifyFetchError)

    private struct ClassifiedError {
        let category: String
        let message: String
        let retryable: Bool
    }

    private func classifyError(_ error: Error) -> ClassifiedError {
        let msg = error.localizedDescription

        if let apiError = error as? APIError {
            switch apiError {
            case .httpError(let code):
                if code == 401 || code == 403 {
                    return ClassifiedError(category: "auth", message: "认证失败或权限不足", retryable: false)
                }
                if code == 429 {
                    return ClassifiedError(category: "rate_limit", message: "请求过于频繁，请稍后重试", retryable: true)
                }
                if code >= 500 {
                    return ClassifiedError(category: "server_error", message: "服务端错误 (\(code))", retryable: true)
                }
                return ClassifiedError(category: "http", message: "请求失败 (HTTP \(code))", retryable: false)
            case .invalidResponse:
                return ClassifiedError(category: "network", message: "无效响应", retryable: true)
            case .decodingError(let detail):
                return ClassifiedError(category: "decode", message: "数据解析失败: \(detail)", retryable: false)
            }
        }

        if msg.contains("network") || msg.contains("connection") || msg.contains("NSURLError") {
            return ClassifiedError(category: "network", message: "网络连接失败，请检查网络", retryable: true)
        }
        if msg.contains("timeout") || msg.contains("timed out") {
            return ClassifiedError(category: "timeout", message: "请求超时，请稍后重试", retryable: true)
        }

        return ClassifiedError(category: "unknown", message: msg, retryable: false)
    }

    // MARK: - Plan Steps Progress (对标桌面端 completedToolCount 启发式)

    /// tool_result 完成时更新 Plan 步骤的视觉进度
    private func updatePlanStepsProgress() {
        guard let plan = currentPlan, !plan.steps.isEmpty else { return }

        let stepCount = plan.steps.count
        let progressRatio = Double(completedToolCount) / Double(max(totalToolCount, stepCount * 2))
        let completedSteps = min(Int(progressRatio * Double(stepCount)), stepCount - 1)

        // 找到 plan 在 displayGroups 中的位置并更新
        for i in 0..<displayGroups.count {
            if case .plan(let id, var data) = displayGroups[i] {
                var updatedSteps = data.steps
                for j in 0..<updatedSteps.count {
                    if j < completedSteps {
                        updatedSteps[j].status = "completed"
                    } else if j == completedSteps {
                        updatedSteps[j].status = "in_progress"
                    } else {
                        updatedSteps[j].status = "pending"
                    }
                }
                data = PlanData(id: data.id, goal: data.goal, steps: updatedSteps, notes: data.notes)
                displayGroups[i] = .plan(id: id, data: data)
                break
            }
        }
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
            if !title.isEmpty {
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

import Foundation
import SwiftUI

/// 聊天消息 UI 模型
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    var content: String
    var artifacts: [ArtifactData]
    var plan: PlanData?
    var isStreaming: Bool

    enum MessageRole {
        case user
        case assistant
        case error
        case system
    }

    init(role: MessageRole, content: String, artifacts: [ArtifactData] = [], plan: PlanData? = nil, isStreaming: Bool = false) {
        self.role = role
        self.content = content
        self.artifacts = artifacts
        self.plan = plan
        self.isStreaming = isStreaming
    }
}

/// Artifact 数据
struct ArtifactData: Identifiable {
    let id = UUID()
    let type: String
    let jsonData: String
}

/// 对话 ViewModel — 核心状态管理
@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isRunning = false
    @Published var currentSessionId: String?
    @Published var currentTitle: String?
    @Published var phase: String = "idle" // idle, planning, awaiting_approval, executing

    private var backendSessionId: String?
    private var streamTask: Task<Void, Never>?

    // MARK: - Public API

    func sendMessage(_ prompt: String) async {
        // Add user message
        let userMessage = ChatMessage(role: .user, content: prompt)
        messages.append(userMessage)

        isRunning = true
        phase = "executing"

        // Create a placeholder for assistant response
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        // Build request
        let settings = SettingsService.shared.currentSettings
        let request = AgentRequest(
            prompt: prompt,
            taskId: currentSessionId ?? UUID().uuidString,
            modelConfig: settings.modelConfig,
            language: "zh-CN",
            userId: AuthService.shared.userId,
            accessToken: await AuthService.shared.getAccessToken()
        )

        // Start streaming
        streamTask = Task {
            do {
                let stream = await APIClient.shared.streamAgent(request: request)
                for try await event in stream {
                    handleSSEEvent(event, at: assistantIndex)
                }
            } catch {
                if !Task.isCancelled {
                    messages[assistantIndex].content += "\n\n⚠️ \(error.localizedDescription)"
                    messages[assistantIndex].isStreaming = false
                }
            }
            isRunning = false
            phase = "idle"
            messages[assistantIndex].isStreaming = false

            // Generate title for first message
            if messages.filter({ $0.role == .user }).count == 1 {
                await generateTitle(for: prompt)
            }
        }
    }

    func stopGeneration() {
        streamTask?.cancel()
        streamTask = nil
        isRunning = false
        phase = "idle"
        if let sessionId = backendSessionId {
            Task {
                try? await APIClient.shared.stopSession(sessionId)
            }
        }
    }

    func startNewChat() {
        messages = []
        currentSessionId = nil
        currentTitle = nil
        backendSessionId = nil
        phase = "idle"
        isRunning = false
    }

    func loadSession(_ sessionId: String) {
        // TODO: Load from local storage
        currentSessionId = sessionId
    }

    // MARK: - SSE Event Handling

    private func handleSSEEvent(_ event: SSEEvent, at index: Int) {
        guard index < messages.count else { return }

        switch event.type {
        case .text, .directAnswer:
            if let content = event.content {
                messages[index].content += content
            }

        case .session:
            if let sid = event.sessionId {
                backendSessionId = sid
            }

        case .plan:
            if let plan = event.plan {
                messages[index].plan = plan
                phase = "awaiting_approval"
            }

        case .error:
            let errorMsg = event.message ?? "未知错误"
            messages[index].content += "\n\n❌ \(errorMsg)"

        case .toolUse:
            // Show tool usage inline
            let toolName = event.name ?? "工具"
            messages[index].content += "\n🔧 正在调用 \(toolName)..."

        case .toolResult:
            // Tool finished
            break

        case .result:
            // Final result
            messages[index].isStreaming = false

        case .done:
            messages[index].isStreaming = false

        default:
            break
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
            if !title.isEmpty && title != prompt {
                currentTitle = title
            }
        } catch {
            // Title generation failure is non-critical
        }
    }
}

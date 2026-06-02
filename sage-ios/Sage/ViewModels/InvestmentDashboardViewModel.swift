import Foundation

struct VoiceTranscriptPreview: Identifiable {
    let id = UUID()
    let transcript: String
}

@MainActor
final class InvestmentDashboardViewModel: ObservableObject {
    @Published var dashboard: MobileDashboard?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var presentedIdea: IdeaNoteCardData?
    @Published var pendingVoicePreview: VoiceTranscriptPreview?
    @Published var focusedActionId: String?
    @Published var actions: [InvestmentActionItem] = []
    @Published var isTranscribing = false
    @Published var isCreatingIdea = false

    func loadDashboard() async {
        isLoading = true
        errorMessage = nil
        do {
            dashboard = try await APIClient.shared.getMobileDashboard()
            actions = try await APIClient.shared.getMobileActions()
        } catch {
            errorMessage = error.localizedDescription
            reportMobileError("ios_dashboard_load_failed", error)
        }
        isLoading = false
    }

    /// push-to-talk 闭环第一段：录音 URL → 后端转写 → 展示可确认/取消的 transcript 预览。
    func submitVoiceIdea(audioURL: URL) async {
        isTranscribing = true
        defer {
            isTranscribing = false
            try? FileManager.default.removeItem(at: audioURL)
        }
        do {
            let text = try await APIClient.shared.transcribe(audioURL: audioURL)
            let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                errorMessage = "没听清，请再说一次。"
                return
            }
            pendingVoicePreview = VoiceTranscriptPreview(transcript: transcript)
        } catch {
            errorMessage = error.localizedDescription
            reportMobileError("ios_voice_idea_failed", error)
        }
    }

    /// 用户确认转写内容后才创建想法卡和行动卡；取消则直接丢弃，不落库。
    func confirmVoiceIdea(transcript: String) async {
        let cleaned = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            errorMessage = "内容为空，无法提交。"
            return
        }

        isCreatingIdea = true
        defer { isCreatingIdea = false }
        do {
            let result = try await APIClient.shared.createIdeaNote(transcript: cleaned)
            pendingVoicePreview = nil
            presentedIdea = result.note
            focusedActionId = result.action.id
            actions = try await APIClient.shared.getMobileActions()
        } catch {
            errorMessage = error.localizedDescription
            reportMobileError("ios_voice_idea_create_failed", error)
        }
    }

    func cancelVoiceIdea() {
        pendingVoicePreview = nil
    }

    /// 刷新行动列表（两步确认流程完成后回调）。
    func reloadActions() async {
        do {
            actions = try await APIClient.shared.getMobileActions()
        } catch {
            errorMessage = error.localizedDescription
            reportMobileError("ios_actions_reload_failed", error)
        }
    }
}

/// 把用户可见的产品级失败异步上报到 Supabase `error_logs`（fire-and-forget，不阻塞 UI）。
private func reportMobileError(_ type: String, _ error: Error) {
    Task { await ErrorReportService.shared.submit(errorType: type, message: error.localizedDescription) }
}

/// 分身 Tab：拉取真实蒸馏画像（/persona/memory），未蒸馏时回退引导文案。
@MainActor
final class AvatarProfileViewModel: ObservableObject {
    @Published var snapshot: PersonaSnapshot?
    @Published var isLoading = false

    /// 画像为空（新用户 / 尚未蒸馏）时是否展示 mock 引导。
    var showsOnboardingFallback: Bool {
        guard let snapshot else { return true }
        return !snapshot.hasContent
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let token = await AuthService.shared.getAccessToken() else {
            snapshot = nil
            return
        }
        do {
            let data = try await APIClient.shared.getPersona(accessToken: token)
            snapshot = PersonaSnapshot.parse(from: data)
        } catch {
            snapshot = nil
            reportMobileError("ios_persona_load_failed", error)
        }
    }
}

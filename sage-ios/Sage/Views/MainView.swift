import SwiftUI

/// 主视图 — Gemini 风格移动聊天壳 + Sage 金融工作流入口
struct MainView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settingsService: SettingsService
    @ObservedObject var chatVM: ChatViewModel
    @StateObject private var sessionListVM = SessionListViewModel()
    @State private var showSidebar = false
    @State private var showSettings = false
    @State private var showModelSheet = false
    @AppStorage("sage_theme") private var theme: String = "system"

    var body: some View {
        ZStack(alignment: .leading) {
            SageBackground()

            // ─── Main Content ───────────────────────────────────────
            VStack(spacing: 0) {
                topBar

                if chatVM.displayGroups.isEmpty && !chatVM.isRunning {
                    homeContent
                } else {
                    chatContent
                }

                inputBar
            }

            // ─── Sidebar Panel ──────────────────────────────────────
            if showSidebar {
                SidebarView(
                    sessions: sessionListVM.sessions,
                    onSelectSession: { id in
                        chatVM.loadSession(id)
                        if let session = sessionListVM.sessions.first(where: { $0.id == id }) {
                            chatVM.currentTitle = session.title
                        }
                        withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
                    },
                    onNewChat: {
                        chatVM.startNewChat()
                        withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
                    },
                    onDeleteSession: { id in
                        sessionListVM.deleteSession(id)
                        if chatVM.currentSessionId == id {
                            chatVM.startNewChat()
                        }
                    },
                    onRenameSession: { id, newTitle in
                        sessionListVM.updateTitle(id, title: newTitle)
                        if chatVM.currentSessionId == id {
                            chatVM.currentTitle = newTitle
                        }
                    },
                    onOpenSettings: {
                        withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showSettings = true }
                    },
                    runningSessionId: chatVM.isRunning ? chatVM.currentSessionId : nil
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.move(edge: .leading))
                .zIndex(2)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showSidebar)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if !showSidebar && value.startLocation.x < 30 && value.translation.width > 80 {
                        withAnimation(.easeOut(duration: 0.25)) { showSidebar = true }
                    } else if showSidebar && value.translation.width < -80 {
                        withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
                    }
                }
        )
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authService)
                .environmentObject(settingsService)
                .preferredColorScheme(colorSchemeForTheme)
        }
        .sheet(isPresented: $showModelSheet) {
            ModelQuickSheet(
                modelName: modelDisplayName,
                providerName: providerDisplayName,
                isConfigured: settingsService.isModelConfigured,
                onOpenSettings: {
                    showModelSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        showSettings = true
                    }
                }
            )
            .presentationDetents([.height(280)])
            .presentationDragIndicator(.hidden)
        }
        // Permission Request Alert
        .alert("权限请求", isPresented: .init(
            get: { chatVM.pendingPermission != nil },
            set: { if !$0 { chatVM.pendingPermission = nil } }
        )) {
            Button("拒绝", role: .cancel) {
                if let perm = chatVM.pendingPermission {
                    Task { await chatVM.respondToPermission(permissionId: perm.id, approved: false) }
                }
            }
            Button("允许") {
                if let perm = chatVM.pendingPermission {
                    Task { await chatVM.respondToPermission(permissionId: perm.id, approved: true) }
                }
            }
        } message: {
            if let perm = chatVM.pendingPermission {
                Text(permissionMessage(perm))
            }
        }
        .onAppear {
            sessionListVM.loadSessions()
            chatVM.onSessionCreated = { [weak sessionListVM] session in
                sessionListVM?.addSession(session)
            }
            chatVM.onSessionTitleUpdated = { [weak sessionListVM] id, title in
                sessionListVM?.updateTitle(id, title: title)
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            SageIconButton(systemName: "line.3.horizontal") {
                withAnimation(.easeOut(duration: 0.25)) { showSidebar.toggle() }
            }

            Spacer()

            Button {
                showModelSheet = true
            } label: {
                HStack(spacing: 6) {
                    VStack(spacing: 1) {
                        Text(chatVM.currentTitle ?? "Sage")
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                        Text(modelDisplayName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Spacer()

            SageIconButton(systemName: "square.and.pencil") {
                chatVM.startNewChat()
            }
        }
        .padding(.horizontal, SageTheme.Spacing.md)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: - Home (empty state)

    private var homeContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: SageTheme.Spacing.md) {
                Image("SageLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 58, height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
                    .shadow(color: SageTheme.ColorToken.brand.opacity(0.22), radius: 18, x: 0, y: 10)

                VStack(spacing: 6) {
                    Text("今天想研究什么？")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("问行情、读财报、做回测，Sage 会把过程收进清晰的工作流。")
                        .font(.system(size: 14))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 34)
                }
            }

            if settingsService.isModelConfigured {
                quickActionsSection
                    .padding(.top, SageTheme.Spacing.xl)
            }

            // Model not configured warning
            if !settingsService.isModelConfigured {
                Button {
                    showSettings = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("请先配置模型")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .cornerRadius(10)
                }
                .padding(.top, 20)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
    }

    // MARK: - Chat Content (使用 displayGroups 渲染)

    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(chatVM.displayGroups) { group in
                        displayGroupView(group)
                            .id(group.id)
                    }

                    // Running indicator
                    if chatVM.isRunning {
                        RunningIndicatorView(lastToolName: chatVM.lastToolName)
                            .id("running")
                    }
                }
                .padding(.vertical, SageTheme.Spacing.md)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            .onChange(of: chatVM.displayGroups.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: chatVM.isRunning) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    /// 根据 DisplayGroup 类型分发渲染
    @ViewBuilder
    private func displayGroupView(_ group: DisplayGroup) -> some View {
        switch group {
        case .userMessage(_, let content):
            UserMessageRow(content: content)

        case .taskGroup(_, let title, let tools, let isComplete):
            TaskGroupRow(title: title, tools: tools, isComplete: isComplete)

        case .assistantText(_, let content, let isStreaming):
            AssistantTextRow(content: content, isStreaming: isStreaming)

        case .plan(_, let data):
            PlanApprovalRow(plan: data, onApprove: {
                Task { await chatVM.approvePlan() }
            }, onReject: {
                chatVM.rejectPlan()
            })

        case .error(_, let message):
            ErrorRow(message: message)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if chatVM.isRunning {
                proxy.scrollTo("running", anchor: .bottom)
            } else if let last = chatVM.displayGroups.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        InputBarView(
            isRunning: chatVM.isRunning,
            isModelConfigured: settingsService.isModelConfigured,
            onSend: { prompt, images in
                Task { await chatVM.sendMessage(prompt, images: images) }
            },
            onStop: {
                chatVM.stopGeneration()
            }
        )
    }

    // MARK: - Quick Actions (对标桌面端首页 3 个分类)

    private var quickActionsSection: some View {
        VStack(spacing: SageTheme.Spacing.sm) {
            HStack(spacing: SageTheme.Spacing.xs) {
                quickActionButton(icon: "chart.line.uptrend.xyaxis", title: "看行情", prompt: "帮我查一下今天 A 股大盘走势和热门板块")
                quickActionButton(icon: "doc.text.magnifyingglass", title: "读研报", prompt: "搜索最新的券商研报，分析当前市场观点")
            }
            HStack(spacing: SageTheme.Spacing.xs) {
                quickActionButton(icon: "clock.arrow.circlepath", title: "定时复盘", prompt: "帮我设置一个每天早上 9 点的市场简报定时任务")
                quickActionButton(icon: "brain.head.profile", title: "记忆偏好", prompt: "根据我的历史偏好，整理一份投资关注清单")
            }
        }
        .padding(.horizontal, SageTheme.Spacing.xl)
    }

    private func quickActionButton(icon: String, title: String, prompt: String) -> some View {
        SagePromptChip(icon: icon, title: title) {
            Task { await chatVM.sendMessage(prompt) }
        }
    }

    // MARK: - Helpers

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var colorSchemeForTheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var modelDisplayName: String {
        settingsService.currentSettings.modelConfig?.model
            ?? settingsService.currentSettings.defaultModel
            ?? "选择模型"
    }

    private var providerDisplayName: String {
        guard let providerId = settingsService.currentSettings.defaultProvider,
              let provider = settingsService.currentSettings.providers.first(where: { $0.id == providerId }) else {
            return settingsService.isModelConfigured ? "已配置" : "未配置"
        }
        return provider.name
    }

    private func permissionMessage(_ perm: PermissionRequestData) -> String {
        var msg = ""
        if let desc = perm.description, !desc.isEmpty {
            msg += desc
        }
        if let tool = perm.tool, !tool.isEmpty {
            msg += msg.isEmpty ? "工具: \(tool)" : "\n工具: \(tool)"
        }
        if let cmd = perm.command, !cmd.isEmpty {
            msg += msg.isEmpty ? cmd : "\n\(cmd)"
        }
        return msg.isEmpty ? "Agent 请求执行权限" : msg
    }
}

// MARK: - Model Quick Sheet

struct ModelQuickSheet: View {
    let modelName: String
    let providerName: String
    let isConfigured: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            SageSheetHandle()

            VStack(alignment: .leading, spacing: SageTheme.Spacing.lg) {
                HStack(spacing: SageTheme.Spacing.md) {
                    Image(systemName: isConfigured ? "sparkles" : "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(isConfigured ? SageTheme.ColorToken.brand : .orange)
                        .frame(width: 42, height: 42)
                        .background((isConfigured ? SageTheme.ColorToken.brandSoft : Color.orange.opacity(0.12)))
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isConfigured ? "当前模型" : "模型未配置")
                            .font(.system(size: 18, weight: .semibold))
                        Text(isConfigured ? "\(providerName) · \(modelName)" : "配置模型后即可开始对话")
                            .font(.system(size: 13))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                            .lineLimit(2)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: SageTheme.Spacing.xs) {
                    Label("轻量模型入口先承载状态与设置跳转", systemImage: "checkmark.circle")
                    Label("后续可扩展思考等级、模型族切换与额度状态", systemImage: "slider.horizontal.3")
                }
                .font(.system(size: 13))
                .foregroundColor(SageTheme.ColorToken.mutedText)

                Button(action: onOpenSettings) {
                    HStack {
                        Text(isConfigured ? "打开模型设置" : "去配置模型")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, SageTheme.Spacing.md)
                    .padding(.vertical, 14)
                    .background(SageTheme.ColorToken.brand)
                    .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, SageTheme.Spacing.xl)
            .padding(.bottom, SageTheme.Spacing.xl)
        }
        .background(SageTheme.ColorToken.surface)
    }
}

// MARK: - Plan Approval Row

struct PlanApprovalRow: View {
    let plan: PlanData
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                Text("执行计划")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    withAnimation { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            // Goal
            Text(plan.goal)
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            // Steps
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(plan.steps) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: stepIcon(step.status))
                                .font(.system(size: 11))
                                .foregroundColor(stepColor(step.status))
                                .frame(width: 14)
                            Text(step.description)
                                .font(.system(size: 12))
                                .foregroundColor(.primary)
                        }
                    }
                }
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    onApprove()
                } label: {
                    Text("批准执行")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(SageTheme.ColorToken.brand)
                        .clipShape(Capsule())
                }

                Button {
                    onReject()
                } label: {
                    Text("拒绝")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(SageTheme.ColorToken.surfaceSecondary)
                        .clipShape(Capsule())
                }

                Spacer()
            }
        }
        .padding(14)
        .sageSoftCard(cornerRadius: SageTheme.Radius.md)
        .padding(.horizontal, 16)
    }

    private func stepIcon(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "in_progress": return "circle.dotted"
        case "failed": return "xmark.circle.fill"
        default: return "circle"
        }
    }

    private func stepColor(_ status: String) -> Color {
        switch status {
        case "completed": return .green
        case "in_progress": return .blue
        case "failed": return .red
        default: return .secondary
        }
    }
}

// MARK: - Error Row

struct ErrorRow: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .lineLimit(5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.sm, style: .continuous))
        .padding(.horizontal, 16)
    }
}

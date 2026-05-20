import SwiftUI

/// 主视图 — 侧边栏 + 对话区域
/// ChatGPT 风格布局：顶栏(≡ + 标题 + 新对话) + 内容区 + 底部输入栏
struct MainView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settingsService: SettingsService
    @StateObject private var chatVM = ChatViewModel()
    @StateObject private var sessionListVM = SessionListViewModel()
    @State private var showSidebar = false
    @State private var showSettings = false
    @AppStorage("sage_theme") private var theme: String = "system"

    var body: some View {
        ZStack(alignment: .leading) {
            // ─── Main Content ───────────────────────────────────────
            VStack(spacing: 0) {
                topBar
                Divider().opacity(0.3)

                if chatVM.displayGroups.isEmpty && !chatVM.isRunning {
                    homeContent
                } else {
                    chatContent
                }

                inputBar
            }
            .disabled(showSidebar)
            .blur(radius: showSidebar ? 1 : 0)

            // ─── Sidebar Overlay ────────────────────────────────────
            if showSidebar {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeOut(duration: 0.25)) { showSidebar = false } }
                    .zIndex(1)
            }

            // ─── Sidebar Panel ──────────────────────────────────────
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
                }
            )
            .frame(width: 300)
            .offset(x: showSidebar ? 0 : -300)
            .animation(.easeOut(duration: 0.25), value: showSidebar)
            .zIndex(2)
        }
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
        HStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.25)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(chatVM.currentTitle ?? "Sage")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer()

            Button {
                chatVM.startNewChat()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
    }

    // MARK: - Home (empty state)

    private var homeContent: some View {
        VStack(spacing: 0) {
            Spacer()

            Image("SageLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .opacity(0.7)
                .padding(.bottom, 12)

            Text("有什么可以帮你的？")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(.secondary)

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
                .padding(.vertical, 16)
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
            onSend: { prompt in
                Task { await chatVM.sendMessage(prompt) }
            },
            onStop: {
                chatVM.stopGeneration()
            }
        )
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
                        .background(Color.blue)
                        .cornerRadius(8)
                }

                Button {
                    onReject()
                } label: {
                    Text("拒绝")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }

                Spacer()
            }
        }
        .padding(14)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.2), lineWidth: 0.5)
        )
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
    }
}

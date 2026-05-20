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

    var body: some View {
        ZStack(alignment: .leading) {
            // ─── Main Content ───────────────────────────────────────
            VStack(spacing: 0) {
                topBar
                Divider().opacity(0.3)

                if chatVM.messages.isEmpty && !chatVM.isRunning {
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
                    withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
                },
                onNewChat: {
                    chatVM.startNewChat()
                    withAnimation(.easeOut(duration: 0.25)) { showSidebar = false }
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

            // Sage logo (not a leaf!)
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
    }

    // MARK: - Chat Content

    private var chatContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ForEach(chatVM.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }

                    if chatVM.isRunning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("正在思考...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .id("running")
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: chatVM.messages.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    if chatVM.isRunning {
                        proxy.scrollTo("running", anchor: .bottom)
                    } else if let last = chatVM.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
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
}

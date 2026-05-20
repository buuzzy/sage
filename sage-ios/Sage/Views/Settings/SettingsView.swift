import SwiftUI

/// 设置页 — 底部 sheet 弹出
/// 分组为独立 NavigationLink 页面：账户、通用、模型、数据、关于（匹配桌面端）
struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // ─── 账户 ─────────────────────────────────────
                Section {
                    NavigationLink {
                        AccountSettingsView()
                            .environmentObject(authService)
                    } label: {
                        Label("账户", systemImage: "person.circle")
                    }
                }

                // ─── 通用 ─────────────────────────────────────
                Section {
                    NavigationLink {
                        GeneralSettingsView()
                            .environmentObject(settingsService)
                    } label: {
                        Label("通用", systemImage: "gearshape")
                    }
                }

                // ─── 模型 ─────────────────────────────────────
                Section {
                    NavigationLink {
                        ModelSettingsView()
                            .environmentObject(settingsService)
                    } label: {
                        Label("模型", systemImage: "cpu")
                    }
                }

                // ─── 数据 ─────────────────────────────────────
                Section {
                    NavigationLink {
                        DataSettingsView()
                    } label: {
                        Label("数据", systemImage: "externaldrive")
                    }
                }

                // ─── MCP ─────────────────────────────────────
                Section {
                    NavigationLink {
                        MCPSettingsView()
                    } label: {
                        Label("MCP", systemImage: "server.rack")
                    }
                }

                // ─── 技能 ─────────────────────────────────────
                Section {
                    NavigationLink {
                        SkillsSettingsView()
                    } label: {
                        Label("技能", systemImage: "sparkles")
                    }
                }

                // ─── 定时任务 ────────────────────────────────
                Section {
                    NavigationLink {
                        CronSettingsView()
                    } label: {
                        Label("定时任务", systemImage: "clock")
                    }
                }

                // ─── 画像 ────────────────────────────────────
                Section {
                    NavigationLink {
                        PersonaSettingsView()
                    } label: {
                        Label("画像", systemImage: "brain")
                    }
                }

                // ─── 关于 ─────────────────────────────────────
                Section {
                    NavigationLink {
                        AboutSettingsView()
                            .environmentObject(authService)
                    } label: {
                        Label("关于", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                }
            }
        }
    }
}

// MARK: - Account Settings

struct AccountSettingsView: View {
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("账户信息") {
                if let user = authService.currentUser {
                    HStack {
                        Image(systemName: "envelope")
                            .foregroundColor(.secondary)
                        Text(user.email ?? "-")
                        Spacer()
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    Task {
                        await authService.signOut()
                        dismiss()
                    }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("退出登录")
                    }
                }
            }
        }
        .navigationTitle("账户")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - General Settings (Theme + Language + Accent Color)

struct GeneralSettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @AppStorage("sage_theme") private var theme: String = "system"
    @AppStorage("sage_language") private var language: String = "zh"
    @AppStorage("sage_accent_color") private var accentColor: String = "blue"

    private let accentColors: [(name: String, color: Color, key: String)] = [
        ("蓝色", .blue, "blue"),
        ("绿色", .green, "green"),
        ("橙色", .orange, "orange"),
        ("紫色", .purple, "purple"),
        ("红色", .red, "red"),
        ("粉色", .pink, "pink"),
    ]

    var body: some View {
        List {
            Section("外观") {
                Picker("主题", selection: $theme) {
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                    Text("跟随系统").tag("system")
                }
                .pickerStyle(.segmented)
                .onChange(of: theme) { newValue in
                    settingsService.currentSettings.theme = newValue
                    settingsService.save()
                }
            }

            Section("强调色") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(accentColors, id: \.key) { item in
                        Circle()
                            .fill(item.color)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: accentColor == item.key ? 2.5 : 0)
                                    .padding(-3)
                            )
                            .onTapGesture {
                                accentColor = item.key
                                settingsService.save()
                            }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("语言") {
                Picker("语言", selection: $language) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                .onChange(of: language) { newValue in
                    settingsService.currentSettings.language = newValue
                    settingsService.save()
                }
            }
        }
        .navigationTitle("通用")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            theme = settingsService.currentSettings.theme
            language = settingsService.currentSettings.language
        }
    }
}

// MARK: - Model Settings

struct ModelSettingsView: View {
    @EnvironmentObject var settingsService: SettingsService

    var body: some View {
        List {
            Section("模型配置") {
                ForEach(settingsService.currentSettings.providers) { provider in
                    NavigationLink {
                        ProviderDetailView(provider: provider)
                            .environmentObject(settingsService)
                    } label: {
                        HStack(spacing: 12) {
                            Text(provider.icon)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 32, height: 32)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .font(.subheadline)
                                Text(provider.apiKey?.isEmpty == false ? "已配置" : "未配置")
                                    .font(.caption)
                                    .foregroundColor(provider.apiKey?.isEmpty == false ? .green : .secondary)
                            }
                            Spacer()
                            if provider.id == settingsService.currentSettings.defaultProvider {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                    }
                }
            }

            Section(footer: Text("选择一个 Provider 配置 API Key 后即可使用。")) {
                EmptyView()
            }
        }
        .navigationTitle("模型")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Data Settings

struct DataSettingsView: View {
    @State private var showClearAlert = false

    var body: some View {
        List {
            Section("对话数据") {
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("清除所有对话记录")
                    }
                }
            }

            Section(footer: Text("清除后无法恢复，请谨慎操作。")) {
                EmptyView()
            }
        }
        .navigationTitle("数据")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认清除", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("将删除所有本地对话记录，此操作不可撤销。")
        }
    }

    private func clearAllData() {
        let defaults = UserDefaults.standard
        let sessions = ChatViewModel.loadAllSessionsFromStorage()
        for session in sessions {
            defaults.removeObject(forKey: "sage_messages_\(session.id)")
        }
        ChatViewModel.saveAllSessionsToStorage([])
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        List {
            Section("应用信息") {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("用户 ID")
                    Spacer()
                    Text(authService.userId?.prefix(8).description ?? "-")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }

            Section("开发者") {
                HStack {
                    Text("Sage AI")
                    Spacer()
                    Text("sage.ai")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Provider Detail (with Test Response + API Type)

struct ProviderDetailView: View {
    let provider: ProviderConfig
    @EnvironmentObject var settingsService: SettingsService
    @State private var apiKey: String = ""
    @State private var baseUrl: String = ""
    @State private var selectedModel: String = ""
    @State private var selectedApiType: String = ""
    @State private var showKey = false
    @State private var testStatus: TestStatus = .idle
    @Environment(\.dismiss) private var dismiss

    enum TestStatus: Equatable {
        case idle, testing, success, failure(String)
    }

    private let apiTypes = [
        ("openai-completions", "OpenAI 兼容"),
        ("anthropic-messages", "Anthropic Messages"),
    ]

    var body: some View {
        Form {
            // API Key
            Section("API Key") {
                HStack {
                    if showKey {
                        TextField("sk-...", text: $apiKey)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("sk-...", text: $apiKey)
                    }
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }

                // API Key 获取链接
                if let url = provider.apiKeyUrl, let link = URL(string: url) {
                    Link(destination: link) {
                        HStack(spacing: 6) {
                            Image(systemName: "key")
                                .font(.system(size: 12))
                            Text("获取 API Key")
                                .font(.system(size: 13))
                        }
                        .foregroundColor(.blue)
                    }
                }
            }

            // Base URL
            Section("Base URL") {
                TextField(provider.baseUrl ?? "https://api.openai.com/v1", text: $baseUrl)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.body, design: .monospaced))
            }

            // API Type
            Section("API 类型") {
                Picker("类型", selection: $selectedApiType) {
                    ForEach(apiTypes, id: \.0) { type in
                        Text(type.1).tag(type.0)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Model Selection
            Section("模型") {
                ForEach(provider.models, id: \.self) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        HStack {
                            Text(model)
                                .foregroundColor(.primary)
                                .font(.system(size: 14))
                            Spacer()
                            if selectedModel == model {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 13))
                            }
                        }
                    }
                }
            }

            // Test Response
            Section("连接测试") {
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 10) {
                        switch testStatus {
                        case .idle:
                            Image(systemName: "bolt")
                                .foregroundColor(.blue)
                            Text("测试响应")
                                .foregroundColor(.blue)
                        case .testing:
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("测试中...")
                                .foregroundColor(.secondary)
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("连接成功")
                                .foregroundColor(.green)
                        case .failure(let msg):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(msg)
                                .foregroundColor(.red)
                                .font(.system(size: 13))
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                }
                .disabled(apiKey.isEmpty || testStatus == .testing)
            }

            // Save
            Section {
                Button {
                    saveAndDismiss()
                } label: {
                    Text("保存并设为默认")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(provider.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = provider.apiKey ?? ""
            baseUrl = provider.baseUrl ?? ""
            selectedModel = provider.defaultModel ?? provider.models.first ?? ""
            selectedApiType = provider.apiType ?? "openai-completions"
        }
    }

    // MARK: - Test Connection

    private func testConnection() {
        testStatus = .testing
        let testKey = apiKey
        let testBaseUrl = baseUrl.isEmpty ? (provider.baseUrl ?? "") : baseUrl
        let testModel = selectedModel

        Task {
            do {
                // Simple test: send a minimal request to validate API key
                let url = URL(string: "\(testBaseUrl)/chat/completions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(testKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 15

                let body: [String: Any] = [
                    "model": testModel,
                    "messages": [["role": "user", "content": "hi"]],
                    "max_tokens": 5
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    testStatus = .success
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    testStatus = .failure("HTTP \(code)")
                }
            } catch {
                testStatus = .failure(error.localizedDescription)
            }

            // Reset after 3 seconds
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            testStatus = .idle
        }
    }

    // MARK: - Save

    private func saveAndDismiss() {
        if let idx = settingsService.currentSettings.providers.firstIndex(where: { $0.id == provider.id }) {
            settingsService.currentSettings.providers[idx].apiKey = apiKey
            settingsService.currentSettings.providers[idx].baseUrl = baseUrl.isEmpty ? provider.baseUrl : baseUrl
            settingsService.currentSettings.providers[idx].defaultModel = selectedModel
            settingsService.currentSettings.providers[idx].apiType = selectedApiType
        }
        settingsService.currentSettings.defaultProvider = provider.id
        settingsService.currentSettings.defaultModel = selectedModel
        settingsService.currentSettings.modelConfig = ModelConfig(
            apiKey: apiKey,
            baseUrl: baseUrl.isEmpty ? provider.baseUrl : baseUrl,
            model: selectedModel,
            apiType: selectedApiType
        )
        settingsService.save()
        dismiss()
    }
}

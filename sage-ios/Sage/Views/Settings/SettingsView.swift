import SwiftUI

/// 设置页 — 对标 DMG 桌面端设置面板
/// 紧凑列表布局，无多余间隔，统一风格
struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // 账户信息头部
                Section {
                    if let user = authService.currentUser {
                        HStack(spacing: SageTheme.Spacing.sm) {
                            // 头像
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(SageTheme.ColorToken.brand)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.email ?? "用户")
                                    .font(.system(size: 15, weight: .medium))
                                Text("已登录")
                                    .font(.system(size: 12))
                                    .foregroundColor(.green)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                // 主设置列表 — 所有选项紧凑排列
                Section {
                    // 通用
                    NavigationLink {
                        GeneralSettingsView()
                            .environmentObject(settingsService)
                    } label: {
                        settingsRow(icon: "gearshape.fill", color: .gray, title: "通用")
                    }

                    // 模型
                    NavigationLink {
                        ModelSettingsView()
                            .environmentObject(settingsService)
                    } label: {
                        settingsRow(icon: "cpu.fill", color: .blue, title: "模型")
                    }

                    // 画像
                    NavigationLink {
                        PersonaSettingsView()
                    } label: {
                        settingsRow(icon: "brain", color: .purple, title: "画像")
                    }

                    // 定时任务
                    NavigationLink {
                        CronSettingsView()
                    } label: {
                        settingsRow(icon: "clock.fill", color: .orange, title: "定时任务")
                    }

                    // MCP
                    NavigationLink {
                        MCPSettingsView()
                    } label: {
                        settingsRow(icon: "server.rack", color: .teal, title: "MCP")
                    }

                    // 技能
                    NavigationLink {
                        SkillsSettingsView()
                    } label: {
                        settingsRow(icon: "sparkles", color: .pink, title: "技能")
                    }
                }

                // 数据 & 关于
                Section {
                    NavigationLink {
                        DataSettingsView()
                    } label: {
                        settingsRow(icon: "externaldrive.fill", color: .indigo, title: "数据")
                    }

                    NavigationLink {
                        AboutSettingsView()
                            .environmentObject(authService)
                    } label: {
                        settingsRow(icon: "info.circle.fill", color: .secondary, title: "关于")
                    }
                }

                // 退出登录
                Section {
                    Button {
                        Task {
                            await authService.signOut()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("退出登录")
                                .font(.system(size: 15))
                                .foregroundColor(.red)
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(SageTheme.ColorToken.surfaceSecondary)
                            .clipShape(Circle())
                    }
                }
            }
        }
    }

    // MARK: - 设置项行（统一风格）

    private func settingsRow(icon: String, color: Color, title: String) -> some View {
        HStack(spacing: SageTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.sm, style: .continuous))
            Text(title)
                .font(.system(size: 15))
        }
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
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .onChange(of: theme) { newValue in
                    settingsService.currentSettings.theme = newValue
                    settingsService.save()
                }
            }

            Section("强调色") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 16) {
                    ForEach(accentColors, id: \.key) { item in
                        Circle()
                            .fill(item.color)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .opacity(accentColor == item.key ? 1 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.primary.opacity(0.2), lineWidth: accentColor == item.key ? 2 : 0)
                                    .padding(-3)
                            )
                            .onTapGesture {
                                accentColor = item.key
                                settingsService.save()
                            }
                    }
                }
                .padding(.vertical, 8)
            }

            Section("语言") {
                Picker("语言", selection: $language) {
                    Text("中文").tag("zh")
                    Text("English").tag("en")
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
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
            ForEach(settingsService.currentSettings.providers) { provider in
                NavigationLink {
                    ProviderDetailView(provider: provider)
                        .environmentObject(settingsService)
                } label: {
                    HStack(spacing: 12) {
                        // Provider 图标
                        Text(provider.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                                .font(.system(size: 15))
                            Text(provider.apiKey?.isEmpty == false ? "已配置" : "未配置")
                                .font(.system(size: 12))
                                .foregroundColor(provider.apiKey?.isEmpty == false ? .green : .secondary)
                        }

                        Spacer()

                        if provider.id == settingsService.currentSettings.defaultProvider {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 16))
                        }
                    }
                    .padding(.vertical, 2)
                }
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
            Section {
                Button(role: .destructive) {
                    showClearAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                        Text("清除所有对话记录")
                    }
                }
            } footer: {
                Text("清除后无法恢复，请谨慎操作。")
            }
        }
        .navigationTitle("数据")
        .navigationBarTitleDisplayMode(.inline)
        .alert("确认清除", isPresented: $showClearAlert) {
            Button("取消", role: .cancel) { }
            Button("清除", role: .destructive) {
                let defaults = UserDefaults.standard
                let sessions = ChatViewModel.loadAllSessionsFromStorage()
                for session in sessions {
                    defaults.removeObject(forKey: "sage_messages_\(session.id)")
                }
                ChatViewModel.saveAllSessionsToStorage([])
            }
        } message: {
            Text("将删除所有本地对话记录，此操作不可撤销。")
        }
    }
}

// MARK: - About Settings

struct AboutSettingsView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        List {
            Section {
                HStack {
                    Text("版本")
                    Spacer()
                    Text("1.0.0 (14)")
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("用户 ID")
                    Spacer()
                    Text(authService.userId?.prefix(8).description ?? "-")
                        .foregroundColor(.secondary)
                        .font(.system(size: 13, design: .monospaced))
                }
            }
            Section {
                HStack {
                    Text("开发者")
                    Spacer()
                    Text("Sage AI")
                        .foregroundColor(.secondary)
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

    var body: some View {
        Form {
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
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                    }
                }

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

            Section("Base URL") {
                TextField(provider.baseUrl ?? "https://api.openai.com/v1", text: $baseUrl)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.body, design: .monospaced))
            }

            Section("API 类型") {
                Picker("类型", selection: $selectedApiType) {
                    Text("OpenAI 兼容").tag("openai-completions")
                    Text("Anthropic").tag("anthropic-messages")
                }
                .pickerStyle(.segmented)
            }

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
                            }
                        }
                    }
                }
            }

            Section("连接测试") {
                Button { testConnection() } label: {
                    HStack(spacing: 10) {
                        switch testStatus {
                        case .idle:
                            Image(systemName: "bolt")
                                .foregroundColor(.blue)
                            Text("测试响应")
                                .foregroundColor(.blue)
                        case .testing:
                            ProgressView().scaleEffect(0.8)
                            Text("测试中...").foregroundColor(.secondary)
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("连接成功").foregroundColor(.green)
                        case .failure(let msg):
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text(msg).foregroundColor(.red).font(.system(size: 13)).lineLimit(2)
                        }
                        Spacer()
                    }
                }
                .disabled(apiKey.isEmpty || testStatus == .testing)
            }

            Section {
                Button { saveAndDismiss() } label: {
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

    private func testConnection() {
        testStatus = .testing
        Task {
            do {
                let testBaseUrl = baseUrl.isEmpty ? (provider.baseUrl ?? "") : baseUrl
                let url = URL(string: "\(testBaseUrl)/chat/completions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 15
                let body: [String: Any] = ["model": selectedModel, "messages": [["role": "user", "content": "hi"]], "max_tokens": 5]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    testStatus = .success
                } else {
                    testStatus = .failure("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                }
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            testStatus = .idle
        }
    }

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

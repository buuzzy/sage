import SwiftUI

/// 设置页 — 对标 DMG 桌面端设置面板
/// 紧凑列表布局，无多余间隔，统一风格
struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss
    @State private var showClearDataAlert = false
    @State private var clearDataState: ClearDataState = .idle

    enum ClearDataState: Equatable {
        case idle
        case clearing
        case success
        case partialFailure
    }

    var body: some View {
        NavigationStack {
            List {
                // 账户信息头部
                Section {
                    if let user = authService.currentUser {
                        HStack(spacing: SageTheme.Spacing.sm) {
                            SageSymbolIcon(systemName: "person.crop.circle.fill", tone: .brand, size: 21, containerSize: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.email ?? "用户")
                                    .font(SageTheme.Typography.rowTitleEmphasized)
                                Text("已登录")
                                    .font(SageTheme.Typography.rowSubtitle)
                                    .foregroundColor(SageIconTone.success.foreground)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listRowBackground(sageListRowBackground)

                // 主设置列表 — 所有选项紧凑排列
                Section {
                    // 模型
                    NavigationLink {
                        ModelSettingsView()
                            .environmentObject(settingsService)
                            .environmentObject(CloudProviderStore.shared)
                    } label: {
                        SageSettingsRow(icon: "cpu", title: "模型", tone: .neutral, showsChevron: false)
                    }

                    // 画像
                    NavigationLink {
                        PersonaSettingsView()
                    } label: {
                        SageSettingsRow(icon: "brain", title: "画像", tone: .neutral, showsChevron: false)
                    }

                    // 定时任务
                    NavigationLink {
                        CronSettingsView()
                    } label: {
                        SageSettingsRow(icon: "clock", title: "定时任务", tone: .neutral, showsChevron: false)
                    }

                    // MCP
                    NavigationLink {
                        MCPSettingsView()
                    } label: {
                        SageSettingsRow(icon: "server.rack", title: "MCP", tone: .neutral, showsChevron: false)
                    }

                    // 技能
                    NavigationLink {
                        SkillsSettingsView()
                    } label: {
                        SageSettingsRow(icon: "sparkles", title: "技能", tone: .neutral, showsChevron: false)
                    }
                }
                .listRowBackground(sageListRowBackground)

                // 清除数据 + 退出登录（合并到同一 Section，靠 List divider 自然分隔）
                Section {
                    // 清除数据：destructive 操作保持红色字体
                    Button(role: .destructive) {
                        showClearDataAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            if clearDataState == .clearing {
                                ProgressView().scaleEffect(0.8)
                                Text("清除中…")
                                    .font(SageTheme.Typography.button)
                                    .foregroundColor(SageIconTone.danger.foreground)
                            } else {
                                Text("清除数据")
                                    .font(SageTheme.Typography.button)
                                    .foregroundColor(SageIconTone.danger.foreground)
                            }
                            Spacer()
                        }
                    }
                    .disabled(clearDataState == .clearing)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

                    // 退出登录：常规操作，黑色字体（红色留给真正的破坏性操作）
                    Button {
                        Task {
                            await authService.signOut()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("退出登录")
                                .font(SageTheme.Typography.button)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }
                .listRowBackground(sageListRowBackground)

                // 版本信息（居中、低调，从 Bundle 自动读取）
                Section {
                    EmptyView()
                } footer: {
                    HStack {
                        Spacer()
                        Text("版本 \(appVersionString)")
                            .font(SageTheme.Typography.rowSubtitle)
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                        Spacer()
                    }
                    .padding(.top, SageTheme.Spacing.md)
                }
            }
            .listStyle(.insetGrouped)
            .sageSettingsPage()
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 36, height: 36)
                            .background(SageTheme.ColorToken.controlGlass)
                            .clipShape(Circle())
                    }
                }
            }
            .alert("清除数据", isPresented: $showClearDataAlert) {
                Button("取消", role: .cancel) { }
                Button("清除", role: .destructive) { performClearData() }
            } message: {
                Text("将永久删除本机和云端的所有对话记录。此操作不可恢复。")
            }
            .alert("清除完成", isPresented: .init(
                get: { clearDataState == .success || clearDataState == .partialFailure },
                set: { if !$0 { clearDataState = .idle } }
            )) {
                Button("好") { clearDataState = .idle }
            } message: {
                Text(clearDataState == .partialFailure
                     ? "本机数据已清空，云端部分表删除失败。请稍后重试或检查网络。"
                     : "本机和云端对话记录已全部清除。")
            }
        }
    }

    // MARK: - Helpers

    /// 从 Bundle 读取 marketing version + build number，如「1.0.0 (15)」
    private var appVersionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let marketing = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(marketing) (\(build))"
    }

    /// 清除流程：先 confirm → 本地 UserDefaults → Supabase 三表 → 通知 MainView 刷新 UI
    /// 不可逆，所以 alert 已经强制确认过一次。
    private func performClearData() {
        clearDataState = .clearing
        Task {
            // 1) 本地 UserDefaults：messages 全部 + sessions 列表
            let defaults = UserDefaults.standard
            for session in ChatViewModel.loadAllSessionsFromStorage() {
                defaults.removeObject(forKey: "sage_messages_\(session.id)")
            }
            ChatViewModel.saveAllSessionsToStorage([])

            // 2) Supabase 云端三表（messages → tasks → sessions，按 FK 依赖）
            var cloudOk = true
            if let userId = authService.userId, !userId.isEmpty {
                cloudOk = await CloudSyncService.shared.clearAllConversationData(userId: userId)
            }

            // 3) 通知 MainView 同步刷新会话列表 + 重置当前对话
            await MainActor.run {
                clearDataState = cloudOk ? .success : .partialFailure
                NotificationCenter.default.post(name: .sageDataCleared, object: nil)
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// 「清除数据」操作完成后广播 — MainView / SidebarView 监听并刷新 sessions
    static let sageDataCleared = Notification.Name("ai.sage.dataCleared")
}

// MARK: - Model Settings

struct ModelSettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @EnvironmentObject var cloudStore: CloudProviderStore
    @State private var hasCheckedAuth = false

    var body: some View {
        List {
            if cloudStore.isLoading && cloudStore.providers.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 20)
                        Spacer()
                    }
                }
                .listRowBackground(sageListRowBackground)
            } else if hasCheckedAuth && !cloudStore.providers.isEmpty {
                // 云端模式
                ForEach(cloudStore.providers) { provider in
                    NavigationLink {
                        CloudProviderDetailView(provider: provider)
                            .environmentObject(cloudStore)
                            .environmentObject(settingsService)
                    } label: {
                        SageSettingsRow(
                            icon: providerSymbol(for: provider.providerKind),
                            title: provider.displayName,
                            subtitle: provider.enabled ? "已启用" : "已禁用",
                            tone: provider.isDefault ? .brand : .neutral,
                            showsChevron: false
                        ) {
                            if provider.isDefault {
                                SageStatusPill(title: "默认", tone: .success)
                            }
                        }
                    }
                    .listRowBackground(sageListRowBackground)
                }
            } else if hasCheckedAuth && cloudStore.providers.isEmpty {
                // 云端模式但无数据
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "cloud")
                                .font(.system(size: 32))
                                .foregroundColor(.secondary)
                            Text("还没有配置模型\n点击下方按钮添加")
                                .font(SageTheme.Typography.rowSubtitle)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.vertical, 24)
                        Spacer()
                    }
                }
                .listRowBackground(sageListRowBackground)
            } else {
                // 本地 fallback
                ForEach(settingsService.currentSettings.providers) { provider in
                    NavigationLink {
                        ProviderDetailView(provider: provider)
                            .environmentObject(settingsService)
                    } label: {
                        SageSettingsRow(
                            icon: providerSymbol(for: provider.id),
                            title: provider.name,
                            subtitle: provider.apiKey?.isEmpty == false ? "已配置" : "未配置",
                            tone: provider.id == settingsService.currentSettings.defaultProvider ? .brand : .neutral,
                            showsChevron: false
                        ) {
                            if provider.id == settingsService.currentSettings.defaultProvider {
                                SageStatusPill(title: "默认", tone: .success)
                            }
                        }
                    }
                    .listRowBackground(sageListRowBackground)
                }
            }

            // 添加供应商按钮
            Section {
                NavigationLink {
                    if hasCheckedAuth {
                        CloudAddProviderView()
                            .environmentObject(cloudStore)
                            .environmentObject(settingsService)
                    } else {
                        AddProviderView()
                            .environmentObject(settingsService)
                    }
                } label: {
                    HStack(spacing: SageTheme.Spacing.sm) {
                        SageSymbolIcon(systemName: "plus.circle", tone: .brand, size: 17, containerSize: 30)
                        Text("添加供应商")
                            .font(SageTheme.Typography.rowTitle)
                            .foregroundColor(SageTheme.ColorToken.brand)
                    }
                }
                .listRowBackground(sageListRowBackground)
            }

            if let error = cloudStore.error {
                Section {
                    Text(error)
                        .font(SageTheme.Typography.rowSubtitle)
                        .foregroundColor(.red)
                }
                .listRowBackground(sageListRowBackground)
            }
        }
        .sageSettingsPage()
        .navigationTitle("模型")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // 检查登录状态并拉取云端数据
            let authenticated = await cloudStore.isAuthenticated
            if authenticated {
                await cloudStore.refresh()
            }
            hasCheckedAuth = authenticated
        }
        .refreshable {
            if hasCheckedAuth {
                await cloudStore.refresh()
            }
        }
    }

    private func providerSymbol(for kind: String) -> String {
        switch kind.lowercased() {
        case let k where k.contains("deepseek"): return "brain"
        case let k where k.contains("minimax"): return "m.circle"
        case let k where k.contains("zhipu"): return "sparkles"
        case let k where k.contains("volcengine"): return "flame"
        case let k where k.contains("siliconflow"): return "cpu"
        case let k where k.contains("kimi"): return "moon"
        case let k where k.contains("qwen"): return "cloud"
        case let k where k.contains("anthropic"): return "sparkle.magnifyingglass"
        case let k where k.contains("openai"): return "circle.hexagongrid"
        case let k where k.contains("custom"): return "wrench.and.screwdriver"
        default: return "cpu"
        }
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
                            .frame(width: 44, height: 44)
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
            .listRowBackground(sageListRowBackground)

            Section("Base URL") {
                TextField(provider.baseUrl ?? "https://api.openai.com/v1", text: $baseUrl)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.body, design: .monospaced))
            }
            .listRowBackground(sageListRowBackground)

            Section("API 类型") {
                Picker("类型", selection: $selectedApiType) {
                    Text("OpenAI 兼容").tag("openai-completions")
                    Text("Anthropic").tag("anthropic-messages")
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(sageListRowBackground)

            Section("模型") {
                ForEach(provider.models, id: \.self) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        HStack {
                            Text(model)
                                .foregroundColor(.primary)
                                .font(SageTheme.Typography.rowTitle)
                            Spacer()
                            if selectedModel == model {
                                Image(systemName: "checkmark")
                                    .foregroundColor(SageTheme.ColorToken.brand)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .listRowBackground(sageListRowBackground)

            Section("连接测试") {
                Button { testConnection() } label: {
                    HStack(spacing: 10) {
                        switch testStatus {
                        case .idle:
                            SageSymbolIcon(systemName: "bolt", tone: .brand)
                            Text("测试响应")
                                .font(SageTheme.Typography.rowTitle)
                                .foregroundColor(.primary)
                        case .testing:
                            ProgressView().scaleEffect(0.8)
                            Text("测试中...").font(SageTheme.Typography.rowTitle).foregroundColor(.secondary)
                        case .success:
                            SageSymbolIcon(systemName: "checkmark.circle", tone: .success)
                            Text("连接成功").font(SageTheme.Typography.rowTitle).foregroundColor(SageIconTone.success.foreground)
                        case .failure(let msg):
                            SageSymbolIcon(systemName: "xmark.circle", tone: .danger)
                            Text(msg).foregroundColor(.red).font(SageTheme.Typography.rowSubtitle).lineLimit(2)
                        }
                        Spacer()
                    }
                }
                .disabled(apiKey.isEmpty || testStatus == .testing)
            }
            .listRowBackground(sageListRowBackground)

            Section {
                Button { saveAndDismiss() } label: {
                    Text("保存并设为默认")
                }
                .buttonStyle(SagePrimaryButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // 自定义 Provider 显示删除按钮
            if provider.id.hasPrefix("custom-") {
                Section {
                    Button(role: .destructive) { deleteProvider() } label: {
                        HStack {
                            Spacer()
                            Text("删除供应商")
                                .font(SageTheme.Typography.button)
                                .foregroundColor(SageIconTone.danger.foreground)
                            Spacer()
                        }
                    }
                    .listRowBackground(sageListRowBackground)
                }
            }
        }
        .sageSettingsPage()
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
                let rawBaseUrl = baseUrl.isEmpty ? (provider.baseUrl ?? "") : baseUrl
                let isAnthropic = selectedApiType == "anthropic-messages"

                // baseUrl 已遵循后端 buildEndpointUrl 约定（包含版本路径），
                // 这里只需直接拼端点 suffix。/v1 自动插入由后端在真实聊天时处理。
                let suffix = isAnthropic ? "/messages" : "/chat/completions"
                let trimmed = rawBaseUrl.hasSuffix("/") ? String(rawBaseUrl.dropLast()) : rawBaseUrl
                guard let url = URL(string: trimmed + suffix), !trimmed.isEmpty else {
                    testStatus = .failure("Base URL 为空或格式错误")
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    testStatus = .idle
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 15

                if isAnthropic {
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                } else {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                }

                let body: [String: Any] = ["model": selectedModel, "messages": [["role": "user", "content": "hi"]], "max_tokens": 5]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    testStatus = .success
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                    testStatus = .failure("HTTP \(code)（请求 URL：\(url.absoluteString)）")
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

    private func deleteProvider() {
        settingsService.currentSettings.providers.removeAll { $0.id == provider.id }
        // 如果删除的是默认 provider，重置默认
        if settingsService.currentSettings.defaultProvider == provider.id {
            settingsService.currentSettings.defaultProvider = settingsService.currentSettings.providers.first?.id
            settingsService.currentSettings.defaultModel = settingsService.currentSettings.providers.first?.defaultModel
            settingsService.currentSettings.modelConfig = nil
        }
        settingsService.save()
        dismiss()
    }
}

// MARK: - Add Provider

struct AddProviderView: View {
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var baseUrl: String = ""
    @State private var apiKey: String = ""
    @State private var modelsText: String = ""
    @State private var apiType: String = "openai-completions"
    @State private var showKey = false

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !baseUrl.trimmingCharacters(in: .whitespaces).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Section("名称") {
                TextField("供应商名称", text: $name)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }
            .listRowBackground(sageListRowBackground)

            Section("Base URL") {
                TextField("https://api.openai.com/v1", text: $baseUrl)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.system(.body, design: .monospaced))
            }
            .listRowBackground(sageListRowBackground)

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
                            .frame(width: 44, height: 44)
                    }
                }
            }
            .listRowBackground(sageListRowBackground)

            Section("模型列表") {
                TextField("gpt-4o, gpt-4o-mini", text: $modelsText)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                Text("多个模型用逗号分隔")
                    .font(SageTheme.Typography.rowSubtitle)
                    .foregroundColor(SageTheme.ColorToken.mutedText)
            }
            .listRowBackground(sageListRowBackground)

            Section("API 类型") {
                Picker("类型", selection: $apiType) {
                    Text("OpenAI 兼容").tag("openai-completions")
                    Text("Anthropic").tag("anthropic-messages")
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(sageListRowBackground)

            Section {
                Button { saveProvider() } label: {
                    Text("保存")
                }
                .buttonStyle(SagePrimaryButtonStyle())
                .disabled(!isValid)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .sageSettingsPage()
        .navigationTitle("添加供应商")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveProvider() {
        let id = "custom-\(Int(Date().timeIntervalSince1970 * 1000))"
        let models = modelsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let provider = ProviderConfig(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            apiKey: apiKey.trimmingCharacters(in: .whitespaces),
            baseUrl: baseUrl.trimmingCharacters(in: .whitespaces),
            models: models.isEmpty ? ["default"] : models,
            defaultModel: models.first,
            apiType: apiType,
            icon: "C",
            canDelete: true
        )

        settingsService.currentSettings.providers.append(provider)

        // 如果是第一个自定义 provider，自动设为默认
        let customProviders = settingsService.currentSettings.providers.filter { $0.id.hasPrefix("custom-") }
        if customProviders.count == 1 {
            settingsService.currentSettings.defaultProvider = id
            settingsService.currentSettings.defaultModel = provider.defaultModel
            settingsService.currentSettings.modelConfig = ModelConfig(
                apiKey: provider.apiKey,
                baseUrl: provider.baseUrl,
                model: provider.defaultModel,
                apiType: provider.apiType
            )
        }

        settingsService.save()
        dismiss()
    }
}

// MARK: - Cloud Add Provider (with Brand Templates)

struct CloudAddProviderView: View {
    @EnvironmentObject var cloudStore: CloudProviderStore
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedKind: String = "deepseek"
    @State private var name: String = ""
    @State private var baseUrl: String = ""
    @State private var endpointPath: String = ""
    @State private var apiKey: String = ""
    @State private var modelsText: String = ""
    @State private var apiType: String = "openai-completions"
    @State private var showKey = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var selectedTemplate: ProviderTemplate? {
        ProviderTemplate.allBuiltins.first(where: { $0.kind == selectedKind })
    }

    private var isCustom: Bool { selectedKind == "custom" }

    private var effectiveName: String {
        isCustom ? name : (selectedTemplate?.name ?? name)
    }
    private var effectiveBaseUrl: String {
        isCustom ? baseUrl : (selectedTemplate?.baseUrl ?? baseUrl)
    }
    private var effectiveEndpointPath: String {
        isCustom ? endpointPath : (selectedTemplate?.endpointPath ?? endpointPath)
    }
    private var effectiveApiType: String {
        isCustom ? apiType : (selectedTemplate?.apiType ?? apiType)
    }
    private var effectiveModels: [String] {
        if isCustom {
            return modelsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return selectedTemplate?.models ?? []
    }

    private var isValid: Bool {
        !apiKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        (isCustom ? !name.trimmingCharacters(in: .whitespaces).isEmpty && !baseUrl.trimmingCharacters(in: .whitespaces).isEmpty : true)
    }

    var body: some View {
        Form {
            // 供应商选择
            Section("模型供应商") {
                Picker("供应商", selection: $selectedKind) {
                    ForEach(ProviderTemplate.allBuiltins, id: \.kind) { tmpl in
                        Text(tmpl.name).tag(tmpl.kind)
                    }
                    Text("自定义").tag("custom")
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }
            .listRowBackground(sageListRowBackground)

            // 自定义时显示名称、Base URL、端点路径
            if isCustom {
                Section("名称") {
                    TextField("供应商名称", text: $name)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                .listRowBackground(sageListRowBackground)

                Section("Base URL") {
                    TextField("https://api.example.com", text: $baseUrl)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))
                }
                .listRowBackground(sageListRowBackground)

                Section("端点路径") {
                    TextField("/v1/chat/completions", text: $endpointPath)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                }
                .listRowBackground(sageListRowBackground)

                Section("API 类型") {
                    Picker("类型", selection: $apiType) {
                        Text("OpenAI 兼容").tag("openai-completions")
                        Text("Anthropic").tag("anthropic-messages")
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(sageListRowBackground)

                Section("模型列表") {
                    TextField("model-a, model-b", text: $modelsText)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                    Text("多个模型用逗号分隔")
                        .font(SageTheme.Typography.rowSubtitle)
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                }
                .listRowBackground(sageListRowBackground)
            } else {
                // 内置品牌显示信息（只读）
                if let tmpl = selectedTemplate {
                    Section("配置信息") {
                        LabeledContent("Base URL") {
                            Text(tmpl.baseUrl)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("API 类型") {
                            Text(tmpl.apiType == "anthropic-messages" ? "Anthropic" : "OpenAI 兼容")
                                .foregroundColor(.secondary)
                        }
                        LabeledContent("可用模型") {
                            VStack(alignment: .trailing, spacing: 2) {
                                ForEach(tmpl.models, id: \.self) { model in
                                    Text(model)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                    }
                    .listRowBackground(sageListRowBackground)
                }
            }

            // API Key
            Section {
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
                            .frame(width: 44, height: 44)
                    }
                }
            } header: {
                Text("API Key")
            } footer: {
                if let tmpl = selectedTemplate {
                    Link(destination: URL(string: tmpl.apiKeyUrl)!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                            Text("前往 \(tmpl.name) 官网获取 API Key")
                                .font(.system(size: 12))
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .listRowBackground(sageListRowBackground)

            // 保存按钮
            Section {
                Button {
                    Task { await saveProvider() }
                } label: {
                    if isSaving {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("保存中...")
                                .font(SageTheme.Typography.button)
                            Spacer()
                        }
                    } else {
                        Text("保存")
                    }
                }
                .buttonStyle(SagePrimaryButtonStyle())
                .disabled(!isValid || isSaving)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .font(SageTheme.Typography.rowSubtitle)
                        .foregroundColor(.red)
                }
                .listRowBackground(sageListRowBackground)
            }
        }
        .sageSettingsPage()
        .navigationTitle("添加模型")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private func saveProvider() async {
        isSaving = true
        errorMessage = nil
        do {
            let models = effectiveModels
            let input = CreateProviderInput(
                providerKind: selectedKind,
                displayName: effectiveName,
                apiType: effectiveApiType,
                baseUrl: effectiveBaseUrl,
                endpointPath: effectiveEndpointPath,
                models: models.isEmpty ? nil : models,
                defaultModel: isCustom ? models.first : selectedTemplate?.defaultModel,
                apiKey: apiKey.trimmingCharacters(in: .whitespaces),
                enabled: true,
                isDefault: cloudStore.providers.isEmpty,
                sortOrder: cloudStore.providers.count
            )
            let created = try await cloudStore.create(input)

            // 同步到本地 settingsService
            if created.isDefault {
                settingsService.currentSettings.defaultProvider = created.id
                settingsService.currentSettings.defaultModel = created.defaultModel
                settingsService.currentSettings.modelConfig = ModelConfig(
                    apiKey: nil,
                    baseUrl: created.baseUrl + created.endpointPath,
                    model: created.defaultModel,
                    apiType: created.apiType
                )
                settingsService.save()
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Cloud Provider Detail

struct CloudProviderDetailView: View {
    let provider: CloudProvider
    @EnvironmentObject var cloudStore: CloudProviderStore
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey: String = ""
    @State private var showKey = false
    @State private var selectedModel: String = ""
    @State private var testStatus: CloudTestStatus = .idle
    @State private var isSaving = false
    @State private var showDeleteAlert = false

    enum CloudTestStatus: Equatable {
        case idle, testing, success, failure(String)
    }

    var body: some View {
        Form {
            // 基本信息
            Section("配置") {
                LabeledContent("品牌") {
                    Text(provider.displayName)
                        .foregroundColor(.secondary)
                }
                LabeledContent("API 类型") {
                    Text(provider.apiType == "anthropic-messages" ? "Anthropic" : "OpenAI 兼容")
                        .foregroundColor(.secondary)
                }
                LabeledContent("Base URL") {
                    Text(provider.baseUrl)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .listRowBackground(sageListRowBackground)

            // 更新 API Key
            Section("API Key") {
                HStack {
                    if showKey {
                        TextField("输入新 Key 替换...", text: $apiKey)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))
                    } else {
                        SecureField("输入新 Key 替换...", text: $apiKey)
                    }
                    Button { showKey.toggle() } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
                            .frame(width: 44, height: 44)
                    }
                }
                Text("留空则保持原有 Key 不变")
                    .font(SageTheme.Typography.rowSubtitle)
                    .foregroundColor(SageTheme.ColorToken.mutedText)
            }
            .listRowBackground(sageListRowBackground)

            // 模型选择
            Section("模型") {
                ForEach(provider.models, id: \.self) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        HStack {
                            Text(model)
                                .foregroundColor(.primary)
                                .font(SageTheme.Typography.rowTitle)
                            Spacer()
                            if selectedModel == model {
                                Image(systemName: "checkmark")
                                    .foregroundColor(SageTheme.ColorToken.brand)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
            .listRowBackground(sageListRowBackground)

            // 连接测试
            Section("连接测试") {
                Button { testConnection() } label: {
                    HStack(spacing: 10) {
                        switch testStatus {
                        case .idle:
                            SageSymbolIcon(systemName: "bolt", tone: .brand)
                            Text("测试响应")
                                .font(SageTheme.Typography.rowTitle)
                                .foregroundColor(.primary)
                        case .testing:
                            ProgressView().scaleEffect(0.8)
                            Text("测试中...").font(SageTheme.Typography.rowTitle).foregroundColor(.secondary)
                        case .success:
                            SageSymbolIcon(systemName: "checkmark.circle", tone: .success)
                            Text("连接成功").font(SageTheme.Typography.rowTitle).foregroundColor(SageIconTone.success.foreground)
                        case .failure(let msg):
                            SageSymbolIcon(systemName: "xmark.circle", tone: .danger)
                            Text(msg).foregroundColor(.red).font(SageTheme.Typography.rowSubtitle).lineLimit(2)
                        }
                        Spacer()
                    }
                }
                .disabled(testStatus == .testing)
            }
            .listRowBackground(sageListRowBackground)

            // 保存并设为默认
            Section {
                Button {
                    Task { await saveAndSetDefault() }
                } label: {
                    if isSaving {
                        HStack {
                            Spacer()
                            ProgressView().scaleEffect(0.8)
                            Text("保存中...").font(SageTheme.Typography.button)
                            Spacer()
                        }
                    } else {
                        Text("保存并设为默认")
                    }
                }
                .buttonStyle(SagePrimaryButtonStyle())
                .disabled(isSaving)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            // 删除
            Section {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text("删除供应商")
                            .font(SageTheme.Typography.button)
                            .foregroundColor(SageIconTone.danger.foreground)
                        Spacer()
                    }
                }
                .listRowBackground(sageListRowBackground)
            }
        }
        .sageSettingsPage()
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedModel = provider.defaultModel ?? provider.models.first ?? ""
        }
        .alert("确认删除", isPresented: $showDeleteAlert) {
            Button("删除", role: .destructive) {
                Task { await deleteProvider() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复，API Key 将从云端永久移除")
        }
    }

    private func testConnection() {
        testStatus = .testing
        Task {
            do {
                let result = try await cloudStore.test(id: provider.id)
                if result.success {
                    testStatus = .success
                } else {
                    testStatus = .failure(result.error ?? "连接失败")
                }
            } catch {
                testStatus = .failure(error.localizedDescription)
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            testStatus = .idle
        }
    }

    private func saveAndSetDefault() async {
        isSaving = true
        do {
            // 更新字段（只传有变化的）
            var patch = UpdateProviderInput()
            if !apiKey.trimmingCharacters(in: .whitespaces).isEmpty {
                patch.apiKey = apiKey.trimmingCharacters(in: .whitespaces)
            }
            if selectedModel != provider.defaultModel {
                patch.defaultModel = selectedModel
            }
            if patch.apiKey != nil || patch.defaultModel != nil {
                try await cloudStore.update(id: provider.id, patch: patch)
            }
            try await cloudStore.setDefault(id: provider.id)

            // 同步到本地 settingsService
            settingsService.currentSettings.defaultProvider = provider.id
            settingsService.currentSettings.defaultModel = selectedModel.isEmpty ? provider.defaultModel : selectedModel
            settingsService.currentSettings.modelConfig = ModelConfig(
                apiKey: nil,
                baseUrl: provider.baseUrl + provider.endpointPath,
                model: selectedModel.isEmpty ? provider.defaultModel : selectedModel,
                apiType: provider.apiType
            )
            settingsService.save()

            dismiss()
        } catch {
            // 静默失败，用户可重试
        }
        isSaving = false
    }

    private func deleteProvider() async {
        do {
            try await cloudStore.delete(id: provider.id)
            if settingsService.currentSettings.defaultProvider == provider.id {
                settingsService.currentSettings.defaultProvider = nil
                settingsService.currentSettings.defaultModel = nil
                settingsService.currentSettings.modelConfig = nil
                settingsService.save()
            }
            dismiss()
        } catch {
            // 静默失败
        }
    }
}

import SwiftUI

/// 设置页 — 底部 sheet 弹出（ChatGPT 风格）
/// 分组：账户、模型配置、主题、关于
struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settingsService: SettingsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // ─── 账户 ─────────────────────────────────────
                Section("账户") {
                    if let user = authService.currentUser {
                        HStack {
                            Image(systemName: "envelope")
                                .foregroundColor(.secondary)
                            Text(user.email ?? "-")
                            Spacer()
                        }
                    }
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

                // ─── 模型配置 ──────────────────────────────────
                Section("模型") {
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

                // ─── 主题 ─────────────────────────────────────
                Section("主题") {
                    Picker("外观", selection: $settingsService.currentSettings.theme) {
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                        Text("系统").tag("system")
                    }
                    .onChange(of: settingsService.currentSettings.theme) { _ in
                        settingsService.save()
                    }
                }

                // ─── 应用设置 ──────────────────────────────────
                Section("应用设置") {
                    Picker("语言", selection: $settingsService.currentSettings.language) {
                        Text("中文").tag("zh")
                        Text("English").tag("en")
                    }
                    .onChange(of: settingsService.currentSettings.language) { _ in
                        settingsService.save()
                    }
                }

                // ─── 关于 ─────────────────────────────────────
                Section("关于") {
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

// MARK: - Provider Detail

struct ProviderDetailView: View {
    let provider: ProviderConfig
    @EnvironmentObject var settingsService: SettingsService
    @State private var apiKey: String = ""
    @State private var baseUrl: String = ""
    @State private var selectedModel: String = ""
    @State private var showKey = false
    @Environment(\.dismiss) private var dismiss

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
                    Button {
                        showKey.toggle()
                    } label: {
                        Image(systemName: showKey ? "eye.slash" : "eye")
                            .foregroundColor(.secondary)
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

            Section("模型") {
                ForEach(provider.models, id: \.self) { model in
                    Button {
                        selectedModel = model
                    } label: {
                        HStack {
                            Text(model)
                                .foregroundColor(.primary)
                            Spacer()
                            if selectedModel == model {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }

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
        }
    }

    private func saveAndDismiss() {
        if let idx = settingsService.currentSettings.providers.firstIndex(where: { $0.id == provider.id }) {
            settingsService.currentSettings.providers[idx].apiKey = apiKey
            settingsService.currentSettings.providers[idx].baseUrl = baseUrl.isEmpty ? provider.baseUrl : baseUrl
            settingsService.currentSettings.providers[idx].defaultModel = selectedModel
        }
        settingsService.currentSettings.defaultProvider = provider.id
        settingsService.currentSettings.defaultModel = selectedModel
        settingsService.currentSettings.modelConfig = ModelConfig(
            apiKey: apiKey,
            baseUrl: baseUrl.isEmpty ? provider.baseUrl : baseUrl,
            model: selectedModel,
            apiType: provider.apiType
        )
        settingsService.save()
        dismiss()
    }
}

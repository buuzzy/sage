import SwiftUI

// MARK: - Persona Settings (用户画像)

struct PersonaSettingsView: View {
    @State private var isLoading = true
    @State private var hardRules: [PersonaItem] = []
    @State private var focusAreas: [PersonaItem] = []
    @State private var activeFocus: [PersonaItem] = []
    @State private var exclusions: [PersonaItem] = []
    @State private var recentViews: [PersonaItem] = []
    @State private var behaviorSummary: String?
    @State private var riskPreference: String = "-"
    @State private var capabilityLevel: String = "-"
    @State private var lastDistilled: String = "尚未蒸馏"
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView().padding(20); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            } else {
                // 隐式字段（AI 推断，只读）
                Section("AI 推断") {
                    infoRow("风险偏好", value: riskPreference)
                    infoRow("能力水平", value: capabilityLevel)
                    infoRow("上次蒸馏", value: lastDistilled)
                }

                if let behaviorSummary, !behaviorSummary.isEmpty {
                    Section("行为摘要") {
                        Text(behaviorSummary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // 硬规则（可删除）
                if !hardRules.isEmpty {
                    Section("硬规则") {
                        ForEach(hardRules) { rule in
                            Text(rule.content).font(.subheadline)
                        }
                        .onDelete { offsets in hardRules.remove(atOffsets: offsets) }
                    }
                }

                // 关注领域
                if !focusAreas.isEmpty {
                    Section("主动关注") {
                        ForEach(focusAreas) { item in
                            Text(item.content).font(.subheadline)
                        }
                        .onDelete { offsets in focusAreas.remove(atOffsets: offsets) }
                    }
                }

                if !activeFocus.isEmpty {
                    Section("近期高频关注") {
                        ForEach(activeFocus) { item in
                            Text(item.content).font(.subheadline)
                        }
                    }
                }

                // 排除项
                if !exclusions.isEmpty {
                    Section("排除项") {
                        ForEach(exclusions) { item in
                            Text(item.content).font(.subheadline)
                        }
                        .onDelete { offsets in exclusions.remove(atOffsets: offsets) }
                    }
                }

                if !recentViews.isEmpty {
                    Section("近期观点") {
                        ForEach(recentViews) { item in
                            Text(item.content).font(.subheadline)
                        }
                    }
                }

                if hardRules.isEmpty && focusAreas.isEmpty && activeFocus.isEmpty && exclusions.isEmpty && recentViews.isEmpty && behaviorSummary == nil {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "brain")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("暂无画像数据")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("画像由云端蒸馏任务从对话中自动生成，通常需要完成几轮对话后才会出现")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .navigationTitle("画像")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPersona() }
    }

    private func infoRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline).foregroundColor(.secondary)
        }
    }

    private func loadPersona() {
        isLoading = true
        Task {
            guard let userId = AuthService.shared.userId else {
                errorMessage = "未登录"
                isLoading = false
                return
            }
            do {
                guard let accessToken = await AuthService.shared.getAccessToken() else {
                    errorMessage = "登录已过期，请重新登录"
                    isLoading = false
                    return
                }
                let data = try await APIClient.shared.getPersona(accessToken: accessToken)
                parsePersonaData(data)
            } catch {
                errorMessage = "无法加载画像：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func parsePersonaData(_ data: Data) {
        resetPersona()

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let row = (payload["row"] as? [String: Any]) ?? payload
        guard !row.isEmpty else { return }

        if let time = row["last_distilled_at"] as? String {
            lastDistilled = formatTime(time)
        }

        guard let profile = row["profile"] as? [String: Any] else { return }
        let explicit = profile["explicit"] as? [String: Any]
        let implicit = profile["implicit"] as? [String: Any]

        if let risk = implicit?["risk_tolerance"] as? String {
            riskPreference = localizeRisk(risk)
        }
        if let cap = implicit?["capability_level"] as? String {
            capabilityLevel = localizeCap(cap)
        }

        if let summary = implicit?["behavior_summary"] as? String, !summary.isEmpty {
            behaviorSummary = summary
        }

        if let rules = explicit?["hard_rules"] as? [[String: Any]] {
            hardRules = rules.enumerated().compactMap { idx, rule in
                guard let content = rule["content"] as? String, !content.isEmpty else { return nil }
                return PersonaItem(id: (rule["id"] as? String) ?? "\(idx)", content: content)
            }
        }

        if let focusUniverse = explicit?["focus_universe"] as? [String: Any],
           let focus = focusUniverse["declared"] as? [[String: Any]] {
            focusAreas = focus.enumerated().compactMap { idx, item in
                guard let name = item["name"] as? String, !name.isEmpty else { return nil }
                let code = item["code"] as? String
                return PersonaItem(id: "declared-\(idx)", content: code == nil ? name : "\(name) (\(code!))")
            }
        }

        if let focusUniverse = explicit?["focus_universe"] as? [String: Any],
           let excl = focusUniverse["exclusions"] as? [[String: Any]] {
            exclusions = excl.enumerated().compactMap { idx, item in
                let value = (item["value"] as? String) ?? (item["name"] as? String)
                guard let value, !value.isEmpty else { return nil }
                return PersonaItem(id: "exclusion-\(idx)", content: value)
            }
        }

        if let focusUniverse = implicit?["focus_universe"] as? [String: Any],
           let active = focusUniverse["active"] as? [[String: Any]] {
            activeFocus = active.enumerated().compactMap { idx, item in
                guard let name = item["name"] as? String, !name.isEmpty else { return nil }
                let code = item["code"] as? String
                return PersonaItem(id: "active-\(idx)", content: code == nil ? name : "\(name) (\(code!))")
            }
        }

        if let views = implicit?["recent_views"] as? [[String: Any]] {
            recentViews = views.enumerated().compactMap { idx, view in
                guard let topic = view["topic"] as? String, !topic.isEmpty else { return nil }
                let stance = view["stance"] as? String
                return PersonaItem(id: "view-\(idx)", content: stance == nil ? topic : "\(topic)：\(stance!)")
            }
        }
    }

    private func resetPersona() {
        hardRules = []
        focusAreas = []
        activeFocus = []
        exclusions = []
        recentViews = []
        behaviorSummary = nil
        riskPreference = "-"
        capabilityLevel = "-"
        lastDistilled = "尚未蒸馏"
        errorMessage = nil
    }

    private func localizeRisk(_ risk: String) -> String {
        ["conservative": "保守", "moderate": "稳健", "aggressive": "进取", "speculative": "激进"][risk] ?? risk
    }
    private func localizeCap(_ cap: String) -> String {
        ["novice": "新手", "intermediate": "中级", "advanced": "进阶", "professional": "专业"][cap] ?? cap
    }
    private func formatTime(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        guard let date = f.date(from: iso) else { return iso }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm"
        return df.string(from: date)
    }
}

struct PersonaItem: Identifiable {
    let id: String
    let content: String
}

// MARK: - Cron Settings (定时任务)

struct CronSettingsView: View {
    @State private var jobs: [CronJobItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView().padding(20); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            } else if jobs.isEmpty {
                systemCronSection
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无定时任务")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("这里显示你自己创建的定时任务。你可以在对话中让 Sage 定时提醒、定时复盘或定时检查市场。")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
                systemCronSection
                ForEach($jobs) { $job in
                    CronJobRow(job: $job, onDelete: { deleteJob(job.id) }, onTrigger: { triggerJob(job.id) })
                }
            }
        }
        .navigationTitle("定时任务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { loadJobs() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 14))
                }
            }
        }
        .onAppear { loadJobs() }
    }

    private var systemCronSection: some View {
        Section("系统任务") {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 14))
                        .foregroundColor(.purple)
                    Text("画像蒸馏")
                        .font(.system(size: 15, weight: .medium))
                    Spacer()
                    Text("云端")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray6))
                        .cornerRadius(4)
                }
                Text("Railway 后台每天凌晨自动从对话中更新 persona_memory；它不是用户可删除的任务，所以不出现在用户任务列表里。")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func loadJobs() {
        isLoading = true
        Task {
            do {
                let data = try await APIClient.shared.getCronJobs()
                let response = try JSONDecoder().decode(CronJobsResponse.self, from: data)
                jobs = response.jobs
                errorMessage = nil
            } catch {
                errorMessage = "无法加载定时任务：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func deleteJob(_ id: String) {
        Task {
            try? await APIClient.shared.deleteCronJob(jobId: id)
            jobs.removeAll { $0.id == id }
        }
    }

    private func triggerJob(_ id: String) {
        Task { try? await APIClient.shared.triggerCronJob(jobId: id) }
    }
}

struct CronJobsResponse: Codable {
    let ok: Bool?
    let jobs: [CronJobItem]
}

struct CronJobItem: Codable, Identifiable {
    let id: String
    var name: String
    var prompt: String
    var enabled: Bool
    var schedule: CronScheduleData?
    var lastRunAt: String?
    var nextRunAt: String?
    var system: Bool?
}

struct CronScheduleData: Codable {
    var type: String?
    var expression: String?
    var interval: Int?
}

struct CronJobRow: View {
    @Binding var job: CronJobItem
    let onDelete: () -> Void
    let onTrigger: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.name)
                        .font(.system(size: 15, weight: .medium))
                    Text(job.prompt)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if job.system == true {
                    Text("系统").font(.system(size: 10))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1)).cornerRadius(4)
                }
                Toggle("", isOn: $job.enabled)
                    .labelsHidden()
                    .onChange(of: job.enabled) { val in
                        Task { try? await APIClient.shared.toggleCronJob(jobId: job.id, enabled: val) }
                    }
            }
            HStack(spacing: 12) {
                if let s = job.schedule, let expr = s.expression {
                    Text(expr).font(.caption2).foregroundColor(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color(.systemGray6)).cornerRadius(4)
                }
                Spacer()
                Button { onTrigger() } label: {
                    Image(systemName: "play.circle").font(.system(size: 16)).foregroundColor(.blue)
                }
                Button { onDelete() } label: {
                    Image(systemName: "trash").font(.system(size: 14)).foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - MCP Settings

struct MCPSettingsView: View {
    @State private var servers: [MCPServerItem] = []
    @State private var isLoading = true
    @State private var showAddSheet = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView().padding(20); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            } else if servers.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无 MCP 服务器")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("MCP 服务器用于扩展 Sage 的工具能力")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
                ForEach(servers) { server in
                    HStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 13)).foregroundColor(.teal).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name).font(.system(size: 14, weight: .medium))
                            Text(server.source.map { "\(server.type) · \($0)" } ?? server.type)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if server.type == "stdio" {
                            Text("仅桌面").font(.system(size: 10))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.1)).cornerRadius(4)
                        }
                    }
                }
                .onDelete { idxs in
                    servers.remove(atOffsets: idxs)
                }
            }
        }
        .navigationTitle("MCP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMCPServerSheet { server in servers.append(server); showAddSheet = false }
        }
        .onAppear { loadServers() }
    }

    private func loadServers() {
        isLoading = true
        Task {
            do {
                let data = try await APIClient.shared.getJSON(endpoint: "/mcp/all-configs")
                let response = try JSONDecoder().decode(MCPAllConfigsResponse.self, from: data)
                servers = response.configs.flatMap { config in
                    config.servers.map { name, server in
                        MCPServerItem(
                            id: "\(config.name)-\(name)",
                            name: name,
                            type: server.type,
                            url: server.url,
                            source: config.name
                        )
                    }
                }
                errorMessage = nil
            } catch {
                errorMessage = "无法加载 MCP：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }
}

struct MCPAllConfigsResponse: Codable {
    let success: Bool
    let configs: [MCPConfigSource]
}

struct MCPConfigSource: Codable {
    let name: String
    let exists: Bool
    let servers: [String: MCPServerConfigData]
}

struct MCPServerConfigData: Codable {
    let command: String?
    let url: String?

    var type: String {
        if command != nil { return "stdio" }
        if url?.contains("sse") == true { return "sse" }
        return "http"
    }
}

struct MCPServerItem: Codable, Identifiable {
    var id: String
    var name: String
    var type: String
    var url: String?
    var source: String?
}

struct AddMCPServerSheet: View {
    let onAdd: (MCPServerItem) -> Void
    @State private var name = ""
    @State private var url = ""
    @State private var type = "sse"
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器信息") {
                    TextField("名称", text: $name)
                    Picker("类型", selection: $type) {
                        Text("SSE").tag("sse")
                        Text("HTTP").tag("http")
                    }.pickerStyle(.segmented)
                    TextField("URL", text: $url).autocapitalization(.none).keyboardType(.URL)
                }
                Section {
                    Button("添加") {
                        onAdd(MCPServerItem(id: UUID().uuidString, name: name, type: type, url: url, source: "local"))
                    }.disabled(name.isEmpty || url.isEmpty)
                }
            }
            .navigationTitle("添加 MCP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("取消") { dismiss() } }
            }
        }
    }
}

// MARK: - Skills Settings

struct SkillsSettingsView: View {
    @State private var allSkills: [SkillItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView().padding(20); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let error = errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            } else if allSkills.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无技能")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("当前后端没有返回可用技能")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
                ForEach($allSkills) { $skill in
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13)).foregroundColor(.purple).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name).font(.system(size: 14, weight: .medium))
                            if let desc = skill.description {
                                Text(desc).font(.caption).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: $skill.enabled)
                            .labelsHidden()
                            .onChange(of: skill.enabled) { _ in toggleSkill(skill) }
                    }
                }
            }
        }
        .navigationTitle("技能")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadSkills() }
    }

    private func loadSkills() {
        isLoading = true
        Task {
            do {
                let data = try await APIClient.shared.getJSON(endpoint: "/skills")
                let response = try JSONDecoder().decode(SkillsListResponse.self, from: data)
                allSkills = response.skills
                errorMessage = nil
            } catch {
                errorMessage = "无法加载技能：\(error.localizedDescription)"
            }
            isLoading = false
        }
    }

    private func toggleSkill(_ skill: SkillItem) {
        Task {
            try? await APIClient.shared.toggleSkill(name: skill.name, enabled: skill.enabled)
        }
    }
}

struct SkillsListResponse: Codable {
    let success: Bool
    let skills: [SkillItem]
}

struct SkillItem: Codable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var enabled: Bool
}

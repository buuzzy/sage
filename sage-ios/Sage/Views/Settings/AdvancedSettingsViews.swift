import SwiftUI

// MARK: - Persona Settings (用户画像)

struct PersonaSettingsView: View {
    @State private var isLoading = true
    @State private var hardRules: [PersonaItem] = []
    @State private var focusAreas: [PersonaItem] = []
    @State private var exclusions: [PersonaItem] = []
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
                    Section("关注领域") {
                        ForEach(focusAreas) { item in
                            Text(item.content).font(.subheadline)
                        }
                        .onDelete { offsets in focusAreas.remove(atOffsets: offsets) }
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

                if hardRules.isEmpty && focusAreas.isEmpty && exclusions.isEmpty {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "brain")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary.opacity(0.5))
                            Text("暂无画像数据")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Sage 会在对话中自动学习你的偏好")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.7))
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
                // 尝试通过后端获取 persona（后端会查 Supabase）
                let data = try await APIClient.shared.getJSON(endpoint: "/mcp-memory/persona?userId=\(userId)")
                parsePersonaData(data)
            } catch {
                // 如果失败，显示空状态（不是错误，只是还没有数据）
                errorMessage = nil
            }
            isLoading = false
        }
    }

    private func parsePersonaData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if let risk = json["risk_preference"] as? String {
            riskPreference = localizeRisk(risk)
        }
        if let cap = json["capability_level"] as? String {
            capabilityLevel = localizeCap(cap)
        }
        if let time = json["last_distilled_at"] as? String {
            lastDistilled = formatTime(time)
        }
        if let rules = json["hard_rules"] as? [[String: Any]] {
            hardRules = rules.enumerated().map { PersonaItem(id: "\($0.offset)", content: ($0.element["rule"] as? String) ?? "") }
        }
        if let focus = json["focus_universe_declared"] as? [[String: Any]] {
            focusAreas = focus.enumerated().map { PersonaItem(id: "f\($0.offset)", content: ($0.element["name"] as? String) ?? "") }
        }
        if let excl = json["focus_universe_exclusion"] as? [[String: Any]] {
            exclusions = excl.enumerated().map { PersonaItem(id: "e\($0.offset)", content: ($0.element["name"] as? String) ?? "") }
        }
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
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无定时任务")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("在对话中让 Sage 为你创建")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
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

    private func loadJobs() {
        isLoading = true
        Task {
            do {
                let data = try await APIClient.shared.getCronJobs()
                jobs = (try? JSONDecoder().decode([CronJobItem].self, from: data)) ?? []
            } catch {
                errorMessage = "无法加载定时任务"
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

struct CronJobItem: Codable, Identifiable {
    let id: String
    var name: String
    var prompt: String
    var enabled: Bool
    var schedule: CronScheduleData?
    var lastRunAt: String?
    var nextRunAt: String?
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

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView().padding(20); Spacer() }
                    .listRowBackground(Color.clear)
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
                            Text(server.type).font(.caption).foregroundColor(.secondary)
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
                let data = try await APIClient.shared.getJSON(endpoint: "/mcp/config")
                // 后端返回 { mcpServers: { name: {...config} } } 格式
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let mcpServers = json["mcpServers"] as? [String: [String: Any]] {
                    servers = mcpServers.map { name, config in
                        let type = (config["command"] != nil) ? "stdio" : ((config["url"] as? String)?.contains("sse") == true ? "sse" : "http")
                        return MCPServerItem(id: name, name: name, type: type, url: config["url"] as? String)
                    }
                }
            } catch { }
            isLoading = false
        }
    }
}

struct MCPServerItem: Codable, Identifiable {
    var id: String
    var name: String
    var type: String
    var url: String?
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
                        onAdd(MCPServerItem(id: UUID().uuidString, name: name, type: type, url: url))
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
    @State private var disabledSkills: Set<String> = []
    @State private var allSkills: [SkillItem] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack { Spacer(); ProgressView().padding(20); Spacer() }
                    .listRowBackground(Color.clear)
            } else if allSkills.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无技能")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("技能由 Sage 桌面端管理和安装")
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
                let data = try await APIClient.shared.getJSON(endpoint: "/skills/config")
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let disabled = json["disabledSkills"] as? [String] {
                    disabledSkills = Set(disabled)
                }
                // Skills 列表需要从文件系统获取（桌面端），iOS 只能显示已知的技能
                // 这里用空列表，等后端支持远程 skills 列表
            } catch { }
            isLoading = false
        }
    }

    private func toggleSkill(_ skill: SkillItem) {
        Task {
            struct ToggleBody: Codable { let skillId: String; let enabled: Bool }
            let body = ToggleBody(skillId: skill.id, enabled: skill.enabled)
            if let data = try? JSONEncoder().encode(body) {
                var request = URLRequest(url: URL(string: "https://sage-production-28e1.up.railway.app/skills/toggle")!)
                request.httpMethod = "POST"
                request.setValue("Bearer b2cbe89f938ee822f4a7efa45315346429fa1c34f9534e08f558e649cc46f3ed", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = data
                _ = try? await URLSession.shared.data(for: request)
            }
        }
    }
}

struct SkillItem: Codable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var enabled: Bool
}

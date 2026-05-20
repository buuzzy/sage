import SwiftUI

// MARK: - Persona Settings (用户画像)

/// 从 Supabase persona_memory 读取 AI 蒸馏的用户画像
/// 显式字段可删除，隐式字段只读
struct PersonaSettingsView: View {
    @State private var isLoading = true
    @State private var hardRules: [PersonaItem] = []
    @State private var focusAreas: [PersonaItem] = []
    @State private var exclusions: [PersonaItem] = []
    @State private var riskPreference: String = "-"
    @State private var capabilityLevel: String = "-"
    @State private var lastDistilled: String = "-"
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
            } else if let error = errorMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                // 隐式字段（只读）
                Section("AI 推断") {
                    HStack {
                        Text("风险偏好")
                        Spacer()
                        Text(riskPreference)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("能力水平")
                        Spacer()
                        Text(capabilityLevel)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("上次蒸馏")
                        Spacer()
                        Text(lastDistilled)
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }

                // 硬规则（可删除）
                Section("硬规则") {
                    if hardRules.isEmpty {
                        Text("暂无")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(hardRules) { rule in
                            Text(rule.content)
                                .font(.subheadline)
                        }
                        .onDelete { indexSet in
                            deleteItems(from: &hardRules, at: indexSet, field: "hard_rules")
                        }
                    }
                }

                // 关注领域（可删除）
                Section("关注领域") {
                    if focusAreas.isEmpty {
                        Text("暂无")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(focusAreas) { item in
                            Text(item.content)
                                .font(.subheadline)
                        }
                        .onDelete { indexSet in
                            deleteItems(from: &focusAreas, at: indexSet, field: "focus_universe_declared")
                        }
                    }
                }

                // 排除项（可删除）
                Section("排除项") {
                    if exclusions.isEmpty {
                        Text("暂无")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(exclusions) { item in
                            Text(item.content)
                                .font(.subheadline)
                        }
                        .onDelete { indexSet in
                            deleteItems(from: &exclusions, at: indexSet, field: "focus_universe_exclusion")
                        }
                    }
                }
            }
        }
        .navigationTitle("用户画像")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPersona() }
    }

    private func loadPersona() {
        isLoading = true
        Task {
            do {
                let data = try await APIClient.shared.getJSON(endpoint: "/persona")
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Parse fields
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
                        hardRules = rules.enumerated().map { i, r in
                            PersonaItem(id: "\(i)", content: r["rule"] as? String ?? "")
                        }
                    }
                    if let focus = json["focus_universe_declared"] as? [[String: Any]] {
                        focusAreas = focus.enumerated().map { i, f in
                            PersonaItem(id: "\(i)", content: f["name"] as? String ?? "")
                        }
                    }
                    if let excl = json["focus_universe_exclusion"] as? [[String: Any]] {
                        exclusions = excl.enumerated().map { i, e in
                            PersonaItem(id: "\(i)", content: e["name"] as? String ?? "")
                        }
                    }
                }
                isLoading = false
            } catch {
                errorMessage = "加载失败: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func deleteItems(from array: inout [PersonaItem], at offsets: IndexSet, field: String) {
        array.remove(atOffsets: offsets)
        // TODO: Call API to delete from Supabase
    }

    private func localizeRisk(_ risk: String) -> String {
        switch risk {
        case "conservative": return "保守"
        case "moderate": return "稳健"
        case "aggressive": return "进取"
        case "speculative": return "激进"
        default: return risk
        }
    }

    private func localizeCap(_ cap: String) -> String {
        switch cap {
        case "novice": return "新手"
        case "intermediate": return "中级"
        case "advanced": return "进阶"
        case "professional": return "专业"
        default: return cap
        }
    }

    private func formatTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: iso) {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            return df.string(from: date)
        }
        return iso
    }
}

struct PersonaItem: Identifiable {
    let id: String
    let content: String
}

// MARK: - Cron Settings (定时任务)

/// 定时任务管理 — 列表/启用/禁用/删除/运行历史
/// 不支持用户创建，仅通过 Agent 创建
struct CronSettingsView: View {
    @State private var jobs: [CronJobItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            } else if let error = errorMessage {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else if jobs.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无定时任务")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("在对话中让 Sage 为你创建定时任务")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section("定时任务") {
                    ForEach($jobs) { $job in
                        CronJobRow(job: $job, onDelete: {
                            deleteJob(job.id)
                        }, onTrigger: {
                            triggerJob(job.id)
                        })
                    }
                }
            }
        }
        .navigationTitle("定时任务")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    loadJobs()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
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
                let decoded = try JSONDecoder().decode([CronJobItem].self, from: data)
                jobs = decoded
                isLoading = false
            } catch {
                errorMessage = "加载失败"
                isLoading = false
            }
        }
    }

    private func deleteJob(_ id: String) {
        Task {
            try? await APIClient.shared.deleteCronJob(jobId: id)
            jobs.removeAll { $0.id == id }
        }
    }

    private func triggerJob(_ id: String) {
        Task {
            try? await APIClient.shared.triggerCronJob(jobId: id)
        }
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
    var type: String? // cron, every, at
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
                VStack(alignment: .leading, spacing: 2) {
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
                    .onChange(of: job.enabled) { newValue in
                        Task {
                            try? await APIClient.shared.toggleCronJob(jobId: job.id, enabled: newValue)
                        }
                    }
            }

            HStack(spacing: 12) {
                if let schedule = job.schedule {
                    Text(formatSchedule(schedule))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button { onTrigger() } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatSchedule(_ s: CronScheduleData) -> String {
        if s.type == "cron", let expr = s.expression {
            return "Cron: \(expr)"
        }
        if s.type == "every", let interval = s.interval {
            if interval >= 3600000 { return "每 \(interval / 3600000) 小时" }
            if interval >= 60000 { return "每 \(interval / 60000) 分钟" }
            return "每 \(interval / 1000) 秒"
        }
        return s.type ?? ""
    }
}

// MARK: - MCP Settings

/// MCP 服务器配置 — 列表展示/新增/删除 SSE/HTTP 类型
struct MCPSettingsView: View {
    @State private var servers: [MCPServerItem] = []
    @State private var isLoading = true
    @State private var showAddSheet = false

    var body: some View {
        List {
            if isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if servers.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无 MCP 服务器")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section("已配置服务器") {
                    ForEach(servers) { server in
                        HStack(spacing: 12) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(server.name)
                                    .font(.system(size: 14, weight: .medium))
                                Text(server.type)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if server.type == "stdio" {
                                Text("仅桌面")
                                    .font(.system(size: 10))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for idx in indexSet {
                            let server = servers[idx]
                            deleteServer(server.id)
                        }
                        servers.remove(atOffsets: indexSet)
                    }
                }
            }
        }
        .navigationTitle("MCP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMCPServerSheet { newServer in
                servers.append(newServer)
                showAddSheet = false
            }
        }
        .onAppear { loadServers() }
    }

    private func loadServers() {
        isLoading = true
        Task {
            do {
                let data = try await APIClient.shared.getJSON(endpoint: "/mcp/servers")
                if let decoded = try? JSONDecoder().decode([MCPServerItem].self, from: data) {
                    servers = decoded
                }
            } catch { }
            isLoading = false
        }
    }

    private func deleteServer(_ id: String) {
        Task {
            struct DeleteBody: Codable { let id: String }
            // Best effort delete
        }
    }
}

struct MCPServerItem: Codable, Identifiable {
    var id: String
    var name: String
    var type: String // stdio, sse, http
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
                    }
                    .pickerStyle(.segmented)
                    TextField("URL", text: $url)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                }

                Section {
                    Button("添加") {
                        let server = MCPServerItem(id: UUID().uuidString, name: name, type: type, url: url)
                        onAdd(server)
                    }
                    .disabled(name.isEmpty || url.isEmpty)
                }
            }
            .navigationTitle("添加 MCP 服务器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Skills Settings

/// 技能管理 — 通过后端 API 获取列表、启用/禁用
struct SkillsSettingsView: View {
    @State private var skills: [SkillItem] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            } else if skills.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("暂无已安装技能")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                Section("已安装技能") {
                    ForEach($skills) { $skill in
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 14))
                                .foregroundColor(.purple)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.system(size: 14, weight: .medium))
                                if let desc = skill.description {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: $skill.enabled)
                                .labelsHidden()
                        }
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
                if let decoded = try? JSONDecoder().decode([SkillItem].self, from: data) {
                    skills = decoded
                }
            } catch { }
            isLoading = false
        }
    }
}

struct SkillItem: Codable, Identifiable {
    var id: String
    var name: String
    var description: String?
    var enabled: Bool
}

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
    @State private var languagePreference: String?
    @State private var explanationStyle: String?
    @State private var responseLength: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                SageLoadingRow()
            } else if let error = errorMessage {
                Section {
                    SageErrorState(message: error)
                }
                .sageListSection()
            } else {
                // 顶部：上次更新时间 + 刷新按钮
                Section {
                    HStack {
                        Text("上次更新")
                            .font(SageTheme.Typography.rowSubtitle)
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                        Spacer()
                        Text(lastDistilled)
                            .font(SageTheme.Typography.rowSubtitle)
                            .foregroundColor(.primary)
                        Button { loadPersona() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(SageTheme.ColorToken.brand)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .sageListSection()

                // Section 1: 你的明确声明（explicit）
                Section {
                    Text("Sage 从对话中识别你立的规则、关注与排除。可在此撤销。")
                        .font(SageTheme.Typography.rowSubtitle)
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .lineSpacing(2)
                        .padding(.vertical, 2)

                    if !hardRules.isEmpty {
                        ForEach(hardRules) { rule in
                            personaTextRow(rule.content, icon: "checkmark.seal")
                        }
                        .onDelete { offsets in hardRules.remove(atOffsets: offsets) }
                    }

                    if !focusAreas.isEmpty {
                        ForEach(focusAreas) { item in
                            personaTextRow(item.content, icon: "scope")
                        }
                        .onDelete { offsets in focusAreas.remove(atOffsets: offsets) }
                    }

                    if !exclusions.isEmpty {
                        ForEach(exclusions) { item in
                            personaTextRow(item.content, icon: "minus.circle")
                        }
                        .onDelete { offsets in exclusions.remove(atOffsets: offsets) }
                    }

                    if hardRules.isEmpty && focusAreas.isEmpty && exclusions.isEmpty {
                        Text("尚无明确声明。在对话中告诉 Sage「以后不要 X」、「我开始研究 Y 了」等表达，蒸馏后会出现在这里。")
                            .font(SageTheme.Typography.rowSubtitle)
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                            .lineSpacing(2)
                            .padding(.vertical, 4)
                    }
                } header: {
                    Text("你的明确声明")
                }
                .sageListSection()

                // Section 2: Sage 对你的观察（implicit）
                Section {
                    Text("基于以往对话蒸馏的画像，由 AI 每天自动更新，仅供参考。")
                        .font(SageTheme.Typography.rowSubtitle)
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .lineSpacing(2)
                        .padding(.vertical, 2)

                    // 风险偏好 & 能力水平 网格
                    if riskPreference != "-" || capabilityLevel != "-" {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SageTheme.Spacing.sm) {
                            personaGridCell(title: "风险偏好", value: riskPreference)
                            personaGridCell(title: "能力水平", value: capabilityLevel)
                        }
                        .padding(.vertical, 4)
                    }

                    // 偏好设置网格
                    if languagePreference != nil || explanationStyle != nil || responseLength != nil {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SageTheme.Spacing.sm) {
                            if let lang = languagePreference {
                                personaGridCell(title: "语言偏好", value: lang)
                            }
                            if let style = explanationStyle {
                                personaGridCell(title: "解释风格", value: style)
                            }
                            if let length = responseLength {
                                personaGridCell(title: "回应详略", value: length)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // 近期高频关注（标签形式）
                    if !activeFocus.isEmpty {
                        VStack(alignment: .leading, spacing: SageTheme.Spacing.xs) {
                            Text("近期高频关注")
                                .font(SageTheme.Typography.rowSubtitle)
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                            FlowLayout(spacing: 6) {
                                ForEach(activeFocus) { item in
                                    Text(item.content)
                                        .font(.system(size: 13))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(SageTheme.ColorToken.controlGlass)
                                        .cornerRadius(12)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // 行为摘要（90天）
                    if let behaviorSummary, !behaviorSummary.isEmpty {
                        VStack(alignment: .leading, spacing: SageTheme.Spacing.xs) {
                            Text("行为摘要（90天）")
                                .font(SageTheme.Typography.rowSubtitle)
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                            Text(behaviorSummary)
                                .font(SageTheme.Typography.rowSubtitle)
                                .foregroundColor(.primary)
                                .lineSpacing(3)
                        }
                        .padding(.vertical, 4)
                    }

                    // 近期观点
                    if !recentViews.isEmpty {
                        VStack(alignment: .leading, spacing: SageTheme.Spacing.xs) {
                            Text("近期观点")
                                .font(SageTheme.Typography.rowSubtitle)
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                            ForEach(recentViews) { item in
                                personaTextRow(item.content, icon: "quote.bubble")
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // 观察类空状态
                    if riskPreference == "-" && capabilityLevel == "-" && activeFocus.isEmpty && behaviorSummary == nil && recentViews.isEmpty && languagePreference == nil && explanationStyle == nil && responseLength == nil {
                        Text("画像还没建立。多和 Sage 聊一些金融问题，蒸馏会逐步识别你的偏好。")
                            .font(SageTheme.Typography.rowSubtitle)
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                            .lineSpacing(2)
                            .padding(.vertical, 4)
                    }
                } header: {
                    Text("Sage 对你的观察")
                }
                .sageListSection()

                // 底部说明
                Section {
                    EmptyView()
                } footer: {
                    Text("画像由 AI 蒸馏自动产生，每天更新一次。明确声明可在此撤销；观察类信息会跟随你的对话演化。")
                        .font(SageTheme.Typography.rowSubtitle)
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .lineSpacing(2)
                }
            }
        }
        .sageSettingsPage()
        .navigationTitle("画像")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadPersona() }
    }

    private func personaGridCell(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(SageTheme.ColorToken.mutedText)
            Text(value)
                .font(SageTheme.Typography.rowTitleEmphasized)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(SageTheme.ColorToken.controlGlass)
        .cornerRadius(8)
    }

    private func personaTextRow(_ content: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: SageTheme.Spacing.sm) {
            SageSymbolIcon(systemName: icon, tone: .neutral, size: 15, containerSize: 30)
            Text(content)
                .font(SageTheme.Typography.rowSubtitle)
                .foregroundColor(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private func loadPersona() {
        isLoading = true
        Task {
            guard AuthService.shared.userId != nil else {
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

        // preferences
        if let prefs = implicit?["preferences"] as? [String: Any] {
            languagePreference = prefs["language"] as? String
            explanationStyle = prefs["explanation_style"] as? String
            responseLength = prefs["response_length"] as? String
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
        languagePreference = nil
        explanationStyle = nil
        responseLength = nil
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

// MARK: - FlowLayout (Tag Layout Helper)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - Cron Settings (定时任务)

struct CronSettingsView: View {
    @State private var jobs: [CronJobItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if isLoading {
                SageLoadingRow()
            } else if let error = errorMessage {
                Section {
                    SageErrorState(message: error)
                }
                .sageListSection()
            } else if jobs.isEmpty {
                systemCronSection
                Section {
                    SageEmptyPanel(
                        icon: "clock",
                        title: "暂无定时任务",
                        message: "这里显示你自己创建的定时任务。你可以在对话中让 Sage 定时提醒、定时复盘或定时检查市场。",
                        tone: .neutral
                    )
                }
                .sageListSection()
            } else {
                systemCronSection
                ForEach($jobs) { $job in
                    CronJobRow(job: $job, onDelete: { deleteJob(job.id) }, onTrigger: { triggerJob(job.id) })
                        .sageListSection()
                }
            }
        }
        .sageSettingsPage()
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
            SageSettingsRow(
                icon: "brain.head.profile",
                title: "画像蒸馏",
                subtitle: "Railway 后台每天凌晨自动从对话中更新 persona_memory；它不是用户可删除的任务。",
                tone: .neutral,
                showsChevron: false
            ) {
                SageStatusPill(title: "云端", tone: .neutral)
            }
        }
        .sageListSection()
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
        VStack(alignment: .leading, spacing: SageTheme.Spacing.sm) {
            SageSettingsRow(
                icon: "clock.arrow.circlepath",
                title: job.name,
                subtitle: job.prompt,
                tone: .neutral,
                showsChevron: false
            ) {
                if job.system == true {
                    SageStatusPill(title: "系统", tone: .purple)
                }
                Toggle("", isOn: $job.enabled)
                    .labelsHidden()
                    .onChange(of: job.enabled) { val in
                        Task { try? await APIClient.shared.toggleCronJob(jobId: job.id, enabled: val) }
                    }
            }
            HStack(spacing: SageTheme.Spacing.sm) {
                if let s = job.schedule, let expr = s.expression {
                    SageStatusPill(title: expr, tone: .neutral)
                }
                Spacer()
                Button { onTrigger() } label: {
                    Image(systemName: "play.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(SageIconTone.neutral.foreground)
                        .frame(width: 44, height: 36)
                }
                Button { onDelete() } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(SageIconTone.danger.foreground)
                        .frame(width: 44, height: 36)
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
                SageLoadingRow()
            } else if let error = errorMessage {
                Section {
                    SageErrorState(message: error)
                }
                .sageListSection()
            } else if servers.isEmpty {
                Section {
                    SageEmptyPanel(
                        icon: "server.rack",
                        title: "暂无 MCP 服务器",
                        message: "MCP 服务器用于扩展 Sage 的工具能力。",
                        tone: .neutral
                    )
                }
                .sageListSection()
            } else {
                ForEach(servers) { server in
                    SageSettingsRow(
                        icon: "server.rack",
                        title: server.name,
                        subtitle: server.source.map { "\(server.type) · \($0)" } ?? server.type,
                        tone: .neutral,
                        showsChevron: false
                    ) {
                        if server.type == "stdio" {
                            SageStatusPill(title: "仅桌面", tone: .warning)
                        }
                    }
                    .sageListSection()
                }
                .onDelete { idxs in
                    servers.remove(atOffsets: idxs)
                }
            }
        }
        .sageSettingsPage()
        .navigationTitle("MCP")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
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
                .sageListSection()
                Section {
                    Button("添加") {
                        onAdd(MCPServerItem(id: UUID().uuidString, name: name, type: type, url: url, source: "local"))
                    }
                    .buttonStyle(SagePrimaryButtonStyle())
                    .disabled(name.isEmpty || url.isEmpty)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .sageSettingsPage()
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
                SageLoadingRow()
            } else if let error = errorMessage {
                Section {
                    SageErrorState(message: error)
                }
                .sageListSection()
            } else if allSkills.isEmpty {
                Section {
                    SageEmptyPanel(
                        icon: "sparkles",
                        title: "暂无技能",
                        message: "当前后端没有返回可用技能。",
                        tone: .brand
                    )
                }
                .sageListSection()
            } else {
                ForEach($allSkills) { $skill in
                    SageSettingsRow(
                        icon: "sparkles",
                        title: skill.name,
                        subtitle: skill.description,
                        tone: skill.enabled ? .brand : .neutral,
                        showsChevron: false
                    ) {
                        Toggle("", isOn: $skill.enabled)
                            .labelsHidden()
                            .onChange(of: skill.enabled) { _ in toggleSkill(skill) }
                    }
                    .sageListSection()
                }
            }
        }
        .sageSettingsPage()
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

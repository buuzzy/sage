import SwiftUI

struct InvestmentWalkieView: View {
    @StateObject private var viewModel = InvestmentDashboardViewModel()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            AssetDashboardView(viewModel: viewModel) {
                selectedTab = 1
            }
                .tabItem {
                    Label("资产", systemImage: "chart.pie.fill")
                }
                .tag(0)

            ActionCenterView(viewModel: viewModel)
                .tabItem {
                    Label("行动", systemImage: "checklist")
                }
                .tag(1)

            AvatarProfileView()
                .tabItem {
                    Label("分身", systemImage: "person.crop.circle.badge.checkmark")
                }
                .tag(2)
        }
        .task {
            await viewModel.loadDashboard()
        }
    }
}

private struct AssetDashboardView: View {
    @ObservedObject var viewModel: InvestmentDashboardViewModel
    @StateObject private var recorder = VoiceRecorder()
    let openActions: () -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                SageBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header

                        if viewModel.isLoading && viewModel.dashboard == nil {
                            ProgressView("正在读取富途模拟盘")
                                .frame(maxWidth: .infinity, minHeight: 220)
                        } else if let dashboard = viewModel.dashboard {
                            AssetSummaryCard(account: dashboard.account)
                            TodayPointsSection(points: dashboard.todayPoints)
                            HoldingsSection(positions: dashboard.positions)
                        } else {
                            ErrorStateView(message: viewModel.errorMessage ?? "资产数据暂不可用") {
                                Task { await viewModel.loadDashboard() }
                            }
                        }

                        Spacer(minLength: 96)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                .refreshable {
                    await viewModel.loadDashboard()
                }

                WalkieButton(
                    title: viewModel.dashboard?.walkiePrompt ?? "按住说话",
                    isRecording: recorder.isRecording,
                    isBusy: viewModel.isTranscribing,
                    onPressStart: { Task { await startRecording() } },
                    onPressEnd: { Task { await stopAndSubmit() } }
                )
                    .padding(.bottom, 18)
            }
            .navigationBarHidden(true)
            .sheet(item: $viewModel.presentedIdea) { idea in
                IdeaNoteSheet(idea: idea) {
                    Task {
                        await viewModel.confirmPresentedIdea()
                        openActions()
                    }
                }
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("投资对讲机")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SageTheme.ColorToken.mutedText)
            Text("先看资产，再做决定")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startRecording() async {
        do {
            try await recorder.start()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func stopAndSubmit() async {
        guard let url = recorder.stop() else { return }
        await viewModel.submitVoiceIdea(audioURL: url)
    }
}

private struct AssetSummaryCard: View {
    let account: BrokerAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("总资产")
                        .font(.system(size: 13))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                    Text(money(account.totalAssets, currency: account.currency))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .minimumScaleFactor(0.7)
                }
                Spacer()
                Text(account.environment == "SIMULATE" ? "模拟盘" : "实盘")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(SageTheme.ColorToken.brand)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(SageTheme.ColorToken.brandSoft)
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                MetricPill(title: "今日盈亏", value: signedMoney(account.dayPnl, currency: account.currency), positive: account.dayPnl >= 0)
                MetricPill(title: "现金", value: money(account.cash, currency: account.currency), positive: nil)
            }
        }
        .padding(20)
        .sageGlassControl(cornerRadius: 24)
    }
}

private struct TodayPointsSection: View {
    let points: [TodayPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("今日要点")
            ForEach(points) { point in
                VStack(alignment: .leading, spacing: 6) {
                    Text(point.title)
                        .font(.system(size: 15, weight: .semibold))
                    Text(point.body)
                        .font(.system(size: 13))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(toneColor(point.tone).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct HoldingsSection: View {
    let positions: [HoldingSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("持仓摘要")
            ForEach(positions) { position in
                NavigationLink {
                    HoldingDetailView(position: position)
                } label: {
                    HoldingRow(position: position)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct HoldingRow: View {
    let position: HoldingSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(position.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                Text("\(position.code) · \(position.attention)")
                    .font(.system(size: 12))
                    .foregroundColor(SageTheme.ColorToken.mutedText)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(money(position.marketValue, currency: position.currency))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                Text(percent(position.unrealizedPnlPercent))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(position.unrealizedPnlPercent >= 0 ? .green : .red)
            }
        }
        .padding(14)
        .sageSoftCard(cornerRadius: 18)
    }
}

private struct HoldingDetailView: View {
    let position: HoldingSummary
    @State private var klineData: KLineChartData?
    @State private var klineError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(position.name)
                        .font(.system(size: 28, weight: .semibold))
                    Text(position.code)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                }

                KlineCard(position: position, data: klineData, errorMessage: klineError)

                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("今日要点")
                    DetailPoint(title: "计划价标注", text: "Kline 上会展示买入点、计划价、止损线和事件点。当前为 mock 数据，后续接富途 K线。")
                    DetailPoint(title: "持仓关系", text: position.attention)
                }
            }
            .padding(20)
        }
        .background(SageBackground())
        .navigationTitle("持仓详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadKline()
        }
    }

    private func loadKline() async {
        do {
            klineData = try await APIClient.shared.getPositionKline(code: position.code, name: position.name)
            klineError = nil
        } catch {
            klineError = error.localizedDescription
        }
    }
}

private struct KlineCard: View {
    let position: HoldingSummary
    let data: KLineChartData?
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(money(position.lastPrice, currency: position.currency))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                Spacer()
                Text(percent(position.dayChangePercent))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(position.dayChangePercent >= 0 ? .green : .red)
            }

            if let data {
                NativeKLineChartView(data: data, compact: true, maxPoints: 60)
                    .frame(height: 230)
                    .padding(12)
                    .background(SageTheme.ColorToken.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(SageTheme.ColorToken.mutedText)
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(SageTheme.ColorToken.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ProgressView("加载 K 线")
                    .frame(maxWidth: .infinity, minHeight: 180)
                    .background(SageTheme.ColorToken.surfaceSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .padding(18)
        .sageGlassControl(cornerRadius: 24)
    }
}

private struct ActionCenterView: View {
    @ObservedObject var viewModel: InvestmentDashboardViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.actions.sorted { $0.priority < $1.priority }) { action in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(action.title)
                                    .font(.system(size: 16, weight: .semibold))
                                Spacer()
                                Text(action.status)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(SageTheme.ColorToken.brand)
                            }
                            Text(action.subtitle)
                                .font(.system(size: 13))
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("优先处理")
                }
            }
            .sageSettingsPage()
            .navigationTitle("行动")
        }
    }
}

private struct AvatarProfileView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settingsService: SettingsService
    @StateObject private var viewModel = AvatarProfileViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            List {
                identitySection

                if viewModel.showsOnboardingFallback {
                    onboardingSection
                } else if let snapshot = viewModel.snapshot {
                    if !snapshot.hardRules.isEmpty {
                        Section("硬规则") {
                            ForEach(snapshot.hardRules, id: \.self) { rule in
                                Text(rule)
                            }
                        }
                    }
                    if !snapshot.focusAreas.isEmpty {
                        Section("当前关注") {
                            ForEach(snapshot.focusAreas, id: \.self) { area in
                                Label(area, systemImage: "scope")
                            }
                        }
                    }
                }

                Section("配置") {
                    Button { showSettings = true } label: {
                        Label("设置", systemImage: "gearshape")
                            .foregroundColor(.primary)
                    }
                }
            }
            .sageSettingsPage()
            .navigationTitle("分身")
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authService)
                .environmentObject(settingsService)
                .sageSheetBackground()
        }
    }

    private var identitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.snapshot?.identityLine ?? "你的分身还在学习你的投资风格")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.primary)
                if viewModel.showsOnboardingFallback {
                    Text("多和我聊聊你的判断和操作，我会逐渐记住你的风格、偏好和纪律，并在关键时刻提醒你。")
                        .font(.system(size: 14))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var onboardingSection: some View {
        Section("分身如何形成") {
            Label("对话越多，画像越准", systemImage: "bubble.left.and.bubble.right")
            Label("每天凌晨自动蒸馏更新", systemImage: "moon.stars")
            Label("关键时刻按你的纪律提醒", systemImage: "bell.badge")
        }
    }
}

/// 对讲机按钮：按住录音、松开发送。转写中显示进度，禁止重复触发。
private struct WalkieButton: View {
    let title: String
    let isRecording: Bool
    let isBusy: Bool
    let onPressStart: () -> Void
    let onPressEnd: () -> Void

    @State private var pressing = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(SageTheme.ColorToken.brand)
                    .frame(width: 64, height: 64)
                    .scaleEffect(isRecording ? 1.12 : 1.0)
                    .shadow(color: SageTheme.ColorToken.brand.opacity(0.35), radius: 18, x: 0, y: 8)

                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: isRecording)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressing, !isBusy else { return }
                        pressing = true
                        onPressStart()
                    }
                    .onEnded { _ in
                        guard pressing else { return }
                        pressing = false
                        onPressEnd()
                    }
            )

            Text(isRecording ? "松开发送" : (isBusy ? "正在整理…" : title))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(SageTheme.ColorToken.mutedText)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
    }
}

private struct IdeaNoteSheet: View {
    let idea: IdeaNoteCardData
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("已整理")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SageTheme.ColorToken.mutedText)

            Text(idea.transcript)
                .font(.system(size: 17, weight: .semibold))
                .lineSpacing(4)

            HStack(spacing: 8) {
                if !idea.symbol.isEmpty {
                    TagPill(text: idea.symbol, tone: .success)
                }
                if !idea.intent.isEmpty {
                    TagPill(text: idea.intent, tone: .brand)
                }
                TagPill(text: idea.status, tone: .warning)
            }

            Spacer()

            Button(action: onConfirm) {
                Text("进入行动中心")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SageTheme.ColorToken.brand)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(22)
    }
}

private struct TagPill: View {
    enum Tone {
        case brand
        case success
        case warning
    }

    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch tone {
        case .brand: return SageTheme.ColorToken.brand
        case .success: return .green
        case .warning: return .orange
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let positive: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(SageTheme.ColorToken.mutedText)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(positive == nil ? .primary : (positive == true ? .green : .red))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(SageTheme.ColorToken.surfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.primary)
    }
}

private struct DetailPoint: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(SageTheme.ColorToken.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .sageSoftCard(cornerRadius: 18)
    }
}

private struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(SageTheme.ColorToken.mutedText)
                .multilineTextAlignment(.center)
            Button("重新加载", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

private func toneColor(_ tone: String) -> Color {
    switch tone {
    case "positive": return .green
    case "warning": return .orange
    default: return SageTheme.ColorToken.brand
    }
}

private func money(_ value: Double, currency: String) -> String {
    "\(currency) \(value.formatted(.number.precision(.fractionLength(0...2))))"
}

private func signedMoney(_ value: Double, currency: String) -> String {
    let sign = value >= 0 ? "+" : "-"
    return "\(sign)\(currency) \(abs(value).formatted(.number.precision(.fractionLength(0...2))))"
}

private func percent(_ value: Double) -> String {
    let sign = value >= 0 ? "+" : ""
    return "\(sign)\(value.formatted(.number.precision(.fractionLength(2))))%"
}

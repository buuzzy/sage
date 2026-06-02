import SwiftUI

struct InvestmentWalkieView: View {
    @StateObject private var viewModel = InvestmentDashboardViewModel()
    @StateObject private var recorder = VoiceRecorder()
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var settingsService: SettingsService
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedPage = 0
    @State private var pendingOrderNoteId: String?
    @State private var showSettings = false
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedPage) {
                    AssetDashboardView(viewModel: viewModel, topInset: proxy.safeAreaInsets.top)
                        .tag(0)

                    ActionCenterView(
                        viewModel: viewModel,
                        pendingOrderNoteId: $pendingOrderNoteId,
                        topInset: proxy.safeAreaInsets.top
                    )
                    .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(.container, edges: [.top, .bottom])

                topChrome(topInset: proxy.safeAreaInsets.top)

                WalkieButton(
                    isRecording: recorder.isRecording,
                    isBusy: viewModel.isTranscribing,
                    onTap: { Task { await toggleRecording() } }
                )
                .padding(.bottom, 18)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .task {
            await viewModel.loadDashboard()
            startForegroundRefresh()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                startForegroundRefresh()
                Task { await viewModel.loadDashboard() }
            } else {
                stopForegroundRefresh()
            }
        }
        .onDisappear {
            stopForegroundRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToOrderNote)) { notification in
            guard let noteId = notification.userInfo?["noteId"] as? String else { return }
            selectedPage = 1
            pendingOrderNoteId = noteId
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authService)
                .environmentObject(settingsService)
                .sageSheetBackground()
        }
        .sheet(item: $viewModel.pendingVoicePreview) { preview in
            VoiceTranscriptPreviewSheet(
                preview: preview,
                isSubmitting: viewModel.isCreatingIdea,
                onCancel: {
                    viewModel.cancelVoiceIdea()
                },
                onConfirm: { transcript in
                    Task { await viewModel.confirmVoiceIdea(transcript: transcript) }
                }
            )
            .presentationDetents([.height(360)])
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(true)
        }
        .sheet(item: $viewModel.presentedIdea) { idea in
            IdeaNoteSheet(idea: idea) {
                viewModel.presentedIdea = nil
                selectedPage = 1
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }

    private func topChrome(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                topMask
                    .frame(height: topInset + 56)
                    .ignoresSafeArea(.container, edges: .top)

                HStack(alignment: .center) {
                    Button { showSettings = true } label: {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 42, height: 42)
                    }
                    .accessibilityLabel("打开设置")

                    Spacer()

                    AssetActionTopTabs(selectedPage: $selectedPage)

                    Spacer()

                    Color.clear.frame(width: 42, height: 42)
                }
                .padding(.horizontal, 20)
                .padding(.top, topInset + 2)
            }
            Spacer()
        }
    }

    private var topMask: some View {
        LinearGradient(
            colors: [
                topMaskColor.opacity(1.0),
                topMaskColor.opacity(0.92),
                topMaskColor.opacity(0.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var topMaskColor: Color {
        colorScheme == .dark ? .black : SageTheme.ColorToken.surface
    }

    private func toggleRecording() async {
        if recorder.isRecording {
            guard let url = recorder.stop() else { return }
            await viewModel.submitVoiceIdea(audioURL: url)
            return
        }

        do {
            try await recorder.start()
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func startForegroundRefresh() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                if Task.isCancelled { break }
                await viewModel.loadDashboard()
            }
        }
    }

    private func stopForegroundRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }
}

private struct AssetActionTopTabs: View {
    @Binding var selectedPage: Int

    var body: some View {
        HStack(spacing: 2) {
            tab("资产", index: 0)
            tab("行动", index: 1)
        }
        .padding(3)
        .background(Color(.secondarySystemBackground))
        .clipShape(Capsule())
    }

    private func tab(_ title: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                selectedPage = index
            }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selectedPage == index ? .primary : SageTheme.ColorToken.mutedText)
                .frame(width: 58, height: 30)
                .background(selectedPage == index ? Color(.systemBackground) : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct AssetDashboardView: View {
    @ObservedObject var viewModel: InvestmentDashboardViewModel
    let topInset: CGFloat

    var body: some View {
        NavigationStack {
            ZStack {
                SageBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if viewModel.isLoading && viewModel.dashboard == nil {
                            ProgressView("正在读取富途模拟盘")
                                .frame(maxWidth: .infinity, minHeight: 220)
                        } else if let dashboard = viewModel.dashboard {
                            AssetSummaryCard(account: dashboard.account, trend: dashboard.assetTrend)
                            AssetHomeSections(points: dashboard.todayPoints, positions: dashboard.positions)
                        } else {
                            ErrorStateView(message: viewModel.errorMessage ?? "资产数据暂不可用") {
                                Task { await viewModel.loadDashboard() }
                            }
                        }

                        Spacer(minLength: 96)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, topInset + 38)
                }
                .refreshable {
                    await viewModel.loadDashboard()
                }
            }
            .navigationBarHidden(true)
        }
    }
}

private struct AssetSummaryCard: View {
    let account: BrokerAccount
    let trend: [AssetTrendPoint]
    @State private var hidesAssets = false
    @State private var selectedCurrency: String?

    private var displayCurrency: String {
        selectedCurrency ?? account.currency
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(SageTheme.ColorToken.brand)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    )
                Text("保证金综合账户")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("总资产 ·")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                        Menu {
                            ForEach(["HKD", "USD", "CNY"], id: \.self) { currency in
                                Button(currency) { selectedCurrency = currency }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(displayCurrency)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                        }
                        Button { hidesAssets.toggle() } label: {
                            Image(systemName: hidesAssets ? "eye.slash" : "eye")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                    }

                    MaskableAmountText(
                        text: converted(account.totalAssets).formatted(.number.precision(.fractionLength(2))),
                        mask: "••••••",
                        isMasked: hidesAssets,
                        fontSize: 24,
                        width: 138,
                        alignment: .leading,
                        color: .primary
                    )
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("今日盈亏")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                    MaskableAmountText(
                        text: signedConvertedPlain(account.dayPnl),
                        mask: "••••",
                        isMasked: hidesAssets,
                        fontSize: 22,
                        width: 92,
                        alignment: .trailing,
                        color: account.dayPnl >= 0 ? .green : .red
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func converted(_ value: Double) -> Double {
        value * exchangeRate(from: account.currency, to: displayCurrency)
    }

    private func signedConvertedMoney(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(displayCurrency) \(abs(converted(value)).formatted(.number.precision(.fractionLength(0...2))))"
    }

    private func signedConvertedPlain(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(abs(converted(value)).formatted(.number.precision(.fractionLength(2))))"
    }

    private func exchangeRate(from: String, to: String) -> Double {
        guard from != to else { return 1 }
        let hkdPerUnit: [String: Double] = ["HKD": 1, "USD": 7.82, "CNY": 1.08]
        let fromRate = hkdPerUnit[from] ?? 1
        let toRate = hkdPerUnit[to] ?? 1
        return fromRate / toRate
    }
}

private struct MaskableAmountText: View {
    let text: String
    let mask: String
    let isMasked: Bool
    let fontSize: CGFloat
    let width: CGFloat
    let alignment: Alignment
    let color: Color

    var body: some View {
        ZStack(alignment: alignment) {
            Text(text)
                .opacity(isMasked ? 0 : 1)
            if isMasked {
                Text(mask)
            }
        }
        .font(.system(size: fontSize, weight: .medium, design: .rounded))
        .foregroundColor(color)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.70)
        .frame(width: width, alignment: alignment)
    }
}

private struct TodayPointsSection: View {
    let points: [TodayPoint]
    @State private var selectedPoint: TodayPoint?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("今日要点")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(points) { point in
                        Button {
                            selectedPoint = point
                        } label: {
                            TodayPointCard(point: point)
                                .frame(width: 292, height: 128)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
        .sheet(item: $selectedPoint) { point in
            TodayPointDetailSheet(point: point)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct TodayPointCard: View {
    let point: TodayPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(point.relatedName ?? point.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                    if let code = point.relatedCode {
                        Text(code)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                    }
                }
                Spacer()
                Circle()
                    .fill(toneColor(point.tone))
                    .frame(width: 8, height: 8)
            }

            Text(point.newsTitle ?? point.body)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .lineSpacing(3)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                if let source = point.newsSource, !source.isEmpty {
                    Text(source)
                } else {
                    Text("资讯")
                }
                if let date = point.newsDate, !date.isEmpty {
                    Text("· \(shortDate(date))")
                }
            }
            .font(.system(size: 11))
            .foregroundColor(SageTheme.ColorToken.mutedText)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(SageTheme.ColorToken.hairline, lineWidth: 1)
        )
    }

    private func shortDate(_ raw: String) -> String {
        String(raw.prefix(10))
    }
}

private struct TodayPointDetailSheet: View {
    let point: TodayPoint
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(point.relatedName ?? point.title)
                        .font(.system(size: 20, weight: .semibold))
                    if let code = point.relatedCode {
                        Text(code)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .frame(width: 30, height: 30)
                }
            }

            Text(point.newsTitle ?? point.body)
                .font(.system(size: 17, weight: .semibold))
                .lineSpacing(4)

            if let summary = point.newsSummary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundColor(SageTheme.ColorToken.mutedText)
                    .lineSpacing(4)
            } else {
                Text(point.body)
                    .font(.system(size: 14))
                    .foregroundColor(SageTheme.ColorToken.mutedText)
                    .lineSpacing(4)
            }

            HStack(spacing: 8) {
                Text(point.newsSource?.isEmpty == false ? point.newsSource! : "资讯")
                if let date = point.newsDate, !date.isEmpty {
                    Text("· \(String(date.prefix(16)))")
                }
            }
            .font(.system(size: 12))
            .foregroundColor(SageTheme.ColorToken.mutedText)

            Spacer()
        }
        .padding(22)
        .background(SageTheme.ColorToken.surface)
    }
}

private struct HoldingsSection: View {
    let positions: [HoldingSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

private struct AssetHomeSections: View {
    let points: [TodayPoint]
    let positions: [HoldingSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            TodayPointsSection(points: points)
            HoldingsSection(positions: positions)
        }
    }
}

private struct MiniAssetSparkline: View {
    let points: [AssetTrendPoint]
    let positive: Bool

    private var values: [Double] {
        points.map(\.value)
    }

    var body: some View {
        GeometryReader { proxy in
            let normalized = normalizedValues
            let linePoints = normalized.enumerated().map { index, value in
                CGPoint(
                    x: CGFloat(index) / CGFloat(max(normalized.count - 1, 1)) * proxy.size.width,
                    y: (1 - value) * proxy.size.height
                )
            }
            let color = positive ? Color.green : Color(red: 0.93, green: 0.22, blue: 0.42)

            ZStack {
                SparklineFill(points: linePoints, size: proxy.size)
                    .fill(color.opacity(0.12))
                SparklineLine(points: linePoints)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .shadow(color: color.opacity(0.28), radius: 8)
            }
        }
    }

    private var normalizedValues: [CGFloat] {
        let raw = values.isEmpty ? [0, 1] : values
        guard let min = raw.min(), let max = raw.max(), max > min else {
            return raw.map { _ in 0.55 }
        }
        return raw.map { value in
            0.16 + CGFloat((value - min) / (max - min)) * 0.68
        }
    }
}

private struct SparklineLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}

private struct SparklineFill: Shape {
    let points: [CGPoint]
    let size: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first, let last = points.last else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        path.addLine(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }
}

private struct HoldingRow: View {
    let position: HoldingSummary

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(position.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(position.market)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SageTheme.ColorToken.mutedText.opacity(0.75))
                    Text(position.code.replacingOccurrences(of: "\(position.market).", with: ""))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                    Text(money(position.marketValue, currency: position.currency))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                Text(position.lastPrice.formatted(.number.precision(.fractionLength(2...3))))
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(percent(position.dayChangePercent))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
                    .frame(width: 78, height: 30)
                    .background(changeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(.vertical, 12)
    }

    private var changeColor: Color {
        if position.dayChangePercent > 0 { return .green }
        if position.dayChangePercent < 0 { return Color(red: 0.91, green: 0.24, blue: 0.39) }
        return Color.gray.opacity(0.55)
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
                    ForEach(Array(position.detailPoints.enumerated()), id: \.offset) { _, point in
                        DetailPoint(title: point.title, text: point.body)
                    }
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

/// 行动卡点击后进入的流程目的地。用 fullScreenCover 模态呈现，避免切 Tab 时
/// 导航栈残留上一张卡（旧实现用 NavigationLink push，切回行动 Tab 会停在旧流程页）。
private enum ActionRoute: Identifiable {
    case order(String)
    case analysis(String)
    case watch(String)
    case noteDetail(String)
    case summary(String)

    var id: String {
        switch self {
        case .order(let id): return "order-\(id)"
        case .analysis(let id): return "analysis-\(id)"
        case .watch(let id): return "watch-\(id)"
        case .noteDetail(let id): return "note-\(id)"
        case .summary(let id): return "summary-\(id)"
        }
    }
}

private struct ActionGroup: Identifiable {
    let key: String
    let title: String
    let order: Int
    var actions: [InvestmentActionItem]

    var id: String { key }
}

private struct ActionCenterView: View {
    @ObservedObject var viewModel: InvestmentDashboardViewModel
    @Binding var pendingOrderNoteId: String?
    let topInset: CGFloat
    @State private var route: ActionRoute?
    @State private var collapsedGroups: Set<String> = ["completed"]
    @State private var flashingActionId: String?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(actionGroups) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                        toggleGroup(group.key)
                                    }
                                } label: {
                                    HStack {
                                        Text(group.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.primary)
                                        Text("\(group.actions.count)")
                                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                                            .foregroundColor(SageTheme.ColorToken.mutedText)
                                        Spacer()
                                        Image(systemName: collapsedGroups.contains(group.key) ? "chevron.down" : "chevron.up")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(SageTheme.ColorToken.mutedText)
                                    }
                                }
                                .buttonStyle(.plain)

                                if !collapsedGroups.contains(group.key) {
                                    ForEach(group.actions) { action in
                                        let target = route(for: action)
                                        if let target {
                                            Button { route = target } label: {
                                                ActionRow(
                                                    action: action,
                                                    actionable: true,
                                                    isHighlighted: flashingActionId == action.id
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            ActionRow(
                                                action: action,
                                                actionable: false,
                                                isHighlighted: flashingActionId == action.id
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, topInset + 38)
                    .padding(.bottom, 110)
                }
                .background(SageBackground().ignoresSafeArea())
                .navigationBarHidden(true)
                .onAppear {
                    consumePendingOrderNote()
                    focusGeneratedAction(with: proxy)
                }
                .onChange(of: pendingOrderNoteId) { _ in consumePendingOrderNote() }
                .onChange(of: viewModel.focusedActionId) { _ in focusGeneratedAction(with: proxy) }
                .onChange(of: viewModel.actions.count) { _ in focusGeneratedAction(with: proxy) }
            }
        }
        .fullScreenCover(item: $route, onDismiss: { Task { await viewModel.reloadActions() } }) { route in
            NavigationStack {
                destination(for: route)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("关闭") { self.route = nil }
                        }
                    }
            }
        }
    }

    private func toggleGroup(_ key: String) {
        if collapsedGroups.contains(key) {
            collapsedGroups.remove(key)
        } else {
            collapsedGroups.insert(key)
        }
    }

    private func focusGeneratedAction(with proxy: ScrollViewProxy) {
        guard let actionId = viewModel.focusedActionId,
              let action = viewModel.actions.first(where: { $0.id == actionId })
        else { return }

        if let groupKey = action.groupKey {
            collapsedGroups.remove(groupKey)
        }

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                proxy.scrollTo(actionId, anchor: .top)
            }
            flashingActionId = actionId
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if flashingActionId == actionId {
                    withAnimation(.easeOut(duration: 0.25)) {
                        flashingActionId = nil
                    }
                }
                if viewModel.focusedActionId == actionId {
                    viewModel.focusedActionId = nil
                }
            }
        }
    }
    /// 分组顺序信任后端输出的 groupOrder；同组内保持 API 返回顺序，不做二次排序。
    private var actionGroups: [ActionGroup] {
        var groups: [String: ActionGroup] = [:]
        var order: [String] = []
        for action in viewModel.actions {
            let key = action.groupKey ?? "pending"
            if groups[key] == nil {
                order.append(key)
                groups[key] = ActionGroup(
                    key: key,
                    title: action.groupTitle ?? fallbackGroupTitle(for: key),
                    order: action.groupOrder ?? fallbackGroupOrder(for: key),
                    actions: []
                )
            }
            var group = groups[key]!
            group.actions.append(action)
            groups[key] = group
        }
        return order
            .compactMap { groups[$0] }
            .sorted { left, right in
                if left.order != right.order { return left.order < right.order }
                return left.key < right.key
            }
    }

    /// 按 kind + 状态决定可点入的流程；已完成/进行中卡片也应可查看（只读详情或继续下单）。
    private func route(for action: InvestmentActionItem) -> ActionRoute? {
        switch action.kind {
        case "system":
            return nil
        case "analysis_task":
            guard let noteId = action.noteId else { return nil }
            return .analysis(noteId)
        case "price_watch":
            guard let noteId = action.noteId else { return nil }
            return .watch(noteId)
        case "idea_confirmation":
            guard let noteId = action.noteId else { return nil }
            if canContinueOrderFlow(action) { return .order(noteId) }
            return .noteDetail(noteId)
        case "order_confirmation":
            if let noteId = action.noteId { return .noteDetail(noteId) }
            return .summary(action.id)
        case "review":
            return .summary(action.id)
        default:
            if let noteId = action.noteId { return .noteDetail(noteId) }
            return .summary(action.id)
        }
    }

    private func canContinueOrderFlow(_ action: InvestmentActionItem) -> Bool {
        if action.statusCode == "awaiting_confirmation" || action.statusCode == "active" {
            return true
        }
        return action.status == "待确认" || action.status == "已确认" || action.status == "进行中"
    }

    private func fallbackGroupTitle(for key: String) -> String {
        switch key {
        case "exception": return "异常"
        case "confirmation": return "等你确认"
        case "active": return "进行中"
        case "completed": return "已完成"
        default: return "待处理"
        }
    }

    private func fallbackGroupOrder(for key: String) -> Int {
        switch key {
        case "exception": return 0
        case "confirmation": return 2
        case "active": return 3
        case "completed": return 9
        default: return 1
        }
    }

    @ViewBuilder
    private func destination(for route: ActionRoute) -> some View {
        switch route {
        case .order(let noteId):
            OrderConfirmationFlowView(noteId: noteId) { Task { await viewModel.reloadActions() } }
        case .analysis(let noteId):
            AnalysisDetailView(noteId: noteId)
        case .watch(let noteId):
            WatchDetailView(noteId: noteId)
        case .noteDetail(let noteId):
            ActionNoteDetailView(noteId: noteId)
        case .summary(let actionId):
            if let action = viewModel.actions.first(where: { $0.id == actionId }) {
                ActionSummaryView(action: action)
            } else {
                Text("卡片不存在或已刷新")
                    .foregroundColor(SageTheme.ColorToken.mutedText)
            }
        }
    }

    private func consumePendingOrderNote() {
        guard let noteId = pendingOrderNoteId else { return }
        pendingOrderNoteId = nil
        route = .order(noteId)
    }
}

private struct ActionRow: View {
    let action: InvestmentActionItem
    let actionable: Bool
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(statusColor)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(action.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Text(action.status)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.10))
                        .clipShape(Capsule())
                }

                Text(action.subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(SageTheme.ColorToken.mutedText)
                    .lineLimit(2)
                    .lineSpacing(2)

                HStack {
                    if let timeLabel = ActionTimeFormat.label(for: action.createdAt) {
                        Text(timeLabel)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                    }
                    Spacer()
                    if actionable {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isHighlighted ? SageTheme.ColorToken.brand.opacity(0.10) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isHighlighted ? SageTheme.ColorToken.brand.opacity(0.45) : SageTheme.ColorToken.hairline, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.25), value: isHighlighted)
        .id(action.id)
    }

    private var statusColor: Color {
        switch action.groupKey {
        case "exception": return .red
        case "confirmation": return SageTheme.ColorToken.brand
        case "active": return .orange
        case "completed": return .green
        default: return .primary
        }
    }

    private var iconName: String {
        switch action.kind {
        case "analysis_task": return "chart.line.uptrend.xyaxis"
        case "price_watch": return "bell.badge"
        case "idea_confirmation": return "mic.badge.plus"
        case "order_confirmation": return "checkmark.seal"
        default: return "sparkles"
        }
    }
}

struct AvatarProfileView: View {
    var showsConfiguration = true
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var settingsService: SettingsService
    @StateObject private var viewModel = AvatarProfileViewModel()
    @State private var showSettings = false
    @AppStorage("sage_theme") private var theme: String = "system"

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

                if showsConfiguration {
                    Section("配置") {
                        // 外观：单击循环切换 跟随系统 → 浅色 → 深色（隐藏复杂项，符合极简）。
                        Button { cycleTheme() } label: {
                            HStack {
                                Label("外观", systemImage: themeIcon)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(themeLabel)
                                    .font(.system(size: 14))
                                    .foregroundColor(SageTheme.ColorToken.mutedText)
                            }
                        }

                        Button { showSettings = true } label: {
                            Label("设置", systemImage: "gearshape")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .sageSettingsPage()
            .navigationTitle("分身")
            .toolbar {
                if showsConfiguration {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { cycleTheme() } label: {
                            Image(systemName: themeIcon)
                                .foregroundColor(SageTheme.ColorToken.brand)
                        }
                        .accessibilityLabel("切换外观（当前\(themeLabel)）")
                    }
                }
            }
        }
        .task { await viewModel.load() }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(authService)
                .environmentObject(settingsService)
                .sageSheetBackground()
        }
    }

    private var themeLabel: String {
        switch theme {
        case "light": return "浅色"
        case "dark": return "深色"
        default: return "跟随系统"
        }
    }

    private var themeIcon: String {
        switch theme {
        case "light": return "sun.max"
        case "dark": return "moon.stars"
        default: return "circle.lefthalf.filled"
        }
    }

    /// 循环：跟随系统 → 浅色 → 深色 → 跟随系统。SageApp 监听 @AppStorage 即时应用到 UIKit 层。
    private func cycleTheme() {
        switch theme {
        case "system": theme = "light"
        case "light": theme = "dark"
        default: theme = "system"
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

/// 对讲机按钮：点击开始录音，再次点击结束。转写中显示进度，禁止重复触发。
private struct WalkieButton: View {
    let isRecording: Bool
    let isBusy: Bool
    let onTap: () -> Void

    var body: some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.red : SageTheme.ColorToken.brand)
                .frame(width: 64, height: 64)
                .scaleEffect(isRecording ? 1.10 : 1.0)
                .shadow(color: (isRecording ? Color.red : SageTheme.ColorToken.brand).opacity(0.34), radius: 18, x: 0, y: 8)

            if isBusy {
                ProgressView()
                    .tint(.white)
            } else {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isRecording)
        .onTapGesture {
            guard !isBusy else { return }
            onTap()
        }
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
                if let condition = idea.condition {
                    TagPill(text: condition.text, tone: .warning)
                }
                TagPill(text: idea.status, tone: .warning)
            }

            Text(taskHint)
                .font(.system(size: 13))
                .foregroundColor(SageTheme.ColorToken.mutedText)
                .lineSpacing(3)

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

    /// 按任务类型给出「Sage 接下来会做什么」的一句话提示。
    private var taskHint: String {
        switch idea.taskType {
        case "analysis": return "Sage 会结合你的持仓给出判断，去行动中心查看分析。"
        case "conditional": return "已为你设好价格监控，触发时会提醒你确认下单。"
        default: return "已整理为想法，去行动中心确认是否下单。"
        }
    }
}

private struct VoiceTranscriptPreviewSheet: View {
    let preview: VoiceTranscriptPreview
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onConfirm: (String) -> Void
    @State private var draft: String
    @FocusState private var isEditorFocused: Bool

    init(
        preview: VoiceTranscriptPreview,
        isSubmitting: Bool,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping (String) -> Void
    ) {
        self.preview = preview
        self.isSubmitting = isSubmitting
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _draft = State(initialValue: preview.transcript)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("确认这条语音想法")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SageTheme.ColorToken.mutedText)

            TextEditor(text: $draft)
                .font(.system(size: 17, weight: .medium))
                .lineSpacing(4)
                .frame(minHeight: 120)
                .padding(10)
                .background(SageTheme.ColorToken.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($isEditorFocused)

            Text("确认后才会生成行动卡；取消会直接丢弃，不会写入记录。")
                .font(.system(size: 12))
                .foregroundColor(SageTheme.ColorToken.mutedText)

            Spacer()

            Button {
                onConfirm(draft)
            } label: {
                ZStack {
                    if isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("确认提交")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(SageTheme.ColorToken.brand)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("取消，不保存") {
                onCancel()
            }
            .font(.system(size: 14))
            .foregroundColor(SageTheme.ColorToken.mutedText)
            .frame(maxWidth: .infinity)
            .disabled(isSubmitting)
        }
        .padding(22)
        .contentShape(Rectangle())
        .onTapGesture {
            isEditorFocused = false
            UIApplication.shared.dismissKeyboard()
        }
    }
}

private extension UIApplication {
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        .background(Color(.systemBackground))
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
            .font(.system(size: 21, weight: .bold))
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

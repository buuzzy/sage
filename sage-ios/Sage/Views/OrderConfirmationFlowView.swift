import SwiftUI

/// 两步确认流程 ViewModel：加载草稿 → 确认投资逻辑 → 调整并提交模拟盘订单。
@MainActor
final class OrderFlowViewModel: ObservableObject {
    enum Step {
        case logic
        case order
        case done
    }

    let noteId: String

    @Published var step: Step = .logic
    @Published var isLoading = false
    @Published var isWorking = false
    @Published var errorMessage: String?

    @Published var note: IdeaNoteCardData?
    @Published var draft: OrderDraft?
    @Published var orderAnalysis: OrderAnalysis?
    @Published var analysisProgress: [OrderAnalysisProgress] = []
    @Published var isAnalyzing = false

    @Published var side = "BUY"
    @Published var orderType = "NORMAL"
    @Published var priceText = ""
    @Published var quantity = 0

    @Published var submittedOrder: MobileOrder?

    init(noteId: String) {
        self.noteId = noteId
    }

    var lotSize: Int { max(1, draft?.lotSize ?? 1) }
    var currency: String { draft?.currency ?? "" }
    var isMarketOrder: Bool { orderType == "MARKET" }

    var estimatedAmount: Double {
        let price = Double(priceText) ?? draft?.price ?? 0
        return price * Double(quantity)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        orderAnalysis = nil
        analysisProgress = []
        do {
            let response = try await APIClient.shared.getOrderDraft(noteId: noteId)
            note = response.note
            draft = response.draft
            side = response.draft.side
            orderType = response.draft.orderType
            priceText = Self.formatPrice(response.draft.price)
            quantity = response.draft.quantity
            isLoading = false
            await loadOrderAnalysis()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func loadOrderAnalysis() async {
        isAnalyzing = true
        defer { isAnalyzing = false }
        do {
            let stream = await APIClient.shared.streamOrderAnalysis(noteId: noteId)
            for try await event in stream {
                switch event.type {
                case "progress":
                    guard let step = event.step, let message = event.message else { continue }
                    upsertProgress(OrderAnalysisProgress(step: step, message: message, status: event.status))
                case "result":
                    orderAnalysis = event.analysis
                case "error":
                    errorMessage = event.message ?? "标的分析失败"
                default:
                    continue
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upsertProgress(_ progress: OrderAnalysisProgress) {
        if let index = analysisProgress.firstIndex(where: { $0.step == progress.step }) {
            analysisProgress[index] = progress
        } else {
            analysisProgress.append(progress)
        }
    }

    func confirmLogic() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await APIClient.shared.confirmIdeaNote(noteId: noteId)
            step = .order
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func incrementQuantity() { quantity += lotSize }

    func decrementQuantity() { quantity = max(lotSize, quantity - lotSize) }

    func submit() async {
        guard let draft else { return }
        let price = Double(priceText) ?? 0
        guard isMarketOrder || price > 0 else {
            errorMessage = "请输入有效价格"
            return
        }
        guard quantity > 0 else {
            errorMessage = "数量必须大于 0"
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            let request = SubmitOrderRequest(
                noteId: noteId,
                accountId: draft.accountId,
                code: draft.code,
                name: draft.name,
                side: side,
                orderType: orderType,
                price: isMarketOrder ? draft.price : price,
                quantity: quantity
            )
            let response = try await APIClient.shared.submitOrder(request)
            submittedOrder = response.order
            step = .done
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func formatPrice(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

}

/// 两步确认流程视图：从「行动」Tab 的待确认想法卡进入。
struct OrderConfirmationFlowView: View {
    @StateObject private var viewModel: OrderFlowViewModel
    @Environment(\.dismiss) private var dismiss
    let onFinished: () -> Void

    init(noteId: String, onFinished: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: OrderFlowViewModel(noteId: noteId))
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isLoading {
                    ProgressView("正在生成订单草稿")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    switch viewModel.step {
                    case .logic: logicStep
                    case .order: orderStep
                    case .done: doneStep
                    }
                }
            }
            .padding(20)
        }
        .background(SageBackground().ignoresSafeArea())
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .alert(
            "操作失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var navigationTitle: String {
        switch viewModel.step {
        case .logic: return "确认投资逻辑"
        case .order: return "确认订单参数"
        case .done: return "已提交模拟盘"
        }
    }

    // MARK: Step 1 — 投资逻辑

    private var logicStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepBadge(index: 1, total: 2, text: "先确认这个判断是否成立")

            if let note = viewModel.note {
                VStack(alignment: .leading, spacing: 14) {
                    Text(note.transcript)
                        .font(.system(size: 18, weight: .semibold))
                        .lineSpacing(4)
                    HStack(spacing: 8) {
                        if !note.symbol.isEmpty { FlowTag(text: note.symbol, tone: .brand) }
                        if !note.intent.isEmpty { FlowTag(text: note.intent, tone: .brand) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .sageGlassControl(cornerRadius: 22)
            }

            targetAnalysisSection

            if let draft = viewModel.draft {
                VStack(alignment: .leading, spacing: 8) {
                    Text("订单准备")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                    Text("\(draft.name) · \(sideText(draft.side)) · 约 \(draft.quantity) 股 @ \(OrderFlowViewModel.formatPrice(draft.price)) \(draft.currency)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .sageGlassControl(cornerRadius: 22)
            }

            PrimaryButton(title: "确认这个判断", isLoading: viewModel.isWorking || viewModel.isAnalyzing) {
                Task { await viewModel.confirmLogic() }
            }
            Button("再想想") { dismiss() }
                .font(.system(size: 14))
                .foregroundColor(SageTheme.ColorToken.mutedText)
                .frame(maxWidth: .infinity)
        }
    }

    private var targetAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("标的分析")
                .font(.system(size: 13))
                .foregroundColor(SageTheme.ColorToken.mutedText)

            if let analysis = viewModel.orderAnalysis {
                VStack(alignment: .leading, spacing: 12) {
                    Text(analysis.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Text(analysis.summary)
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineSpacing(4)

                    if !analysis.bullets.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(analysis.bullets, id: \.self) { item in
                                Label(item, systemImage: "checkmark.circle")
                                    .font(.system(size: 13))
                                    .foregroundColor(.primary)
                            }
                        }
                    }

                    if !analysis.risks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("风险")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            ForEach(analysis.risks, id: \.self) { item in
                                Text("• \(item)")
                                    .font(.system(size: 13))
                                    .foregroundColor(SageTheme.ColorToken.mutedText)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if !analysis.sources.isEmpty {
                            Text("数据来源：\(analysis.sources.joined(separator: " / "))")
                                .font(.system(size: 11))
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                        }
                        Text("分析时间：\(analysisTimeLabel(analysis.generatedAt))")
                            .font(.system(size: 11))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .sageGlassControl(cornerRadius: 22)
            } else {
                AnalysisProgressCard(progress: viewModel.analysisProgress)
            }
        }
    }

    private func analysisTimeLabel(_ iso: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = fractional.date(from: iso) ?? plain.date(from: iso) else {
            return iso
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: Step 2 — 订单参数

    private var orderStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepBadge(index: 2, total: 2, text: "核对并调整订单参数")

            if let draft = viewModel.draft {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.name)
                                .font(.system(size: 18, weight: .semibold))
                            Text(draft.code)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                        }
                        Spacer()
                        Text("模拟盘")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(SageTheme.ColorToken.brand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(SageTheme.ColorToken.brandSoft)
                            .clipShape(Capsule())
                    }

                    Picker("方向", selection: $viewModel.side) {
                        Text("买入").tag("BUY")
                        Text("卖出").tag("SELL")
                    }
                    .pickerStyle(.segmented)

                    Picker("类型", selection: $viewModel.orderType) {
                        Text("限价").tag("NORMAL")
                        Text("市价").tag("MARKET")
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("价格")
                            .font(.system(size: 14))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                        Spacer()
                        if viewModel.isMarketOrder {
                            Text("市价")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                        } else {
                            TextField("价格", text: $viewModel.priceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .frame(width: 120)
                        }
                    }

                    Divider()

                    HStack {
                        Text("数量")
                            .font(.system(size: 14))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { viewModel.quantity },
                                set: { viewModel.quantity = max(viewModel.lotSize, $0) }
                            ),
                            step: viewModel.lotSize
                        ) {
                            Text("\(viewModel.quantity) 股")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                        }
                        .fixedSize()
                    }

                    HStack {
                        Text("预计金额")
                            .font(.system(size: 14))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                        Spacer()
                        Text("\(draft.currency) \(amountText(viewModel.estimatedAmount))")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                    }

                    Text(draft.rationale)
                        .font(.system(size: 12))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .lineSpacing(2)
                }
                .padding(18)
                .sageGlassControl(cornerRadius: 22)
            }

            PrimaryButton(title: "提交到模拟盘", isLoading: viewModel.isWorking) {
                Task { await viewModel.submit() }
            }
            Button("返回上一步") { viewModel.step = .logic }
                .font(.system(size: 14))
                .foregroundColor(SageTheme.ColorToken.mutedText)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Step 3 — 回执

    private var doneStep: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
                .padding(.top, 24)

            Text("已提交到富途模拟盘")
                .font(.system(size: 20, weight: .semibold))

            if let order = viewModel.submittedOrder {
                VStack(alignment: .leading, spacing: 10) {
                    DetailRow(label: "标的", value: order.code)
                    DetailRow(label: "方向", value: sideText(order.side))
                    DetailRow(label: "数量", value: "\(order.quantity) 股")
                    DetailRow(label: "成交价", value: OrderFlowViewModel.formatPrice(order.dealtAvgPrice ?? order.price))
                    DetailRow(label: "状态", value: statusText(order.status))
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .sageGlassControl(cornerRadius: 22)
            }

            PrimaryButton(title: "完成", isLoading: false) {
                onFinished()
                dismiss()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sideText(_ side: String) -> String { side == "SELL" ? "卖出" : "买入" }

    private func statusText(_ status: String) -> String {
        switch status {
        case "FILLED": return "已成交"
        case "REJECTED": return "已拒绝"
        default: return "已提交"
        }
    }

    private func amountText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

// MARK: - 分析任务详情（analysis_task）

/// 分析类想法详情：惰性生成 Sage 结合持仓的结构化判断；建议下单时可一键进入两步确认。
struct AnalysisDetailView: View {
    let noteId: String

    @State private var note: IdeaNoteCardData?
    @State private var analysis: IdeaAnalysisData?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading {
                    ProgressView("Sage 正在结合你的持仓分析…")
                        .frame(maxWidth: .infinity, minHeight: 260)
                } else if let analysis {
                    if let note {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(note.transcript)
                                .font(.system(size: 17, weight: .semibold))
                                .lineSpacing(4)
                            HStack(spacing: 8) {
                                if !note.symbol.isEmpty { FlowTag(text: note.symbol, tone: .green) }
                                if !note.intent.isEmpty { FlowTag(text: note.intent, tone: .brand) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .sageGlassControl(cornerRadius: 22)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Sage 的判断")
                            .font(.system(size: 13))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                        Text(analysis.conclusion)
                            .font(.system(size: 18, weight: .semibold))
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(SageTheme.ColorToken.brandSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    if !analysis.points.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(analysis.points.enumerated()), id: \.offset) { _, point in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "circle.fill")
                                        .font(.system(size: 6))
                                        .foregroundColor(SageTheme.ColorToken.brand)
                                        .padding(.top, 7)
                                    Text(point)
                                        .font(.system(size: 14))
                                        .foregroundColor(.primary)
                                        .lineSpacing(3)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .sageSoftCard(cornerRadius: 18)
                    }

                    orderLink(prominent: analysis.suggestOrder)
                } else {
                    VStack(spacing: 12) {
                        Text(errorMessage ?? "分析暂不可用")
                            .font(.system(size: 14))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                            .multilineTextAlignment(.center)
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(20)
        }
        .background(SageBackground().ignoresSafeArea())
        .navigationTitle("Sage 分析")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func orderLink(prominent: Bool) -> some View {
        NavigationLink {
            OrderConfirmationFlowView(noteId: noteId) {}
        } label: {
            Text(prominent ? "据此生成订单草稿" : "仍要据此下单")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(prominent ? .white : SageTheme.ColorToken.brand)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(prominent ? AnyShapeStyle(SageTheme.ColorToken.brand) : AnyShapeStyle(SageTheme.ColorToken.brandSoft))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.analyzeNote(noteId: noteId)
            note = response.note
            analysis = response.analysis
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 条件监控详情（price_watch）

/// 条件单详情：展示「现价 vs 目标价」与监控状态；触发后进入两步确认。
struct WatchDetailView: View {
    let noteId: String

    @State private var note: IdeaNoteCardData?
    @State private var quote: Double?
    @State private var isLoading = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var goToOrder = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading {
                    ProgressView("加载监控…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let note {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(note.transcript)
                            .font(.system(size: 17, weight: .semibold))
                            .lineSpacing(4)
                        HStack(spacing: 8) {
                            if !note.symbol.isEmpty { FlowTag(text: note.symbol, tone: .green) }
                            if !note.intent.isEmpty { FlowTag(text: note.intent, tone: .brand) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .sageGlassControl(cornerRadius: 22)

                    VStack(spacing: 14) {
                        if let condition = note.condition {
                            DetailRow(label: "触发条件", value: "\(note.symbol) \(condition.text)")
                        }
                        if let quote {
                            DetailRow(label: "当前价", value: formatPrice(quote))
                        }
                        DetailRow(label: "状态", value: isTriggered ? "已触发" : "监控中")
                    }
                    .padding(18)
                    .sageSoftCard(cornerRadius: 18)

                    if isTriggered {
                        PrimaryButton(title: "去确认下单", isLoading: false) { goToOrder = true }
                    } else {
                        PrimaryButton(title: "模拟触发（演示）", isLoading: isWorking) {
                            Task { await trigger() }
                        }
                        Text("达到目标价时 Sage 会自动提醒你；这里可手动模拟触发以演示后续流程。")
                            .font(.system(size: 12))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 12) {
                        Text(errorMessage ?? "监控暂不可用")
                            .font(.system(size: 14))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(20)
        }
        .background(SageBackground().ignoresSafeArea())
        .navigationTitle("价格监控")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToOrder) {
            OrderConfirmationFlowView(noteId: noteId) {}
        }
        .task { await load() }
    }

    private var isTriggered: Bool { note?.watchStatus == "triggered" }

    private func formatPrice(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.getNoteDetail(noteId: noteId)
            note = response.note
            quote = response.quote
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func trigger() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await APIClient.shared.triggerWatch(noteId: noteId)
            note = response.note
            NotificationService.shared.sendPriceWatchTriggeredNotification(
                noteId: noteId,
                symbol: response.note.symbol,
                conditionText: response.note.condition?.text,
                intent: response.note.intent
            )
            goToOrder = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 复用小组件

private struct StepBadge: View {
    let index: Int
    let total: Int
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("第 \(index) / \(total) 步")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(SageTheme.ColorToken.brand)
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(SageTheme.ColorToken.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AnalysisProgressCard: View {
    let progress: [OrderAnalysisProgress]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在生成标的分析")
                    .font(.system(size: 15, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(visibleProgress) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: icon(for: item.status))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(color(for: item.status))
                            .frame(width: 16)
                        Text(item.message)
                            .font(.system(size: 13))
                            .foregroundColor(SageTheme.ColorToken.mutedText)
                            .lineSpacing(2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .sageGlassControl(cornerRadius: 22)
    }

    private var visibleProgress: [OrderAnalysisProgress] {
        if progress.isEmpty {
            return [OrderAnalysisProgress(step: "starting", message: "正在准备分析上下文", status: "running")]
        }
        return progress
    }

    private func icon(for status: String?) -> String {
        switch status {
        case "done": return "checkmark.circle.fill"
        case "skipped": return "minus.circle.fill"
        default: return "circle.dotted"
        }
    }

    private func color(for status: String?) -> Color {
        switch status {
        case "done": return .green
        case "skipped": return SageTheme.ColorToken.mutedText
        default: return SageTheme.ColorToken.brand
        }
    }
}

private struct PrimaryButton: View {
    let title: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(SageTheme.ColorToken.brand)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct FlowTag: View {
    enum Tone { case brand, green }
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
        SageTheme.ColorToken.brand
    }
}

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(SageTheme.ColorToken.mutedText)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
        }
    }
}

// MARK: - 行动卡只读详情（已完成 / 成交回执 / 定时结果）

/// 关联了想法卡的行动条目：加载 note 展示原话、状态与已缓存分析/条件。
struct ActionNoteDetailView: View {
    let noteId: String

    @State private var note: IdeaNoteCardData?
    @State private var quote: Double?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isLoading {
                    ProgressView("加载详情…")
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else if let note {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(note.transcript)
                            .font(.system(size: 17, weight: .semibold))
                            .lineSpacing(4)
                        HStack(spacing: 8) {
                            if !note.symbol.isEmpty { FlowTag(text: note.symbol, tone: .green) }
                            if !note.intent.isEmpty { FlowTag(text: note.intent, tone: .brand) }
                            FlowTag(text: note.status, tone: .brand)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .sageGlassControl(cornerRadius: 22)

                    if let analysis = note.analysis {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Sage 的判断")
                                .font(.system(size: 13))
                                .foregroundColor(SageTheme.ColorToken.mutedText)
                            Text(analysis.conclusion)
                                .font(.system(size: 16, weight: .semibold))
                                .lineSpacing(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                        .sageSoftCard(cornerRadius: 18)
                    }

                    if note.taskType == "conditional", let condition = note.condition {
                        VStack(spacing: 10) {
                            DetailRow(label: "触发条件", value: "\(note.symbol) \(condition.text)")
                            if let quote {
                                DetailRow(label: "参考现价", value: formatPrice(quote))
                            }
                            if let watchStatus = note.watchStatus {
                                DetailRow(label: "监控状态", value: watchStatus == "triggered" ? "已触发" : "监控中")
                            }
                        }
                        .padding(18)
                        .sageSoftCard(cornerRadius: 18)
                    }
                } else {
                    Text(errorMessage ?? "详情暂不可用")
                        .font(.system(size: 14))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding(20)
        }
        .background(SageBackground().ignoresSafeArea())
        .navigationTitle("行动详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func formatPrice(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.getNoteDetail(noteId: noteId)
            note = response.note
            quote = response.quote
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 无想法卡关联的条目（如定时任务结果）：展示标题与摘要。
struct ActionSummaryView: View {
    let action: InvestmentActionItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(action.title)
                        .font(.system(size: 20, weight: .semibold))
                    Text(action.subtitle)
                        .font(.system(size: 15))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                        .lineSpacing(3)
                    DetailRow(label: "状态", value: action.status)
                    if let timeLabel = ActionTimeFormat.label(for: action.createdAt) {
                        DetailRow(label: "时间", value: timeLabel)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .sageGlassControl(cornerRadius: 22)
            }
            .padding(20)
        }
        .background(SageBackground().ignoresSafeArea())
        .navigationTitle("行动详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

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
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.getOrderDraft(noteId: noteId)
            note = response.note
            draft = response.draft
            side = response.draft.side
            orderType = response.draft.orderType
            priceText = Self.formatPrice(response.draft.price)
            quantity = response.draft.quantity
        } catch {
            errorMessage = error.localizedDescription
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
                        if !note.symbol.isEmpty { FlowTag(text: note.symbol, tone: .green) }
                        if !note.intent.isEmpty { FlowTag(text: note.intent, tone: .brand) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .sageGlassControl(cornerRadius: 22)
            }

            if let draft = viewModel.draft {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sage 将据此准备的订单")
                        .font(.system(size: 13))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                    Text("\(draft.name) · \(sideText(draft.side)) · 约 \(draft.quantity) 股 @ \(OrderFlowViewModel.formatPrice(draft.price)) \(draft.currency)")
                        .font(.system(size: 15, weight: .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(SageTheme.ColorToken.surfaceSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            PrimaryButton(title: "确认这个判断", isLoading: viewModel.isWorking) {
                Task { await viewModel.confirmLogic() }
            }
            Button("再想想") { dismiss() }
                .font(.system(size: 14))
                .foregroundColor(SageTheme.ColorToken.mutedText)
                .frame(maxWidth: .infinity)
        }
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
        switch tone {
        case .brand: return SageTheme.ColorToken.brand
        case .green: return .green
        }
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

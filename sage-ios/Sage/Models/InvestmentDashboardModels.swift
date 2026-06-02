import Foundation

struct MobileDashboardResponse: Decodable {
    let ok: Bool
    let dashboard: MobileDashboard
}

struct MobileDashboard: Decodable {
    let connected: Bool
    let account: BrokerAccount
    let assetTrend: [AssetTrendPoint]
    let todayPoints: [TodayPoint]
    let positions: [HoldingSummary]
    let walkiePrompt: String
    let updatedAt: String
}

struct AssetTrendPoint: Decodable, Identifiable {
    var id: String { time }
    let time: String
    let value: Double
}

struct BrokerAccount: Decodable {
    let id: String
    let provider: String
    let name: String
    let environment: String
    let trdMarket: String
    let currency: String
    let totalAssets: Double
    let cash: Double
    let marketValue: Double
    let dayPnl: Double
    let dayPnlPercent: Double
    let updatedAt: String
}

struct TodayPoint: Decodable, Identifiable {
    let id: String
    let tone: String
    let title: String
    let body: String
    let relatedCode: String?
    let relatedName: String?
    let newsTitle: String?
    let newsSource: String?
    let newsDate: String?
    let newsSummary: String?
    let newsUrl: String?
}

struct HoldingSummary: Decodable, Identifiable {
    let id: String
    let accountId: String
    let code: String
    let name: String
    let market: String
    let currency: String
    let quantity: Double
    let availableQuantity: Double
    let costPrice: Double
    let lastPrice: Double
    let marketValue: Double
    let unrealizedPnl: Double
    let unrealizedPnlPercent: Double
    let dayChange: Double
    let dayChangePercent: Double
    let attention: String
    let detailPoints: [HoldingDetailPoint]
}

struct HoldingDetailPoint: Decodable {
    let title: String
    let body: String
}

struct MobileActionsResponse: Decodable {
    let ok: Bool
    let actions: [InvestmentActionItem]
}

struct InvestmentActionItem: Decodable, Identifiable {
    let id: String
    let kind: String?
    let title: String
    let subtitle: String
    let status: String
    let statusCode: String?
    let groupKey: String?
    let groupTitle: String?
    let groupOrder: Int?
    let priority: Int
    let createdAt: String?
    let noteId: String?
}

/// 行动卡时间展示：优先相对时间，跨天显示绝对时间。
enum ActionTimeFormat {
    static func label(for iso: String?) -> String? {
        guard let iso, !iso.isEmpty, let date = parse(iso), date.timeIntervalSince1970 > 1_000_000_000 else {
            return nil
        }

        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(max(1, Int(interval / 60))) 分钟前" }

        let calendar = Calendar.current
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "zh_CN")

        if calendar.isDateInToday(date) {
            clock.dateFormat = "今天 HH:mm"
            return clock.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            clock.dateFormat = "昨天 HH:mm"
            return clock.string(from: date)
        }

        clock.dateFormat = "MM-dd HH:mm"
        return clock.string(from: date)
    }

    private static func parse(_ iso: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: iso) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: iso)
    }
}

struct BrokerKlineResponse: Decodable {
    let ok: Bool
    let code: String
    let period: String
    let kline: [BrokerKlinePoint]
}

struct BrokerKlinePoint: Decodable {
    let time: String
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Int
}

struct CreateIdeaNoteRequest: Encodable {
    let transcript: String?
    let symbol: String?
    let intent: String?
}

struct CreateIdeaNoteResponse: Decodable {
    let ok: Bool
    let note: IdeaNoteCardData
    let action: InvestmentActionItem
}

struct IdeaNoteCardData: Decodable, Identifiable {
    let id: String
    let transcript: String
    let symbol: String
    let intent: String
    let status: String
    let createdAt: String?
    let taskType: String?
    let condition: IdeaConditionData?
    let watchStatus: String?
    let analysis: IdeaAnalysisData?
}

struct IdeaConditionData: Decodable {
    let op: String
    let price: Double

    /// 「跌到 230」/「涨到 260」可读描述。
    var text: String {
        let verb = op == "lte" ? "跌到" : "涨到"
        let priceText = price == price.rounded() ? String(Int(price)) : String(format: "%.2f", price)
        return "\(verb) \(priceText)"
    }
}

struct IdeaAnalysisData: Decodable {
    let conclusion: String
    let points: [String]
    let suggestOrder: Bool
    let suggestedSide: String?
}

// MARK: - 分析 / 条件监控详情响应

struct NoteDetailResponse: Decodable {
    let ok: Bool
    let note: IdeaNoteCardData
    let quote: Double?
}

struct AnalyzeNoteResponse: Decodable {
    let ok: Bool
    let note: IdeaNoteCardData
    let analysis: IdeaAnalysisData
}

struct TriggerWatchResponse: Decodable {
    let ok: Bool
    let note: IdeaNoteCardData
}

// MARK: - 两步确认：订单草稿 / 模拟盘下单

struct OrderDraft: Decodable {
    let accountId: String
    let code: String
    let name: String
    let market: String
    let currency: String
    let side: String
    let orderType: String
    let price: Double
    let quantity: Int
    let lotSize: Int
    let environment: String
    let rationale: String
}

struct OrderDraftResponse: Decodable {
    let ok: Bool
    let note: IdeaNoteCardData
    let draft: OrderDraft
}

struct OrderAnalysisProgress: Decodable, Identifiable {
    var id: String { step }
    let step: String
    let message: String
    let status: String?
}

struct OrderAnalysis: Decodable {
    let title: String
    let summary: String
    let bullets: [String]
    let risks: [String]
    let sources: [String]
    let generatedAt: String
}

struct OrderAnalysisStreamEvent: Decodable {
    let type: String
    let step: String?
    let message: String?
    let status: String?
    let analysis: OrderAnalysis?
}

struct SubmitOrderRequest: Encodable {
    let noteId: String?
    let accountId: String
    let code: String
    let name: String
    let side: String
    let orderType: String
    let price: Double
    let quantity: Int
}

struct MobileOrder: Decodable {
    let id: String
    let code: String
    let side: String
    let orderType: String
    let price: Double
    let quantity: Int
    let status: String
    let dealtAvgPrice: Double?
}

struct SubmitOrderResponse: Decodable {
    let ok: Bool
    let order: MobileOrder
    let action: InvestmentActionItem
}

// MARK: - Persona Snapshot（分身 Tab）

/// 从 `/persona/memory` 的 Phase 3 嵌套 profile 中提炼出「身份摘要优先」所需的字段。
/// 解析逻辑与 Settings 的画像详情页一致（profile.explicit / profile.implicit）。
struct PersonaSnapshot {
    var riskTolerance: String?
    var capabilityLevel: String?
    var hardRules: [String]
    var focusAreas: [String]
    var lastDistilledAt: String?

    /// 是否有任何有意义的蒸馏内容（决定分身页是否回退到 mock 引导文案）。
    var hasContent: Bool {
        riskTolerance != nil || capabilityLevel != nil
            || !hardRules.isEmpty || !focusAreas.isEmpty
    }

    /// 身份一句话总结：「你的分身更像一个稳健·进阶型投资者」。
    var identityLine: String {
        let parts = [riskTolerance, capabilityLevel].compactMap { $0 }
        guard !parts.isEmpty else { return "你的分身还在学习你的投资风格" }
        return "你的分身更像一个\(parts.joined(separator: "·"))型投资者"
    }

    static func parse(from data: Data) -> PersonaSnapshot {
        var snapshot = PersonaSnapshot(
            riskTolerance: nil,
            capabilityLevel: nil,
            hardRules: [],
            focusAreas: [],
            lastDistilledAt: nil
        )

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return snapshot
        }
        let row = (payload["row"] as? [String: Any]) ?? payload
        guard !row.isEmpty else { return snapshot }

        snapshot.lastDistilledAt = row["last_distilled_at"] as? String

        guard let profile = row["profile"] as? [String: Any] else { return snapshot }
        let explicit = profile["explicit"] as? [String: Any]
        let implicit = profile["implicit"] as? [String: Any]

        if let risk = implicit?["risk_tolerance"] as? String {
            snapshot.riskTolerance = localizeRisk(risk)
        }
        if let cap = implicit?["capability_level"] as? String {
            snapshot.capabilityLevel = localizeCapability(cap)
        }

        if let rules = explicit?["hard_rules"] as? [[String: Any]] {
            snapshot.hardRules = rules.compactMap { $0["content"] as? String }.filter { !$0.isEmpty }
        }

        var focus: [String] = []
        if let universe = explicit?["focus_universe"] as? [String: Any],
           let declared = universe["declared"] as? [[String: Any]] {
            focus += declared.compactMap { $0["name"] as? String }
        }
        if let universe = implicit?["focus_universe"] as? [String: Any],
           let active = universe["active"] as? [[String: Any]] {
            focus += active.compactMap { $0["name"] as? String }
        }
        // 去重保序
        var seen = Set<String>()
        snapshot.focusAreas = focus.filter { !$0.isEmpty && seen.insert($0).inserted }

        return snapshot
    }

    private static func localizeRisk(_ risk: String) -> String {
        ["conservative": "保守", "moderate": "稳健", "aggressive": "进取", "speculative": "激进"][risk] ?? risk
    }
    private static func localizeCapability(_ cap: String) -> String {
        ["novice": "新手", "intermediate": "中级", "advanced": "进阶", "professional": "专业"][cap] ?? cap
    }
}

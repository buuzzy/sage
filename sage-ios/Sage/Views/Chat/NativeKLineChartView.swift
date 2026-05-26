import SwiftUI
import Charts
import UIKit

// MARK: - Data Models

struct KLineChartData: Codable {
    let code: String
    let name: String
    let ktype: String
    let data: [KLineDataPoint]
}

struct KLineDataPoint: Codable, Identifiable {
    var id: String { time }
    let time: String
    let open: Double
    let close: Double
    let high: Double
    let low: Double
    let vol: Int
    let turnover: Double?

    enum CodingKeys: String, CodingKey {
        case time, open, close, high, low, vol, turnover
    }

    var isUp: Bool { close >= open }
}

// MARK: - Indexed Data Point (for Chart x-axis by index)

private struct IndexedKLine: Identifiable {
    let id: Int
    let index: Int
    let point: KLineDataPoint
    var bodyLow: Double { min(point.open, point.close) }
    var bodyHigh: Double {
        let high = max(point.open, point.close)
        // 保证蜡烛体最小可见高度（价格范围的 0.5%）
        return high == bodyLow ? high + max(0.01, high * 0.005) : high
    }
}

// MARK: - MA Calculation

private struct MAPoint: Identifiable {
    let id: String
    let index: Int
    let value: Double
}

private func calculateMA(points: [KLineDataPoint], period: Int) -> [MAPoint] {
    guard points.count >= period else { return [] }
    var result: [MAPoint] = []
    for i in (period - 1)..<points.count {
        var sum: Double = 0
        for j in (i - period + 1)...i {
            sum += points[j].close
        }
        let avg = sum / Double(period)
        result.append(MAPoint(id: "\(period)_\(i)", index: i, value: avg))
    }
    return result
}

// MARK: - Constants

private struct MAConfig {
    let period: Int
    let color: Color
    let label: String
}

private let maConfigs: [MAConfig] = [
    MAConfig(period: 5, color: Color(red: 0.96, green: 0.62, blue: 0.04), label: "MA5"),
    MAConfig(period: 10, color: Color(red: 0.02, green: 0.71, blue: 0.83), label: "MA10"),
    MAConfig(period: 20, color: Color(red: 0.66, green: 0.33, blue: 0.97), label: "MA20"),
]

// 涨红跌绿（中国 A 股惯例）
private let upColor = Color(red: 0.94, green: 0.27, blue: 0.27)   // 涨（红）
private let downColor = Color(red: 0.06, green: 0.73, blue: 0.51) // 跌（绿）

private let ktypeLabels: [String: String] = [
    "day": "日K",
    "week": "周K",
    "month": "月K",
]

// MARK: - Native K-Line Chart View

struct NativeKLineChartView: View {
    let data: KLineChartData
    let compact: Bool
    let maxPoints: Int

    init(data: KLineChartData, compact: Bool = true, maxPoints: Int = 30) {
        self.data = data
        self.compact = compact
        self.maxPoints = maxPoints
    }

    /// 过滤有效数据并截取最近 N 条
    private var displayData: [KLineDataPoint] {
        let valid = data.data.filter { isValidTime($0.time) }
        if valid.count <= maxPoints { return valid }
        return Array(valid.suffix(maxPoints))
    }

    private var indexedData: [IndexedKLine] {
        displayData.enumerated().map { IndexedKLine(id: $0.offset, index: $0.offset, point: $0.element) }
    }

    private var ma5Data: [MAPoint] { calculateMA(points: displayData, period: 5) }
    private var ma10Data: [MAPoint] { calculateMA(points: displayData, period: 10) }
    private var ma20Data: [MAPoint] { calculateMA(points: displayData, period: 20) }

    private var yMin: Double { displayData.map(\.low).min() ?? 0 }
    private var yMax: Double { displayData.map(\.high).max() ?? 100 }
    private var yPadding: Double { (yMax - yMin) * 0.08 }

    /// 最高点
    private var highestPoint: IndexedKLine? {
        indexedData.max(by: { $0.point.high < $1.point.high })
    }

    /// 最低点
    private var lowestPoint: IndexedKLine? {
        indexedData.min(by: { $0.point.low < $1.point.low })
    }

    /// MA 最新值
    private var lastMA5: Double? { ma5Data.last?.value }
    private var lastMA10: Double? { ma10Data.last?.value }
    private var lastMA20: Double? { ma20Data.last?.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            maLegendWithValues

            if displayData.isEmpty {
                emptyState
            } else {
                klineChart
                dateRangeLabel
            }
        }
    }

    // MARK: - MA Legend (参考截图: "均线 5:88.07 10:94.24 30:95.46")

    private var maLegendWithValues: some View {
        HStack(spacing: 3) {
            Text("均线")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            maValueLabel(period: 5, value: lastMA5, color: maConfigs[0].color)
            maValueLabel(period: 10, value: lastMA10, color: maConfigs[1].color)
            maValueLabel(period: 20, value: lastMA20, color: maConfigs[2].color)

            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func maValueLabel(period: Int, value: Double?, color: Color) -> some View {
        HStack(spacing: 1) {
            Text("\(period):")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value != nil ? formatPrice(value!) : "--")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(color)
        }
    }

    // MARK: - K-Line Chart (拆分为子视图避免类型推断超时)

    private var klineChart: some View {
        Chart {
            candleWicks
            candleBodies
            ma5Line
            ma10Line
            ma20Line
            highAnnotation
            lowAnnotation
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.2))
                    .foregroundStyle(Color(.systemGray4))
                AxisValueLabel {
                    if let val = value.as(Double.self) {
                        Text(formatPrice(val))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .chartYScale(domain: (yMin - yPadding)...(yMax + yPadding))
        .chartXScale(domain: -1...(displayData.count))
        .chartLegend(.hidden)
        .frame(height: compact ? 200 : 300)
    }

    // MARK: - Chart Content (拆分为 ChartContent builder)

    @ChartContentBuilder
    private var candleWicks: some ChartContent {
        ForEach(indexedData) { item in
            RuleMark(
                x: .value("Idx", item.index),
                yStart: .value("Low", item.point.low),
                yEnd: .value("High", item.point.high)
            )
            .foregroundStyle(candleColor(for: item.point))
            .lineStyle(StrokeStyle(lineWidth: 1))
        }
    }

    @ChartContentBuilder
    private var candleBodies: some ChartContent {
        ForEach(indexedData) { item in
            RectangleMark(
                x: .value("Idx", item.index),
                yStart: .value("Open", item.bodyLow),
                yEnd: .value("Close", item.bodyHigh),
                width: .fixed(candleWidth)
            )
            .foregroundStyle(candleColor(for: item.point))
        }
    }

    @ChartContentBuilder
    private var ma5Line: some ChartContent {
        ForEach(ma5Data) { point in
            LineMark(
                x: .value("Idx", point.index),
                y: .value("MA", point.value)
            )
            .foregroundStyle(maConfigs[0].color)
            .lineStyle(StrokeStyle(lineWidth: 1.2))
            .interpolationMethod(.linear)
        }
    }

    @ChartContentBuilder
    private var ma10Line: some ChartContent {
        ForEach(ma10Data) { point in
            LineMark(
                x: .value("Idx", point.index),
                y: .value("MA", point.value)
            )
            .foregroundStyle(maConfigs[1].color)
            .lineStyle(StrokeStyle(lineWidth: 1.2))
            .interpolationMethod(.linear)
        }
    }

    @ChartContentBuilder
    private var ma20Line: some ChartContent {
        ForEach(ma20Data) { point in
            LineMark(
                x: .value("Idx", point.index),
                y: .value("MA", point.value)
            )
            .foregroundStyle(maConfigs[2].color)
            .lineStyle(StrokeStyle(lineWidth: 1.2))
            .interpolationMethod(.linear)
        }
    }

    @ChartContentBuilder
    private var highAnnotation: some ChartContent {
        if let highest = highestPoint {
            PointMark(
                x: .value("Idx", highest.index),
                y: .value("Price", highest.point.high)
            )
            .foregroundStyle(.clear)
            .annotation(position: highest.index > displayData.count / 2 ? .leading : .trailing) {
                Text("—\(formatPrice(highest.point.high))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }

    @ChartContentBuilder
    private var lowAnnotation: some ChartContent {
        if let lowest = lowestPoint {
            PointMark(
                x: .value("Idx", lowest.index),
                y: .value("Price", lowest.point.low)
            )
            .foregroundStyle(.clear)
            .annotation(position: lowest.index > displayData.count / 2 ? .leading : .trailing) {
                Text("—\(formatPrice(lowest.point.low))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.primary)
            }
        }
    }

    // MARK: - Date Range (起止日期)

    private var dateRangeLabel: some View {
        HStack {
            Text(displayData.first?.time ?? "")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Spacer()
            Text(displayData.last?.time ?? "")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text("暂无 K 线数据")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: compact ? 200 : 300)
    }

    // MARK: - Helpers

    private var candleWidth: CGFloat {
        if compact {
            return displayData.count > 40 ? 3 : 5
        } else {
            return displayData.count > 50 ? 5 : 7
        }
    }

    private func candleColor(for point: KLineDataPoint) -> Color {
        point.isUp ? upColor : downColor
    }

    private func isValidTime(_ t: String) -> Bool {
        let pattern = #"^\d{4}-\d{2}-\d{2}$"#
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    private func formatPrice(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0f", value)
        } else if value >= 100 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}

// MARK: - Full Screen K-Line View (强制横屏)

struct NativeKLineFullScreenView: View {
    let data: KLineChartData
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部工具栏
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(data.name) \(data.code)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(ktypeLabels[data.ktype] ?? "日K")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button { dismissAndRestore() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .background(Color(UIColor.systemGray6))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)

                // 横屏图表 — 展示更多数据 (60 条)
                NativeKLineChartView(data: data, compact: false, maxPoints: 60)
                    .padding(.horizontal, 12)

                Spacer()
            }
        }
        .onAppear { forceLandscape() }
    }

    private func forceLandscape() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .landscape)
        windowScene.requestGeometryUpdate(geometryPreferences) { _ in }
        // 备用方案：强制设备方向
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
    }

    private func dismissAndRestore() {
        // 先恢复竖屏再 dismiss
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            dismiss()
            return
        }
        let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: .portrait)
        windowScene.requestGeometryUpdate(geometryPreferences) { _ in }
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        dismiss()
    }
}

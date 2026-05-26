import SwiftUI

/// 运行指示器 — 三个跳跃圆点（参考 Gemini 风格）
/// 根据最后一个工具名称动态变化文字
struct RunningIndicatorView: View {
    let lastToolName: String?

    var body: some View {
        HStack(spacing: 10) {
            BouncingDots()

            // 动态文字
            Text(indicatorText)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var indicatorText: String {
        guard let tool = lastToolName?.lowercased() else {
            return "正在思考"
        }
        switch tool {
        case "bash":
            return "正在执行命令"
        case "read":
            return "正在读取"
        case "write":
            return "正在写入"
        case "edit":
            return "正在编辑"
        case "websearch", "web_search":
            return "正在搜索"
        case "webfetch", "web_fetch":
            return "正在获取网页"
        case "grep":
            return "正在搜索代码"
        case "glob":
            return "正在查找文件"
        default:
            return "正在执行"
        }
    }
}

// MARK: - Bouncing Dots Animation (使用 TimelineView 保证动画始终运行)

struct BouncingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { index in
                    let offset = dotOffset(for: index, date: timeline.date)
                    Circle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 6, height: 6)
                        .offset(y: offset)
                }
            }
            .frame(width: 24, height: 16)
        }
    }

    /// 基于时间计算每个圆点的 Y 偏移（正弦波 + 相位差）
    private func dotOffset(for index: Int, date: Date) -> CGFloat {
        let elapsed = date.timeIntervalSinceReferenceDate
        let frequency = 2.5  // 每秒跳动次数
        let phase = Double(index) * 0.4  // 圆点间相位差
        let y = sin((elapsed * frequency + phase) * .pi) * 4.0
        return CGFloat(-max(y, 0))  // 只取正值（向上跳）
    }
}


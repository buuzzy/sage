import SwiftUI

/// 运行指示器 — 对标桌面端 RunningIndicator
/// 橙色旋转圆弧 + 根据最后一个工具名称动态变化的文字
struct RunningIndicatorView: View {
    let lastToolName: String?
    @State private var rotation: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            // 橙色旋转圆弧
            Circle()
                .trim(from: 0.0, to: 0.7)
                .stroke(
                    Color.orange,
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .frame(width: 16, height: 16)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }

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
            return "正在思考..."
        }
        switch tool {
        case "bash":
            return "正在执行命令..."
        case "read":
            return "正在读取文件..."
        case "write":
            return "正在写入文件..."
        case "edit":
            return "正在编辑文件..."
        case "websearch", "web_search":
            return "正在搜索网络..."
        case "webfetch", "web_fetch":
            return "正在获取网页..."
        case "grep":
            return "正在搜索代码..."
        case "glob":
            return "正在查找文件..."
        default:
            return "正在执行 \(lastToolName ?? "任务")..."
        }
    }
}

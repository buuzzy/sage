import SwiftUI

/// 单个工具项 — TaskGroup 内的子项
/// 显示：树形连线 + 工具名 + 参数摘要 + 状态图标
/// 注：不可点击展开细节（安全考虑，防止 API 细节被逆向工程）
struct ToolItemRow: View {
    let tool: ToolCallItem
    let isLast: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // 树形连线
            VStack(spacing: 0) {
                Rectangle()
                    .fill(SageTheme.ColorToken.hairline)
                    .frame(width: 1)

                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)

                if !isLast {
                    Rectangle()
                        .fill(SageTheme.ColorToken.hairline)
                        .frame(width: 1)
                } else {
                    Spacer()
                        .frame(width: 1)
                }
            }
            .frame(width: 12, height: 24)
            .padding(.leading, 8)

            // 工具图标
            Image(systemName: toolIcon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)

            // 工具名
            Text(toolDisplayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)

            Spacer()

            // 状态
            toolStatus
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed

    private var toolDisplayName: String {
        switch tool.name.lowercased() {
        case "bash": return "执行命令"
        case "read": return "读取文件"
        case "write": return "写入文件"
        case "edit": return "编辑文件"
        case "websearch", "web_search": return "搜索网页"
        case "webfetch", "web_fetch": return "获取网页"
        default: return tool.name
        }
    }

    private var toolIcon: String {
        switch tool.name.lowercased() {
        case "bash": return "terminal"
        case "read": return "doc.text"
        case "write": return "pencil.line"
        case "edit": return "pencil"
        case "websearch", "web_search": return "magnifyingglass"
        case "webfetch", "web_fetch": return "globe"
        default: return "wrench"
        }
    }

    @ViewBuilder
    private var toolStatus: some View {
        if tool.isComplete {
            if tool.isError {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.red)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
            }
        } else {
            ProgressView()
                .scaleEffect(0.6)
        }
    }
}

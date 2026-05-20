import SwiftUI

/// 单个工具项 — TaskGroup 内的子项
/// 显示：树形连线 + 工具名 + 参数摘要 + 状态图标
struct ToolItemRow: View {
    let tool: ToolCallItem
    let isLast: Bool

    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            HStack(alignment: .center, spacing: 8) {
                // 树形连线
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 1)

                    Circle()
                        .fill(Color(.systemGray4))
                        .frame(width: 5, height: 5)

                    if !isLast {
                        Rectangle()
                            .fill(Color(.systemGray4))
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
                    .foregroundColor(.orange)
                    .frame(width: 16)

                // 工具名 + 参数
                VStack(alignment: .leading, spacing: 1) {
                    Text(toolDisplayName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)

                    if let param = toolParamSummary {
                        Text(param)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // 状态
                toolStatus
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            ToolDetailSheet(tool: tool)
        }
    }

    // MARK: - Computed

    private var toolDisplayName: String {
        // 简化显示名：Bash → 命令, Read → 读取, Write → 写入, WebSearch → 搜索
        switch tool.name.lowercased() {
        case "bash": return "Bash"
        case "read": return "Read"
        case "write": return "Write"
        case "edit": return "Edit"
        case "websearch", "web_search": return "WebSearch"
        case "webfetch", "web_fetch": return "WebFetch"
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

    private var toolParamSummary: String? {
        guard let input = tool.input, !input.isEmpty else { return nil }
        // 尝试提取关键参数（command / file_path / query）
        if let data = input.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let cmd = dict["command"] as? String {
                return String(cmd.prefix(60))
            }
            if let path = dict["file_path"] as? String {
                return path.split(separator: "/").last.map(String.init) ?? path
            }
            if let query = dict["query"] as? String {
                return String(query.prefix(40))
            }
            if let url = dict["url"] as? String {
                return String(url.prefix(50))
            }
        }
        return String(input.prefix(50))
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

// MARK: - Tool Detail Sheet

struct ToolDetailSheet: View {
    let tool: ToolCallItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Input
                    if let input = tool.input, !input.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("输入")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(input)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                    }

                    // Output
                    if let output = tool.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("输出")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(output)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(tool.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Color(.systemGray5))
                            .clipShape(Circle())
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

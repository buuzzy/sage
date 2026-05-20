import SwiftUI

/// 任务组卡片 — 对标桌面端 TaskGroupComponent
/// 标题行：✅/🔵 + AI 描述文字（最多 2 行）
/// 可折叠工具列表：默认折叠（完成后自动折叠），点击展开
struct TaskGroupRow: View {
    let title: String
    let tools: [ToolCallItem]
    let isComplete: Bool

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ─── 标题行 ───────────────────────────────────
            HStack(alignment: .top, spacing: 10) {
                // 状态图标
                statusIcon
                    .frame(width: 20, height: 20)

                // AI 描述文字
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // ─── 折叠按钮 ─────────────────────────────────
            if !tools.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)

                        Text(isExpanded ? "隐藏步骤" : "显示 \(tools.count) 个步骤")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                // ─── 展开的工具列表 ───────────────────────
                if isExpanded {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(tools.enumerated()), id: \.element.id) { index, tool in
                            ToolItemRow(
                                tool: tool,
                                isLast: index == tools.count - 1
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        // 完成后自动折叠
        .onChange(of: isComplete) { complete in
            if complete {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded = false
                }
            }
        }
    }

    // MARK: - Status Icon

    @ViewBuilder
    private var statusIcon: some View {
        if isComplete {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(.green)
        } else {
            // 蓝色脉冲点 — 执行中
            Circle()
                .fill(Color.blue)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                        .scaleEffect(1.6)
                )
                .frame(width: 16, height: 16)
        }
    }
}

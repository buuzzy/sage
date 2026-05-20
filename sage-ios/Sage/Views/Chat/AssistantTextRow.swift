import SwiftUI
import MarkdownUI

/// AI 文本消息 — 左对齐 Markdown 渲染 + 底部操作栏
struct AssistantTextRow: View {
    let content: String
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if content.isEmpty && isStreaming {
                // 等待中的点动画
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .frame(width: 5, height: 5)
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
                .padding(.horizontal, 16)
            } else {
                // Markdown 渲染
                MarkdownContentView(text: content)
                    .padding(.horizontal, 16)

                // 操作栏（非流式时显示）
                if !isStreaming && !content.isEmpty {
                    actionBar
                }
            }
        }
    }

    // MARK: - Action Bar (匹配桌面端 AgentActionBar)

    private var actionBar: some View {
        HStack(spacing: 16) {
            // 复制回答
            Button {
                UIPasteboard.general.string = content
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                    Text("复制回答")
                        .font(.system(size: 12))
                }
                .foregroundColor(Color(.systemGray2))
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }
}

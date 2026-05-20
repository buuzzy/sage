import SwiftUI
import MarkdownUI

/// 消息行 — 用户消息右对齐气泡，AI 回复左对齐无气泡
struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.role == .user {
                // User — right aligned gray bubble
                HStack {
                    Spacer(minLength: 60)
                    Text(message.content)
                        .font(.system(size: 15))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .cornerRadius(16)
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 16)

            } else if message.role == .assistant {
                // AI — left aligned, plain text with markdown
                VStack(alignment: .leading, spacing: 8) {
                    if message.content.isEmpty && message.isStreaming {
                        HStack(spacing: 6) {
                            ForEach(0..<3, id: \.self) { _ in
                                Circle()
                                    .frame(width: 5, height: 5)
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                        }
                        .padding(.horizontal, 16)
                    } else {
                        MarkdownContentView(text: message.content)
                            .padding(.horizontal, 16)

                        // Action bar (only when not streaming)
                        if !message.isStreaming && !message.content.isEmpty {
                            HStack(spacing: 18) {
                                actionButton("doc.on.doc") { UIPasteboard.general.string = message.content }
                                actionButton("hand.thumbsup") { }
                                actionButton("hand.thumbsdown") { }
                                actionButton("arrow.uturn.forward") { }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 2)
                        }
                    }
                }

            } else if message.role == .error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text(message.content)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
    }

    private func actionButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundColor(Color(.systemGray2))
        }
    }
}

import SwiftUI

/// 用户消息 — Gemini 风格右对齐浅灰气泡
struct UserMessageRow: View {
    let content: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(content)
                .font(.system(size: 16))
                .lineSpacing(4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
    }
}

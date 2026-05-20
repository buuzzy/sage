import SwiftUI

/// 用户消息 — 右对齐灰色气泡
struct UserMessageRow: View {
    let content: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(content)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.systemGray5))
                .cornerRadius(16)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
    }
}

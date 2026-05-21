import SwiftUI

/// 用户消息 — 右对齐柔和气泡
struct UserMessageRow: View {
    let content: String

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            Text(content)
                .font(.system(size: 15))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(SageTheme.ColorToken.brandSoft)
                .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous)
                        .stroke(SageTheme.ColorToken.brand.opacity(0.12), lineWidth: 1)
                )
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
    }
}

import SwiftUI
import MarkdownUI

/// Markdown 内容渲染视图
struct MarkdownContentView: View {
    let text: String

    var body: some View {
        Markdown(text)
            .markdownTheme(.gitHub)
            .markdownBlockStyle(\.codeBlock) { configuration in
                configuration.label
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.9))
                    }
            }
            .textSelection(.enabled)
    }
}

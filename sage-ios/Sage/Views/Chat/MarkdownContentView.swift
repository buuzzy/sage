import SwiftUI
import MarkdownUI

/// Markdown 内容渲染视图 — 对标桌面端 Sage 风格
/// 字体 17pt、表格全边框+灰底表头+充足 padding
struct MarkdownContentView: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Markdown(text)
            .markdownTheme(.sage)
            .textSelection(.enabled)
    }
}

// MARK: - Sage iOS Theme (匹配桌面端 prose-sm + 自定义 table)

extension MarkdownUI.Theme {
    static let sage = Theme()
        // ─── 正文 (对标桌面 prose-sm → iOS 用 17pt body) ──────
        .text {
            ForegroundColor(.primary)
            BackgroundColor(nil)
            FontSize(17)
        }
        .paragraph { configuration in
            configuration.label
                .markdownMargin(top: 0, bottom: 14)
                .lineSpacing(5)
        }
        // ─── 行内样式 ─────────────────────────────────────
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .strikethrough {
            StrikethroughStyle(.single)
        }
        .link {
            ForegroundColor(.blue)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(15)
            ForegroundColor(Color(.label))
            BackgroundColor(Color(.systemGray6))
        }
        // ─── 标题（对标桌面 prose heading sizes）────────────
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(26)
                    ForegroundColor(.primary)
                }
                .markdownMargin(top: 28, bottom: 14)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(22)
                    ForegroundColor(.primary)
                }
                .markdownMargin(top: 24, bottom: 12)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(19)
                    ForegroundColor(.primary)
                }
                .markdownMargin(top: 20, bottom: 10)
        }
        .heading4 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(17)
                    ForegroundColor(.primary)
                }
                .markdownMargin(top: 16, bottom: 8)
        }
        // ─── 代码块（对标桌面 bg-muted rounded-lg p-4）────────
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(14)
                        ForegroundColor(Color(.label))
                    }
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .markdownMargin(top: 12, bottom: 12)
        }
        // ─── 引用块 ─────────────────────────────────────────
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(.systemGray3))
                    .frame(width: 4)
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(.secondary)
                        FontSize(16)
                    }
                    .padding(.leading, 14)
            }
            .markdownMargin(top: 12, bottom: 12)
        }
        // ─── 列表 ─────────────────────────────────────────
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: 5, bottom: 5)
        }
        // ─── 表格（核心：对标桌面 border-collapse + bg-muted th）──
        .table { configuration in
            ScrollView(.horizontal, showsIndicators: true) {
                configuration.label
                    .markdownTableBorderStyle(
                        .init(color: Color(.systemGray4), width: 1)
                    )
                    .markdownTableBackgroundStyle(
                        .alternatingRows(
                            Color(.systemBackground),
                            Color(.systemGray6).opacity(0.4)
                        )
                    )
                    .markdownTextStyle {
                        FontSize(15)
                        ForegroundColor(.primary)
                    }
            }
            .markdownMargin(top: 12, bottom: 12)
        }
        .tableCell { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(15)
                    ForegroundColor(.primary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        // ─── 分割线 ─────────────────────────────────────────
        .thematicBreak {
            Divider()
                .markdownMargin(top: 20, bottom: 20)
        }
        // ─── 图片 ─────────────────────────────────────────
        .image { configuration in
            configuration.label
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .markdownMargin(top: 8, bottom: 8)
        }
}

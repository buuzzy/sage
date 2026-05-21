import SwiftUI
import MarkdownUI

/// AI 文本消息 — 左对齐 Markdown 渲染 + Artifact 图表 + 底部操作栏
struct AssistantTextRow: View {
    let content: String
    let isStreaming: Bool
    @State private var cursorVisible = true

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
                let parsed = ArtifactParser.extract(from: content)

                // Artifact 渲染
                ForEach(parsed.artifacts, id: \.id) { artifact in
                    ArtifactView(type: artifact.type, jsonData: artifact.jsonData)
                }

                // Markdown 渲染 + 流式光标
                if !parsed.cleanText.isEmpty {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        MarkdownContentView(text: parsed.cleanText)
                        // 流式打字光标
                        if isStreaming {
                            Text("|")
                                .font(.system(size: 17, weight: .light))
                                .foregroundColor(.primary)
                                .opacity(cursorVisible ? 1 : 0)
                                .onAppear {
                                    withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                                        cursorVisible.toggle()
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // 操作栏（非流式时显示）
                if !isStreaming && !parsed.cleanText.isEmpty {
                    actionBar
                }
            }
        }
    }

    // MARK: - Action Bar (匹配桌面端 AgentActionBar)

    private var actionBar: some View {
        HStack(spacing: 10) {
            // 复制回答
            Button {
                let parsed = ArtifactParser.extract(from: content)
                UIPasteboard.general.string = parsed.cleanText
            } label: {
                actionLabel(icon: "doc.on.doc", title: "复制")
            }

            // 报告问题
            Button {
                // 打开系统分享/反馈（简化版）
                let feedbackText = "问题反馈:\n\n回答内容:\n\(content.prefix(500))"
                UIPasteboard.general.string = feedbackText
            } label: {
                actionLabel(icon: "exclamationmark.triangle", title: "反馈")
            }

            Button {
                let parsed = ArtifactParser.extract(from: content)
                UIPasteboard.general.string = parsed.cleanText
            } label: {
                actionLabel(icon: "square.and.arrow.up", title: "分享")
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func actionLabel(icon: String, title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(SageTheme.ColorToken.mutedText)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(SageTheme.ColorToken.surfaceSecondary.opacity(0.72))
        .clipShape(Capsule())
    }
}

// MARK: - Artifact Parser (对标桌面端 artifactParser.ts)

/// 从 AI 文本中提取 ```artifact:TYPE\n{json}\n``` 格式的 artifact
struct ArtifactParser {
    struct ParseResult {
        let cleanText: String
        let artifacts: [ArtifactItem]
    }

    struct ArtifactItem: Identifiable {
        let id: String
        let type: String
        let jsonData: String
    }

    private static let validTypes: Set<String> = [
        "quote-card", "kline-chart", "news-list", "finance-breakfast",
        "ai-hot-news", "bar-chart", "line-chart", "data-table",
        "stock-snapshot", "sector-heatmap", "research-consensus",
        "financial-health", "news-feed"
    ]

    static func extract(from text: String) -> ParseResult {
        var artifacts: [ArtifactItem] = []
        var cleanText = text

        // Check for incomplete block (still streaming)
        if hasIncompleteBlock(text) {
            if let lastOpen = text.range(of: "```artifact:", options: .backwards) {
                cleanText = String(text[text.startIndex..<lastOpen.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ParseResult(cleanText: cleanText, artifacts: [])
        }

        // Regex: ```artifact:TYPE\n{...}\n```
        let pattern = "```artifact:([\\w-]+)\\s*\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ParseResult(cleanText: text, artifacts: [])
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for (i, match) in matches.enumerated().reversed() {
            guard match.numberOfRanges >= 3 else { continue }
            let typeRange = match.range(at: 1)
            let bodyRange = match.range(at: 2)
            let type = nsText.substring(with: typeRange).trimmingCharacters(in: .whitespaces)
            let body = nsText.substring(with: bodyRange)

            guard validTypes.contains(type) else { continue }

            let item = ArtifactItem(
                id: "art_\(i)_\(type)",
                type: type,
                jsonData: body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            artifacts.insert(item, at: 0)

            // Remove from clean text
            let fullRange = match.range(at: 0)
            cleanText = (cleanText as NSString).replacingCharacters(in: fullRange, with: "")
        }

        cleanText = cleanText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParseResult(cleanText: cleanText, artifacts: artifacts)
    }

    private static func hasIncompleteBlock(_ text: String) -> Bool {
        guard let lastOpen = text.range(of: "```artifact:", options: .backwards) else {
            return false
        }
        let afterOpen = text[lastOpen.upperBound...]
        // Check if there's a closing ``` after the opening
        return !afterOpen.contains("```")
    }
}

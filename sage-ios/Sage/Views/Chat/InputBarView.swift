import SwiftUI

/// 底部输入栏 — ChatGPT 风格
/// 未配置模型时禁止发送（按钮灰显）
struct InputBarView: View {
    let isRunning: Bool
    let isModelConfigured: Bool
    let onSend: (String) -> Void
    let onStop: () -> Void

    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)

            HStack(alignment: .bottom, spacing: 10) {
                // Text field
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .disabled(isRunning)

                // Send or Stop
                if isRunning {
                    Button { onStop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color(.darkGray))
                            .clipShape(Circle())
                    }
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(canSend ? Color(.darkGray) : Color(.systemGray4))
                            .clipShape(Circle())
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    private var placeholder: String {
        if !isModelConfigured { return "请先配置模型..." }
        if isRunning { return "等待回复..." }
        return "询问 Sage..."
    }

    private var canSend: Bool {
        isModelConfigured && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, isModelConfigured else { return }
        text = ""
        onSend(prompt)
    }
}

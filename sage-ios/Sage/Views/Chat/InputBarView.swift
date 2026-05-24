import SwiftUI
import PhotosUI

/// 底部输入栏 — Gemini 风格浮动胶囊 + Sage 金融能力入口
struct InputBarView: View {
    let isRunning: Bool
    let isModelConfigured: Bool
    let onSend: (String, [SelectedImage]) -> Void
    let onStop: () -> Void

    @State private var text = ""
    @State private var selectedImages: [SelectedImage] = []
    @State private var showAttachMenu = false
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: SageTheme.Spacing.xs) {
            // 已选图片预览
            if !selectedImages.isEmpty {
                imagePreviewBar
            }

            HStack(alignment: .bottom, spacing: SageTheme.Spacing.xs) {
                // "+" 按钮
                Button {
                    showAttachMenu = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(SageTheme.ColorToken.brand)
                        .frame(width: 38, height: 38)
                        .background(SageTheme.ColorToken.brandSoft)
                        .clipShape(Circle())
                }
                .disabled(isRunning)

                // 输入框
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .font(.system(size: 15))
                    .padding(.horizontal, SageTheme.Spacing.sm)
                    .padding(.vertical, 9)
                    .frame(minHeight: 38)
                    .disabled(isRunning)

                // 发送/停止
                if isRunning {
                    Button { onStop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.red.opacity(0.88))
                            .clipShape(Circle())
                    }
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(canSend ? SageTheme.ColorToken.brand : Color(.systemGray4))
                            .clipShape(Circle())
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, SageTheme.Spacing.xs)
            .padding(.vertical, SageTheme.Spacing.xs)
            .sagePillBackground()
            .padding(.horizontal, SageTheme.Spacing.md)
            .padding(.bottom, SageTheme.Spacing.xs)
        }
        .padding(.top, SageTheme.Spacing.xs)
        .background(
            LinearGradient(
                colors: [
                    Color.clear,
                    SageTheme.ColorToken.brandSoft.opacity(0.28)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .sheet(isPresented: $showAttachMenu) {
            SageCapabilitySheet(
                onCamera: { showCamera = true },
                onPhotos: { showPhotoPicker = true }
            )
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.hidden)
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems, maxSelectionCount: 4, matching: .images)
        .onChange(of: photoPickerItems) { items in
            Task { await loadImages(from: items) }
        }
        .sheet(isPresented: $showCamera) {
            CameraView { image in
                if let data = image.jpegData(compressionQuality: 0.8) {
                    selectedImages.append(SelectedImage(data: data, mediaType: "image/jpeg"))
                }
            }
        }
    }

    // MARK: - Image Preview Bar

    private var imagePreviewBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedImages) { img in
                    ZStack(alignment: .topTrailing) {
                        if let uiImage = UIImage(data: img.data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                                .clipped()
                        }
                        Button {
                            selectedImages.removeAll { $0.id == img.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.5).clipShape(Circle()))
                        }
                        .offset(x: 4, y: -4)
                    }
                }
            }
            .padding(.horizontal, SageTheme.Spacing.md)
            .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private var placeholder: String {
        if !isModelConfigured { return "请先配置模型..." }
        if isRunning { return "等待回复..." }
        return "询问 Sage..."
    }

    private var canSend: Bool {
        isModelConfigured && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !selectedImages.isEmpty)
    }

    private func send() {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        let images = selectedImages
        text = ""
        selectedImages = []
        photoPickerItems = []
        onSend(prompt, images)
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    // 判断类型
                    let mediaType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                    selectedImages.append(SelectedImage(data: data, mediaType: mediaType))
                }
            }
        }
    }
}

// MARK: - Sage Capability Sheet

struct SageCapabilitySheet: View {
    let onCamera: () -> Void
    let onPhotos: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SageSheetHandle()

            VStack(alignment: .leading, spacing: SageTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加到对话")
                        .font(.system(size: 20, weight: .semibold))
                    Text("上传图片素材让 Sage 一起分析。")
                        .font(.system(size: 13))
                        .foregroundColor(SageTheme.ColorToken.mutedText)
                }

                HStack(spacing: SageTheme.Spacing.sm) {
                    capabilityButton(icon: "camera", title: "拍照") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onCamera() }
                    }
                    capabilityButton(icon: "photo.on.rectangle", title: "相册") {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onPhotos() }
                    }
                }
            }
            .padding(.horizontal, SageTheme.Spacing.xl)
            .padding(.top, SageTheme.Spacing.sm)
            .padding(.bottom, SageTheme.Spacing.xl)
        }
        .background(SageTheme.ColorToken.surface)
    }

    private func capabilityButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SageTheme.Spacing.md)
            .background(SageTheme.ColorToken.brandSoft.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: SageTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Selected Image Model

struct SelectedImage: Identifiable {
    let id = UUID()
    let data: Data
    let mediaType: String

    /// Base64 编码（用于发送给 Agent）
    var base64: String { data.base64EncodedString() }
}

// MARK: - Camera View (UIImagePickerController wrapper)

struct CameraView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView
        init(_ parent: CameraView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

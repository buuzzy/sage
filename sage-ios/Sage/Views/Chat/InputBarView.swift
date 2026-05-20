import SwiftUI
import PhotosUI

/// 底部输入栏 — ChatGPT 风格
/// "+" 按钮（相册/拍照/文件）+ 输入框 + 发送/停止
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
        VStack(spacing: 0) {
            Divider().opacity(0.3)

            // 已选图片预览
            if !selectedImages.isEmpty {
                imagePreviewBar
            }

            HStack(alignment: .bottom, spacing: 8) {
                // "+" 按钮
                Button {
                    showAttachMenu = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
                .disabled(isRunning)

                // 输入框
                TextField(placeholder, text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 36)
                    .background(Color(.systemGray6))
                    .cornerRadius(18)
                    .disabled(isRunning)

                // 发送/停止
                if isRunning {
                    Button { onStop() } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color(.darkGray))
                            .clipShape(Circle())
                    }
                } else {
                    Button { send() } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
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
        .confirmationDialog("添加附件", isPresented: $showAttachMenu, titleVisibility: .hidden) {
            Button("拍照") { showCamera = true }
            Button("从相册选择") { showPhotoPicker = true }
            // 后续扩展：文件上传
            // Button("选择文件") { showFilePicker = true }
            Button("取消", role: .cancel) { }
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
            .padding(.horizontal, 14)
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

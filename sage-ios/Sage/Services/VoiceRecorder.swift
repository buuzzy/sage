import AVFoundation

/// 投资对讲机 push-to-talk 录音器。
///
/// 录制 16kHz 单声道 AAC(.m4a)，匹配 SenseVoice 推荐输入（16kHz / mono）。
/// 「按住说话 → 松手」语义：`start()` 开始录，`stop()` 结束并返回音频文件 URL。
/// 时长过短返回 nil（避免误触上传空音频）。
@MainActor
final class VoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false

    private var recorder: AVAudioRecorder?
    private var fileURL: URL?

    /// 低于此时长视为误触，丢弃。
    private let minDuration: TimeInterval = 0.5

    enum RecorderError: LocalizedError {
        case permissionDenied
        case sessionFailed(String)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                return "需要麦克风权限才能用对讲机，请在系统设置中开启。"
            case .sessionFailed(let message):
                return "录音启动失败：\(message)"
            }
        }
    }

    /// 请求权限并开始录音。
    func start() async throws {
        guard await Self.ensurePermission() else { throw RecorderError.permissionDenied }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            throw RecorderError.sessionFailed(error.localizedDescription)
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("walkie-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            self.recorder = recorder
            self.fileURL = url
            isRecording = true
        } catch {
            throw RecorderError.sessionFailed(error.localizedDescription)
        }
    }

    /// 停止录音并返回音频文件 URL；未在录音或时长过短时返回 nil 并清理临时文件。
    func stop() -> URL? {
        guard let recorder, isRecording else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard duration >= minDuration, let url = fileURL else {
            cleanupTempFile()
            return nil
        }
        return url
    }

    private func cleanupTempFile() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
    }

    private static func ensurePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return true
            case .denied: return false
            case .undetermined: return await AVAudioApplication.requestRecordPermission()
            @unknown default: return false
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted: return true
            case .denied: return false
            case .undetermined:
                return await withCheckedContinuation { continuation in
                    session.requestRecordPermission { continuation.resume(returning: $0) }
                }
            @unknown default: return false
            }
        }
    }
}

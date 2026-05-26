import Foundation
import UIKit

/// 错误上报服务 — 将用户反馈/崩溃日志写入 Supabase error_logs 表
/// 对标桌面端 src/shared/sync/error-sync.ts
actor ErrorReportService {
    static let shared = ErrorReportService()

    /// 提交错误日志到 Supabase
    func submit(
        errorType: String,
        message: String,
        errorCode: String? = nil,
        stackTrace: String? = nil,
        context: [String: String]? = nil
    ) async {
        do {
            let userId = await MainActor.run { AuthService.shared.userId }
            let token = await AuthService.shared.getAccessToken()

            guard let token = token else {
                print("[ErrorReport] No auth token, skip submit")
                return
            }

            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            let osVersion = await MainActor.run { UIDevice.current.systemVersion }

            // 构建请求 body
            var body: [String: Any] = [
                "error_type": errorType,
                "message": message,
                "app_version": "\(appVersion)(\(buildNumber))",
                "platform": "ios",
                "os_version": "iOS \(osVersion)",
            ]
            if let userId = userId { body["user_id"] = userId }
            if let errorCode = errorCode { body["error_code"] = errorCode }
            if let stackTrace = stackTrace { body["stack_trace"] = stackTrace }

            // context 作为 JSONB
            var ctxDict: [String: String] = context ?? [:]
            ctxDict["build"] = buildNumber
            body["context"] = ctxDict

            let url = URL(string: "\(SupabaseConfig.url.absoluteString)/rest/v1/error_logs")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode < 300 {
                print("[ErrorReport] Submitted successfully")
            } else {
                print("[ErrorReport] Submit failed: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
        } catch {
            print("[ErrorReport] Submit error: \(error.localizedDescription)")
        }
    }
}

import Foundation
import UIKit
import UserNotifications

/// iOS 本地推送通知服务
/// 用于 Cron 任务完成后发送通知
/// 实现 UNUserNotificationCenterDelegate 确保前台也能显示横幅 + 点击跳转
class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    private let deviceTokenKey = "sage_apns_device_token"

    private override init() {
        super.init()
        // 设置自己为 delegate，前台时也能显示通知横幅
        UNUserNotificationCenter.current().delegate = self
    }

    /// 请求通知权限
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("[Notification] Permission error: \(error)")
            }
            print("[Notification] Permission granted: \(granted)")
            DispatchQueue.main.async {
                // APNs token registration is independent from alert permission.
                // Register anyway so the backend can keep device reachability observable.
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    func handleRegisteredDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02.2hhx", $0) }.joined()
        UserDefaults.standard.set(token, forKey: deviceTokenKey)
        Task { await syncDeviceTokenIfPossible() }
    }

    func handleRegistrationError(_ error: Error) {
        print("[Notification] Remote registration failed: \(error.localizedDescription)")
    }

    func syncDeviceTokenIfPossible() async {
        guard let token = UserDefaults.standard.string(forKey: deviceTokenKey), !token.isEmpty else { return }
        do {
            try await APIClient.shared.registerDeviceToken(token, environment: apnsEnvironment)
            print("[Notification] APNs device token synced")
        } catch {
            print("[Notification] APNs device token sync skipped: \(error.localizedDescription)")
        }
    }

    /// 发送本地通知（Cron 任务完成）
    /// sessionId 嵌入 userInfo 用于点击跳转
    func sendCronJobNotification(jobName: String, result: String?, sessionId: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "定时任务完成"
        content.body = "\(jobName) 已执行完成"
        if let result = result {
            content.body += "\n\(String(result.prefix(100)))"
        }
        content.sound = .default
        content.badge = 1

        // 嵌入 sessionId 供点击时跳转
        if let sessionId {
            content.userInfo = ["sessionId": sessionId]
        }

        let request = UNNotificationRequest(
            identifier: "cron_\(sessionId ?? UUID().uuidString)",
            content: content,
            trigger: nil // 立即发送
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[Notification] Failed to send: \(error)")
            }
        }
    }

    /// 发送普通通知
    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    /// 一期演示用：条件单模拟触发后发送本地通知，点击后进入对应确认下单页。
    func sendPriceWatchTriggeredNotification(noteId: String, symbol: String, conditionText: String?, intent: String) {
        let content = UNMutableNotificationContent()
        content.title = "价格条件已触发"
        let subject = symbol.isEmpty ? "标的" : symbol
        let condition = conditionText ?? "到达目标价"
        let action = intent.isEmpty ? "操作" : intent
        content.body = "\(subject)\(condition)，是否\(action)？"
        content.sound = .default
        content.badge = 1
        content.userInfo = [
            "noteId": noteId,
            "action": "confirm_order"
        ]

        let request = UNNotificationRequest(
            identifier: "price_watch_\(noteId)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[Notification] Failed to send price watch notification: \(error.localizedDescription)")
            }
        }
    }

    /// 清除角标
    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// 前台时也显示通知横幅（默认前台不显示）
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    /// 用户点击通知 → 提取 payload → 发 NSNotification 让 UI 跳转
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let noteId = userInfo["noteId"] as? String,
           (userInfo["action"] as? String) == "confirm_order" {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigateToOrderNote,
                    object: nil,
                    userInfo: ["noteId": noteId]
                )
            }
        } else if let sessionId = userInfo["sessionId"] as? String {
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .navigateToSession,
                    object: nil,
                    userInfo: ["sessionId": sessionId]
                )
            }
        }
        completionHandler()
    }

    private var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        NotificationService.shared.handleRegisteredDeviceToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NotificationService.shared.handleRegistrationError(error)
    }
}

// MARK: - Notification names

extension Notification.Name {
    /// 点击推送通知时触发，userInfo 含 sessionId
    static let navigateToSession = Notification.Name("sage_navigate_to_session")
    /// 点击条件单触发 push 时打开对应确认下单页，userInfo 含 noteId
    static let navigateToOrderNote = Notification.Name("sage_navigate_to_order_note")
}

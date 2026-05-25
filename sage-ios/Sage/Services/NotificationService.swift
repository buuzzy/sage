import Foundation
import UserNotifications

/// iOS 本地推送通知服务
/// 用于 Cron 任务完成后发送通知
/// 实现 UNUserNotificationCenterDelegate 确保前台也能显示横幅 + 点击跳转
class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

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

    /// 用户点击通知 → 提取 sessionId → 发 NSNotification 让 UI 跳转
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let sessionId = userInfo["sessionId"] as? String {
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
}

// MARK: - Notification names

extension Notification.Name {
    /// 点击推送通知时触发，userInfo 含 sessionId
    static let navigateToSession = Notification.Name("sage_navigate_to_session")
}

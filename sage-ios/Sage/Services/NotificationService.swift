import Foundation
import UserNotifications

/// iOS 本地推送通知服务
/// 用于 Cron 任务完成后发送通知
/// 实现 UNUserNotificationCenterDelegate 确保前台也能显示横幅
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
    func sendCronJobNotification(jobName: String, result: String?) {
        let content = UNMutableNotificationContent()
        content.title = "定时任务完成"
        content.body = "\(jobName) 已执行完成"
        if let result = result {
            content.body += "\n\(String(result.prefix(100)))"
        }
        content.sound = .default
        content.badge = 1

        let request = UNNotificationRequest(
            identifier: "cron_\(UUID().uuidString)",
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
}

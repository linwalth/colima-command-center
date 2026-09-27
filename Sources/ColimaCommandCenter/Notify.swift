import Foundation
import UserNotifications

/// Wraps UNUserNotificationCenter. Named `Notifier` to avoid shadowing
/// Foundation's NotificationCenter.
final class Notifier {
    static let shared = Notifier()
    private init() {}

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Stable identifier so repeated posts replace rather than stack.
        let req = UNNotificationRequest(identifier: "colima.notification", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}

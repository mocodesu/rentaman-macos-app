import Foundation
import UserNotifications
import AppKit

/// Foreground notification delegate. Ensures banners appear even when
/// the app is frontmost, and handles tap actions.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    private override init() {}

    // Foreground presentation — show banner + sound + add to Notification Center.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // User tapped a notification.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Bring the app forward.
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }

        // Future hook: route to the specific bill using response.notification.request.content.userInfo["billId"].
    }
}
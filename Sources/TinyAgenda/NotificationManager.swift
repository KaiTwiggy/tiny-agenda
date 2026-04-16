import AppKit
import TinyAgendaCore
import Foundation
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    /// `UNUserNotificationCenter` crashes when the process has no real `.app` bundle (e.g. `swift run`).
    /// Notifications only work when launched from `TinyAgenda.app` (see `scripts/build-app.sh`).
    static var isAvailable: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    private var didRequest = false

    func requestAuthorizationIfNeeded() {
        guard Self.isAvailable else { return }
        guard !didRequest else { return }
        didRequest = true
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func cancelAllPending() async {
        guard Self.isAvailable else { return }
        let s = await UNUserNotificationCenter.current().notificationSettings()
        if s.authorizationStatus == .denied { return }
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    func rescheduleNotifications(
        events: [CalendarEvent],
        leadMinutes: [Int],
        quietHoursEnabled: Bool,
        quietStartHour: Int,
        quietEndHour: Int,
        toastNotificationsEnabled: Bool
    ) async {
        guard Self.isAvailable else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .denied { return }

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        guard toastNotificationsEnabled else { return }
        let now = Date()
        let leads = Set(leadMinutes.filter { $0 > 0 }).sorted()
        guard !leads.isEmpty else { return }

        for event in events where event.start > now {
            for minutes in leads {
                let fire = event.start.addingTimeInterval(-Double(minutes * 60))
                guard fire > now else { continue }
                if quietHoursEnabled,
                   isInQuietHours(fire, startHour: quietStartHour, endHour: quietEndHour)
                {
                    continue
                }
                let content = UNMutableNotificationContent()
                content.title = event.shortTitle
                content.body = "Starts in \(minutes) minutes"
                Self.attachToastIcon(to: content)
                if let u = event.joinURL {
                    content.userInfo["openURL"] = u.absoluteString
                }
                let id = "cal-\(event.id)-\(minutes)"
                let trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: fire.timeIntervalSinceNow,
                    repeats: false
                )
                let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                do {
                    try await UNUserNotificationCenter.current().add(req)
                } catch {
                    continue
                }
            }
        }
    }

    /// Uses `ToastIcon.png` (generated with AppIcon) so banners show the same artwork as the app icon.
    private static func attachToastIcon(to content: UNMutableNotificationContent) {
        guard let url = Bundle.main.url(forResource: "ToastIcon", withExtension: "png") else { return }
        let opts: [String: Any] = [
            UNNotificationAttachmentOptionsTypeHintKey: UTType.png.identifier,
        ]
        guard let att = try? UNNotificationAttachment(identifier: "tinyagenda.icon", url: url, options: opts) else {
            return
        }
        content.attachments = [att]
    }

    private func isInQuietHours(_ date: Date, startHour: Int, endHour: Int) -> Bool {
        let h = Calendar.current.component(.hour, from: date)
        if startHour == endHour { return false }
        if startHour < endHour {
            return h >= startHour && h < endHour
        }
        return h >= startHour || h < endHour
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let s = userInfo["openURL"] as? String, let url = URL(string: s) {
            Task { @MainActor in
                NSWorkspace.shared.open(url)
            }
        }
        completionHandler()
    }
}

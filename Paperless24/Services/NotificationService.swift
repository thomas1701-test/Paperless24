import Foundation
import UserNotifications
import BackgroundTasks

/// Lokale Benachrichtigungen über neue Posteingangs-Dokumente, gespeist von einem
/// periodischen Hintergrund-Task (kein Server-Push nötig).
enum NotificationService {
    static let refreshTaskId = "com.Thomas.paperless.refresh"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? false
    }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    /// Beim App-Start aufrufen (vor Ende des Launch).
    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            handleRefresh(refresh)
        }
    }

    static func scheduleRefresh() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh() // nächsten Lauf planen
        guard isEnabled else { task.setTaskCompleted(success: true); return }

        let work = Task { @MainActor in
            if let count = await AppStore.shared?.checkInboxForNotification(), count > 0 {
                await postInboxNotification(count: count)
            }
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    static func postInboxNotification(count: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "Neue Dokumente"
        content.body = "Du hast \(count) Dokument(e) im Posteingang."
        content.sound = .default
        content.badge = NSNumber(value: count)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

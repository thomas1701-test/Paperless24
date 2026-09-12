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
            await checkDeadlines()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Meldet Fristen, die in den nächsten Tagen fällig werden.
    ///
    /// Bewusst nur *bestätigte* Fristen aus dem eigenen Feld — nicht das, was die Erkennung
    /// irgendwo im Text gefunden hat. Eine Benachrichtigung über einen Falschtreffer wäre die
    /// beste Möglichkeit, sich das Fristen-Radar abschalten zu lassen.
    @MainActor
    static func checkDeadlines() async {
        guard isEnabled, let store = AppStore.shared, store.isDeadlineRadarEnabled else { return }
        let due = await store.upcomingDeadlines(withinDays: 7)
        let overdue = (await store.loadDeadlines()).filter(\.isOverdue)
        guard !due.isEmpty || !overdue.isEmpty else { return }

        // Einmal am Tag genügt.
        let key = "lastDeadlineNotification"
        let today = Calendar.current.startOfDay(for: Date())
        if let last = UserDefaults.standard.object(forKey: key) as? Date,
           Calendar.current.startOfDay(for: last) == today { return }
        UserDefaults.standard.set(Date(), forKey: key)

        let content = UNMutableNotificationContent()
        content.title = overdue.isEmpty ? "Fristen stehen an" : "Frist überschritten"
        if !overdue.isEmpty {
            let first = overdue[0].document.title
            content.body = overdue.count == 1
                ? "\(first) ist überfällig."
                : "\(first) und \(overdue.count - 1) weitere sind überfällig."
        } else {
            let first = due[0]
            content.body = due.count == 1
                ? "\(first.document.title): fällig in \(first.daysRemaining) Tag(en)."
                : "\(first.document.title) und \(due.count - 1) weitere werden diese Woche fällig."
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
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

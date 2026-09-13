import Foundation
import UserNotifications
import BackgroundTasks

/// Lokale Benachrichtigungen über neue Posteingangs-Dokumente, gespeist von einem
/// periodischen Hintergrund-Task (kein Server-Push nötig).
/// Datenzugriff für den Hintergrundlauf — ohne `AppStore` und ohne Oberfläche.
enum BackgroundData {

    /// Der Posteingangsstand beim letzten Blick — aus der App oder aus dem Hintergrund.
    static let lastInboxKey = "lastNotifiedInbox"

    static func activeAPI() -> PaperlessAPI? {
        let accounts = AccountService.load()
        guard let id = AccountService.activeId(),
              let account = accounts.first(where: { $0.id == id }),
              !account.serverUrl.isEmpty,
              let token = KeychainService.loadToken(for: account.serverUrl, username: account.username)
        else { return nil }
        return PaperlessAPI(serverUrl: account.serverUrl, token: token)
    }

    /// Die Zahl im Posteingang, wenn sie seit dem letzten Blick gestiegen ist.
    static func newInboxCount(api: PaperlessAPI) async -> Int? {
        guard let stats = try? await api.fetchStatistics() else { return nil }
        let current = stats.documentsInbox ?? 0
        let last = UserDefaults.standard.integer(forKey: lastInboxKey)
        UserDefaults.standard.set(current, forKey: lastInboxKey)
        return current > last ? current : nil
    }

    /// Bestätigte Fristen aus dem eigenen Feld „Fälligkeit" (oder dem eingestellten Feld).
    static func deadlines(api: PaperlessAPI) async -> [DeadlineEntry] {
        let storedId = UserDefaults.standard.integer(forKey: "deadlineFieldId")
        var fieldId: Int? = storedId > 0 ? storedId : nil
        if fieldId == nil, let fields = try? await api.fetchCustomFields() {
            fieldId = fields.first {
                $0.safeName.localizedCaseInsensitiveCompare(AppStore.deadlineFieldName) == .orderedSame
            }?.id
        }
        guard let fieldId else { return [] }
        var query = DocumentQuery()
        query.customFieldID = fieldId
        guard let page = try? await api.fetchDocuments(query: query, page: 1, pageSize: 250,
                                                       ordering: "-created,-id") else { return [] }
        return AppStore.deadlineEntries(from: page.documents, fieldId: fieldId)
    }
}

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

        // Ohne `AppStore`: Startet iOS die App für diesen Lauf im Hintergrund, entsteht keine
        // Szene und damit auch kein Store. Vorher hing alles an `AppStore.shared` — der war dann
        // `nil`, und Benachrichtigungen kamen nur, solange die App ohnehin noch im Speicher lag.
        let work = Task {
            guard let api = BackgroundData.activeAPI() else {
                task.setTaskCompleted(success: true)
                return
            }
            if let count = await BackgroundData.newInboxCount(api: api), count > 0 {
                await postInboxNotification(count: count)
            }
            await checkDeadlines(api: api)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }

    /// Das Abzeichen am App-Symbol zurücksetzen — beim Öffnen der App. Vorher wurde es gesetzt,
    /// aber nie wieder entfernt.
    static func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Meldet Fristen, die in den nächsten Tagen fällig werden.
    ///
    /// Bewusst nur *bestätigte* Fristen aus dem eigenen Feld — nicht das, was die Erkennung
    /// irgendwo im Text gefunden hat. Eine Benachrichtigung über einen Falschtreffer wäre die
    /// beste Möglichkeit, sich das Fristen-Radar abschalten zu lassen.
    static func checkDeadlines(api: PaperlessAPI) async {
        let radarEnabled = UserDefaults.standard.object(forKey: "deadlineRadarEnabled") as? Bool ?? false
        guard isEnabled, radarEnabled else { return }
        let all = await BackgroundData.deadlines(api: api)
        let due = all.filter { $0.daysRemaining >= 0 && $0.daysRemaining <= 7 }
        let overdue = all.filter(\.isOverdue)
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
        guard !Task.isCancelled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Neue Dokumente"
        content.body = "Du hast \(count) Dokument(e) im Posteingang."
        content.sound = .default
        content.badge = NSNumber(value: count)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

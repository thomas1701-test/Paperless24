import Foundation

struct WidgetDocument: Codable {
    let id: Int
    let title: String
    let created: String
    let correspondent: String?
}

enum WidgetDataService {
    private static let suiteName = "group.com.Thomas.paperless"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    static func write(
        docs: [WidgetDocument],
        inboxCount: Int,
        totalCount: Int,
        lastSync: Date,
        enabled: Bool
    ) {
        guard let d = defaults else { return }
        d.set(enabled, forKey: "widget_enabled")
        d.set(inboxCount, forKey: "widget_inbox_count")
        d.set(totalCount, forKey: "widget_total_count")
        d.set(lastSync.timeIntervalSince1970, forKey: "widget_last_sync")
        d.set(try? JSONEncoder().encode(docs), forKey: "widget_documents")
    }

    static func readDocuments() -> [WidgetDocument] {
        guard let d = defaults,
              let data = d.data(forKey: "widget_documents") else { return [] }
        return (try? JSONDecoder().decode([WidgetDocument].self, from: data)) ?? []
    }

    static func readStats() -> (inbox: Int, total: Int, lastSync: Date?) {
        guard let d = defaults else { return (0, 0, nil) }
        let inbox = d.integer(forKey: "widget_inbox_count")
        let total = d.integer(forKey: "widget_total_count")
        let ts = d.double(forKey: "widget_last_sync")
        let lastSync = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        return (inbox, total, lastSync)
    }

    static func isEnabled() -> Bool {
        defaults?.bool(forKey: "widget_enabled") ?? true
    }

    static func readMode() -> String {
        defaults?.string(forKey: "widget_mode") ?? "documents"
    }
}

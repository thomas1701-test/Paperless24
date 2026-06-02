import Foundation

/// Spiegelt ausgewählte App-Einstellungen über `NSUbiquitousKeyValueStore` zwischen
/// den Geräten des Nutzers. Ohne aktive iCloud-Capability ein stiller No-Op.
enum SettingsSyncService {
    private static let keys = [
        "appearanceMode", "layoutStyle", "appLanguage",
        "pageSize", "gridItemSize", "aiEnabled", "notificationsEnabled",
        "fristenRadarEnabled", "batchScanEnabled", "translationEnabled",
        "senderName", "senderAddress"
    ]

    static func start() {
        let cloud = NSUbiquitousKeyValueStore.default
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { _ in pullFromCloud() }
        cloud.synchronize()
        pullFromCloud()
        pushLocal()
    }

    /// Lokale Werte in die Cloud schreiben.
    static func pushLocal() {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard
        for key in keys where local.object(forKey: key) != nil {
            cloud.set(local.object(forKey: key), forKey: key)
        }
        cloud.synchronize()
    }

    /// Cloud-Werte nach lokal übernehmen.
    static func pullFromCloud() {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard
        for key in keys where cloud.object(forKey: key) != nil {
            local.set(cloud.object(forKey: key), forKey: key)
        }
    }
}

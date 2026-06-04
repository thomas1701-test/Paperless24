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
        // Live-Änderungen von anderen Geräten übernehmen (während die App läuft).
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud, queue: .main
        ) { _ in pullFromCloud() }
        cloud.synchronize()
        // Beim Start NICHT blind aus der Cloud überschreiben – sonst gewinnt ein alter
        // Cloud-Wert über die lokale Einstellung. Nur fehlende Keys (Erstinstallation) holen.
        pullMissingFromCloud()
        pushLocal()
    }

    /// Lokale Werte in die Cloud schreiben (lokal = Quelle der Wahrheit).
    static func pushLocal() {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard
        for key in keys where local.object(forKey: key) != nil {
            cloud.set(local.object(forKey: key), forKey: key)
        }
        cloud.synchronize()
    }

    /// Nur Keys übernehmen, die lokal noch nicht existieren (Erstinstallation auf neuem Gerät).
    static func pullMissingFromCloud() {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard
        for key in keys where local.object(forKey: key) == nil && cloud.object(forKey: key) != nil {
            local.set(cloud.object(forKey: key), forKey: key)
        }
    }

    /// Externe Live-Änderung: Cloud → lokal übernehmen.
    static func pullFromCloud() {
        let cloud = NSUbiquitousKeyValueStore.default
        let local = UserDefaults.standard
        for key in keys where cloud.object(forKey: key) != nil {
            local.set(cloud.object(forKey: key), forKey: key)
        }
    }
}

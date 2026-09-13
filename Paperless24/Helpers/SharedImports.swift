import Foundation

/// Dateien, die Share-Extension oder Kurzbefehl in der App Group abgelegt haben.
///
/// Jede Datei liegt unter eigenem Namen in `SharedImports/` (Datei + `<name>.name` mit dem
/// ursprünglichen Dateinamen). Vorher gab es genau einen Platz, `shared_import.data` — eine
/// zweite Freigabe überschrieb die erste, bevor die App sie abholen konnte.
enum SharedImports {

    static func directory() -> URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppConstants.appGroupId
        ) else { return nil }
        let dir = container.appendingPathComponent("SharedImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Legt eine Datei zum Abholen ab (Kurzbefehl „Dokument hochladen").
    @discardableResult
    static func stage(_ data: Data, filename: String, in dir: URL? = directory()) -> Bool {
        guard let dir else { return false }
        let id = String(format: "%.6f", Date().timeIntervalSince1970) + "-" + UUID().uuidString
        do {
            try data.write(to: dir.appendingPathComponent(id), options: [.atomic, .completeFileProtectionUnlessOpen])
            try Data(filename.utf8).write(to: dir.appendingPathComponent(id + ".name"), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Nimmt die älteste abgelegte Datei heraus — oder die aus früheren Versionen
    /// (`shared_import.data` + `shared_filename`).
    static func takeNext(in dir: URL? = directory()) -> (data: Data, filename: String)? {
        if let legacy = takeLegacy() { return legacy }
        guard let dir,
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        for id in names.filter({ !$0.hasSuffix(".name") }).sorted() {
            let fileURL = dir.appendingPathComponent(id)
            let nameURL = dir.appendingPathComponent(id + ".name")
            // Ohne Namensdatei schreibt die Erweiterung womöglich noch — später wieder versuchen.
            guard let nameData = try? Data(contentsOf: nameURL) else { continue }
            defer {
                try? FileManager.default.removeItem(at: fileURL)
                try? FileManager.default.removeItem(at: nameURL)
            }
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let filename = String(decoding: nameData, as: UTF8.self)
            return (data, filename.isEmpty ? "Import.pdf" : filename)
        }
        return nil
    }

    private static func takeLegacy() -> (data: Data, filename: String)? {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupId),
              let filename = defaults.string(forKey: "shared_filename"),
              let container = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: AppConstants.appGroupId
              ) else { return nil }
        let fileURL = container.appendingPathComponent("shared_import.data")
        defer {
            defaults.removeObject(forKey: "shared_filename")
            try? FileManager.default.removeItem(at: fileURL)
        }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return (data, filename)
    }
}

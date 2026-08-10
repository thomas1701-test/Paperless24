import Foundation

enum PersistenceService {
    private static func url(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    /// Eine serielle Queue für alle Schreibvorgänge.
    ///
    /// `saveToDisk()` stößt acht Schreibvorgänge auf einmal an, und das bei jeder Bearbeitung.
    /// Auf einer nebenläufigen Queue überholten die sich gegenseitig; zusammen mit dem
    /// nicht-atomaren `write(to:)` konnte eine halb geschriebene Datei zurückbleiben. Beim
    /// nächsten Start schlug das Dekodieren fehl und `?? []` machte daraus stillschweigend
    /// eine leere Liste — die Warteschlange war weg.
    private static let ioQueue = DispatchQueue(label: "de.tedi.paperless.persistence", qos: .utility)

    /// Atomar schreiben und mit Dateischutz versehen. `completeFileProtectionUnlessOpen`
    /// hält die Dokumentdaten verschlüsselt, blockiert aber keine bereits geöffnete Datei.
    private static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUnlessOpen]

    // MARK: - JSON Data (account-agnostic, für globale Einstellungen — nicht mehr verwendet)

    static func save<T: Encodable>(_ value: T, to filename: String) {
        save(value, toURL: url(filename))
    }

    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        load(type, fromURL: url(filename))
    }

    // MARK: - Per-Account JSON Data

    static func accountDataURL(for accountId: UUID, filename: String) -> URL {
        let dir = url("accounts/\(accountId.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    static func save<T: Encodable>(_ value: T, toURL fileURL: URL) {
        // Kodieren beim Aufrufer, nicht in der Queue: `value` ist dann bereits ein fertiger
        // Byte-Puffer und der Wert kann sich nicht mehr unter dem Schreibvorgang ändern.
        guard let data = try? JSONEncoder().encode(value) else { return }
        ioQueue.async {
            try? data.write(to: fileURL, options: writeOptions)
        }
    }

    /// Schreibt eine bereits fertige Datei (PDF, Bild) mit denselben Garantien.
    static func writeFile(_ data: Data, to fileURL: URL) throws {
        try data.write(to: fileURL, options: writeOptions)
    }

    static func load<T: Decodable>(_ type: T.Type, fromURL fileURL: URL) -> T? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Per-Account PDF Files

    static func docFileURL(for docId: Int, accountId: UUID) -> URL {
        let dir = url("accounts/\(accountId.uuidString)/docs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("doc_\(docId).pdf")
    }

    static func fileExists(docId: Int, accountId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: docFileURL(for: docId, accountId: accountId).path)
    }

    static func deleteDocFile(docId: Int, accountId: UUID) {
        try? FileManager.default.removeItem(at: docFileURL(for: docId, accountId: accountId))
    }

    static func deleteAccountFiles(accountId: UUID) {
        try? FileManager.default.removeItem(at: url("accounts/\(accountId.uuidString)"))
    }

    static func calculateStorage(accountId: UUID) -> (sizeString: String, cachedCount: Int) {
        var totalBytes: Int64 = 0
        var count = 0
        let docsDir = url("accounts/\(accountId.uuidString)/docs")
        if let files = try? FileManager.default.contentsOfDirectory(
            at: docsDir, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for file in files {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalBytes += Int64(size)
                }
                if file.lastPathComponent.hasPrefix("doc_") { count += 1 }
            }
        }
        // Nur die Miniaturansichten dieses Kontos. Vorher lief hier der komplette Caches-Ordner
        // durch — inklusive der Vorschauen aller anderen Konten und allem, was das System dort
        // sonst ablegt. Die angezeigte Größe gehörte damit nicht zum gewählten Konto.
        let thumbsDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Thumbnails/\(accountId.uuidString)")
        if let thumbs = try? FileManager.default.contentsOfDirectory(
            at: thumbsDir, includingPropertiesForKeys: [.fileSizeKey]
        ) {
            for file in thumbs {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalBytes += Int64(size)
                }
            }
        }
        return (String(format: "%.2f MB", Double(totalBytes) / 1_048_576), count)
    }

    // MARK: - Migration

    static func legacyDataURL(_ filename: String) -> URL {
        url(filename)
    }

    static func migrateLegacyDocFiles(to accountId: UUID) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let files = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil
              ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("doc_") && file.pathExtension == "pdf" {
            let stem = file.deletingPathExtension().lastPathComponent.dropFirst(4) // "doc_123" → "123"
            if let id = Int(stem) {
                let dest = docFileURL(for: id, accountId: accountId)
                try? FileManager.default.moveItem(at: file, to: dest)
            }
        }
    }

    // MARK: - Global

    static func clearAll() {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .forEach { try? FileManager.default.removeItem(at: $0) }
    }
}

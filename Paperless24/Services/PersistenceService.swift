import Foundation

enum PersistenceService {
    private static func url(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    // MARK: - JSON Data (account-agnostic, für globale Einstellungen — nicht mehr verwendet)

    static func save<T: Encodable>(_ value: T, to filename: String) {
        DispatchQueue.global(qos: .background).async {
            try? JSONEncoder().encode(value).write(to: url(filename))
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        guard let data = try? Data(contentsOf: url(filename)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Per-Account JSON Data

    static func accountDataURL(for accountId: UUID, filename: String) -> URL {
        let dir = url("accounts/\(accountId.uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(filename)
    }

    static func save<T: Encodable>(_ value: T, toURL fileURL: URL) {
        DispatchQueue.global(qos: .background).async {
            try? JSONEncoder().encode(value).write(to: fileURL)
        }
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
        if let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let subs = try? FileManager.default.subpathsOfDirectory(atPath: cacheDir.path) {
            for path in subs {
                if let attrs = try? FileManager.default.attributesOfItem(
                    atPath: cacheDir.appendingPathComponent(path).path
                ), let size = attrs[.size] as? Int64 {
                    totalBytes += size
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

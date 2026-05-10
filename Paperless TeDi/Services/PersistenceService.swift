import Foundation

enum PersistenceService {
    private static func url(_ name: String) -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name)
    }

    static func save<T: Encodable>(_ value: T, to filename: String) {
        DispatchQueue.global(qos: .background).async {
            try? JSONEncoder().encode(value).write(to: url(filename))
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        guard let data = try? Data(contentsOf: url(filename)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func docFileURL(for docId: Int) -> URL {
        url("doc_\(docId).pdf")
    }

    static func fileExists(docId: Int) -> Bool {
        FileManager.default.fileExists(atPath: docFileURL(for: docId).path)
    }

    static func deleteDocFile(docId: Int) {
        try? FileManager.default.removeItem(at: docFileURL(for: docId))
    }

    static func clearAll() {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .forEach { try? FileManager.default.removeItem(at: $0) }
    }

    static func calculateStorage() -> (sizeString: String, cachedCount: Int) {
        var totalBytes: Int64 = 0
        var count = 0

        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
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
                if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheDir.appendingPathComponent(path).path),
                   let size = attrs[.size] as? Int64 {
                    totalBytes += size
                }
            }
        }

        return (String(format: "%.2f MB", Double(totalBytes) / 1_048_576), count)
    }
}

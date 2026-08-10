import UIKit

/// Miniaturansichten, im Speicher und auf der Platte.
///
/// Der Cache ist nach Konto getrennt. Dokument-IDs sind nur innerhalb eines Servers eindeutig —
/// mit einem gemeinsamen Ablageort zeigte Dokument 42 von Server B die Vorschau von Dokument 42
/// aus Server A. Das ist nicht nur eine falsche Kachel, sondern ein Blick in ein fremdes Archiv.
class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let rootDirectory: URL
    /// `nil`, solange kein Konto aktiv ist (frische Installation). Dann wird nichts abgelegt.
    private var accountId: UUID?

    init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        rootDirectory = urls[0].appendingPathComponent("Thumbnails")
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    /// Beim Start und bei jedem Kontowechsel aufrufen. Leert den Speicher-Cache, damit keine
    /// Vorschau des vorherigen Kontos stehen bleibt.
    func setAccount(_ id: UUID?) {
        guard id != accountId else { return }
        accountId = id
        cache.removeAllObjects()
        if let dir = currentDirectory {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private var currentDirectory: URL? {
        guard let accountId else { return nil }
        return rootDirectory.appendingPathComponent(accountId.uuidString)
    }

    private func key(_ id: Int) -> NSString {
        NSString(string: "\(accountId?.uuidString ?? "none")-\(id)")
    }

    func getImage(for id: Int) -> UIImage? {
        if let cached = cache.object(forKey: key(id)) { return cached }
        guard let dir = currentDirectory else { return nil }
        let fileURL = dir.appendingPathComponent("\(id).jpg")
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            cache.setObject(image, forKey: key(id))
            return image
        }
        return nil
    }

    func getFilePath(for id: Int) -> URL {
        (currentDirectory ?? rootDirectory).appendingPathComponent("\(id).jpg")
    }

    /// Die abgelegte Miniaturansicht als Rohdaten.
    ///
    /// Der Spotlight-Index bekommt die Bytes direkt statt eines Dateipfads: einen Pfad müsste
    /// der Indexdienst selbst öffnen, und das scheitert je nach Dateischutz und Zeitpunkt.
    func thumbnailData(for id: Int) -> Data? {
        guard let dir = currentDirectory else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent("\(id).jpg"))
    }

    func saveImage(_ image: UIImage, for id: Int) {
        cache.setObject(image, forKey: key(id))
        guard let dir = currentDirectory else { return }
        DispatchQueue.global(qos: .background).async {
            let fileURL = dir.appendingPathComponent("\(id).jpg")
            if let data = image.jpegData(compressionQuality: 0.7) {
                // Bewusst `untilFirstUserAuthentication` und nicht schärfer: den Spotlight-Index
                // baut ein Systemdienst außerhalb der App, der die Datei zu einem beliebigen
                // Zeitpunkt öffnet. Mit `completeUnlessOpen` scheitert er, sobald der Bildschirm
                // gesperrt ist — und lässt dann den ganzen Stapel fallen.
                try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
    }

    /// Leert die Miniaturansichten des aktiven Kontos.
    func clearCache() {
        cache.removeAllObjects()
        guard let dir = currentDirectory else { return }
        try? fileManager.removeItem(at: dir)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// Entfernt die Miniaturansichten eines gelöschten Kontos.
    func deleteAccount(_ id: UUID) {
        if id == accountId { cache.removeAllObjects() }
        try? fileManager.removeItem(at: rootDirectory.appendingPathComponent(id.uuidString))
    }

    /// Leert die Miniaturansichten aller Konten (Abmelden).
    func clearAll() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: rootDirectory)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }
}

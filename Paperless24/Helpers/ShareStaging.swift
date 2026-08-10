import Foundation

/// Zwischenablage für Dateien, die an das Teilen-Blatt übergeben werden.
///
/// Das Teilen-Blatt braucht eine Datei auf der Platte. Bisher landete die direkt im
/// Temp-Verzeichnis, benannt nach dem Dokumenttitel — zwei Dokumente mit gleichem Titel
/// überschrieben sich gegenseitig, und aufgeräumt wurde nie. Jede Freigabe bekommt hier
/// ihren eigenen Unterordner, und beim nächsten Mal fliegen die alten raus.
enum ShareStaging {

    private static var root: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
    }

    /// Legt die Daten unter einem gefahrlosen Dateinamen ab und liefert die URL.
    static func stage(_ data: Data, filename: String) -> URL? {
        let dir = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(safeFilename(filename))
            // Kein Dateischutz: das Teilen-Blatt liest die Datei unter Umständen erst,
            // nachdem der Bildschirm gesperrt wurde.
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Entfernt alle früher abgelegten Freigaben.
    static func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Dokumenttitel sind freier Text — Schrägstriche, Doppelpunkte und führende Punkte
    /// haben in einem Dateinamen nichts verloren.
    static func safeFilename(_ raw: String, fallback: String = "Dokument.pdf") -> String {
        var name = raw
            .components(separatedBy: CharacterSet(charactersIn: "/\\:\0"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() }
        // Bestand der Titel nur aus Trennzeichen, bleiben jetzt lauter Striche übrig — die
        // ergeben keinen brauchbaren Dateinamen, dann greift der Rückfallname.
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        // HFS+/APFS erlauben 255 Zeichen; darunter bleiben, ohne die Endung zu verlieren.
        if name.count > 100 { name = String(name.prefix(100)) }
        return name.isEmpty ? fallback : name
    }
}

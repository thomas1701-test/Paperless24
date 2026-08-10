import Foundation

/// Ein Ort für alle Datumsformate der paperless-ngx-API.
///
/// Die Formatter sind bewusst statisch: `DateFormatter` und `ISO8601DateFormatter` sind teuer
/// im Aufbau, und `dateObject` wird beim Filtern und Sortieren für jedes Dokument aufgerufen.
/// Nach der Konfiguration werden sie nur noch gelesen, das ist threadsicher.
enum DateFormatting {

    // MARK: - Schreiben

    /// `yyyy-MM-dd` in der lokalen Zeitzone.
    ///
    /// `created` ist seit API-Version 9 ein reines Datum ohne Uhrzeit. Ein UTC-Zeitstempel
    /// (`ISO8601DateFormatter().string(from:)`) verschiebt es östlich von Greenwich um einen
    /// Tag nach hinten: aus dem 10.08. um 00:00 MESZ wird `2026-08-09T22:00:00Z`, und der
    /// Server speichert den 09.08. Ältere Server nehmen das reine Datum ebenfalls an.
    private static let apiDateWriter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Formatiert ein Datum so, wie es die API im Feld `created` erwartet.
    static func apiDate(_ date: Date) -> String { apiDateWriter.string(from: date) }

    // MARK: - Lesen

    private static let isoWithFractionalSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoInternetDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dateOnlyReader: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Liest ein Datum aus der API in allen drei Schreibweisen, die ngx über die Versionen
    /// hinweg geliefert hat:
    /// `2026-08-10T12:00:00.123+02:00`, `2026-08-10T12:00:00+02:00` und `2026-08-10`.
    ///
    /// Ein Formatter mit `.withFractionalSeconds` scheitert an einem Zeitstempel *ohne*
    /// Millisekunden — genau daran ist zuvor das Erstelldatum im Bearbeiten-Dialog verloren
    /// gegangen. Deshalb hier immer alle drei Varianten der Reihe nach.
    static func parseAPIDate(_ raw: String) -> Date? {
        if raw.isEmpty { return nil }
        if let d = isoWithFractionalSeconds.date(from: raw) { return d }
        if let d = isoInternetDateTime.date(from: raw) { return d }
        return dateOnlyReader.date(from: String(raw.prefix(10)))
    }
}

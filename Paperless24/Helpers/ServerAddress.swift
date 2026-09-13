import Foundation

/// Verbindungsart auf der Anmeldeseite (Schalter „Unverschlüsselt verbinden").
enum ServerScheme: String, CaseIterable, Identifiable {
    case https, http
    var id: String { rawValue }
}

/// Aufbereitung der Serveradresse auf der Anmeldeseite.
///
/// Früher wurde eine Adresse ohne Schema still zu `http://` ergänzt — Passwort und Token
/// gingen unverschlüsselt raus, ohne dass es jemand gewählt hatte. Jetzt gilt `https`;
/// `http` nur mit dem Schalter „Unverschlüsselt verbinden".
enum ServerAddress {
    /// Trennt ein mit eingegebenes Schema ab: `"HTTPS://host"` → `(.https, "host")`.
    static func split(_ raw: String) -> (scheme: ServerScheme?, rest: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        for scheme in ServerScheme.allCases where lower.hasPrefix("\(scheme.rawValue)://") {
            return (scheme, String(trimmed.dropFirst(scheme.rawValue.count + 3)))
        }
        return (nil, trimmed)
    }

    /// Vollständige Adresse aus Schalter und Eingabe. Der Schalter entscheidet — auch wenn
    /// die Eingabe selbst mit `http://` beginnt; abschließende Schrägstriche fallen weg.
    static func compose(scheme: ServerScheme, input: String) -> String {
        var rest = split(input).rest
        while rest.hasSuffix("/") { rest.removeLast() }
        guard !rest.isEmpty else { return "" }
        return "\(scheme.rawValue)://\(rest)"
    }

    /// Vorbelegung beim erneuten Anmelden. Gespeicherte Adressen ohne Schema liefen bisher
    /// über `http` — dabei bleibt es, sonst passte die Anmeldung nicht mehr zum Konto.
    static func initialScheme(for prefill: String) -> ServerScheme {
        let parts = split(prefill)
        if let scheme = parts.scheme { return scheme }
        return parts.rest.isEmpty ? .https : .http
    }

    /// Gespeicherte Schreibweise eines vorhandenen Kontos mit derselben Adresse. Token und
    /// Kopfzeilen hängen an dieser Zeichenkette; eine andere Schreibweise („host" statt
    /// „http://host") legte sonst ein zweites Konto an.
    static func storedSpelling(
        of composed: String, username: String, accounts: [(serverUrl: String, username: String)]
    ) -> String? {
        let base = PaperlessAPI.normalizedBase(composed)
        return accounts.first {
            $0.username == username && PaperlessAPI.normalizedBase($0.serverUrl) == base
        }?.serverUrl
    }
}

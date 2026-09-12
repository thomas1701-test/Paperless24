import Foundation

/// Erkennt regelmäßig wiederkehrende Dokumente und meldet, wenn eines fehlt.
///
/// Gehaltsabrechnung, Stromrechnung, Kontoauszug: Sie kommen monatlich, und ihr Fehlen fällt
/// erst auf, wenn man sie braucht. Genau das ist der „das hätte ich sonst nie gemerkt"-Fall,
/// den ein Archiv leisten kann und ein Ordner nicht.
enum SeriesDetector {

    /// Eine erkannte Serie.
    struct Series: Identifiable {
        /// Sender und Typ bilden die Serie — beides zusammen, weil derselbe Absender mehrere
        /// Serien schicken kann (Rechnung und Vertragsinfo).
        let correspondentId: Int?
        let documentTypeId: Int?
        let name: String
        /// Monate mit Beleg, aufsteigend, als „yyyy-MM".
        let months: [String]
        /// Monate ohne Beleg zwischen dem ersten und dem letzten vorhandenen.
        let missingMonths: [String]
        /// Monate seit dem letzten Beleg (0 = dieser Monat vorhanden).
        let monthsSinceLast: Int

        var id: String { "\(correspondentId ?? -1)-\(documentTypeId ?? -1)" }

        /// Fehlt der letzte Monat oder klafft eine Lücke?
        var hasProblem: Bool { !missingMonths.isEmpty || monthsSinceLast >= 2 }
    }

    /// Mindestzahl an Belegen, ab der von einer Serie auszugehen ist.
    ///
    /// Drei Monate sind das Minimum: Bei zweien wäre jeder zufällige Doppelbeleg eine „Serie",
    /// und jede Lücke danach eine Falschmeldung.
    static let minimumOccurrences = 4

    /// Findet monatliche Serien in den übergebenen Dokumenten.
    static func detect(in documents: [Document], names: [Int: String],
                       typeNames: [Int: String], now: Date = Date()) -> [Series] {
        var groups: [String: [Document]] = [:]
        for doc in documents {
            // Ohne Sender lässt sich keine Serie bilden — dann fehlt das verbindende Merkmal.
            guard doc.correspondent != nil else { continue }
            let key = "\(doc.correspondent ?? -1)-\(doc.documentType ?? -1)"
            groups[key, default: []].append(doc)
        }

        let currentMonth = monthKey(now)
        var result: [Series] = []

        for (_, docs) in groups {
            let months = Set(docs.compactMap { doc -> String? in
                guard doc.created.count >= 7 else { return nil }
                return String(doc.created.prefix(7))
            })
            guard months.count >= minimumOccurrences else { continue }

            let sorted = months.sorted()
            guard let first = sorted.first, let last = sorted.last else { continue }

            // Nur als monatlich werten, wenn die Belege den Zeitraum auch halbwegs füllen.
            // Vier Rechnungen über zehn Jahre sind keine monatliche Serie.
            let span = monthsBetween(first, last) + 1
            guard span > 0, Double(months.count) / Double(span) >= 0.6 else { continue }

            let missing = missingMonths(from: first, to: last, present: months)
            let sinceLast = monthsBetween(last, currentMonth)

            let corrId = docs.first?.correspondent
            let typeId = docs.first?.documentType
            let corrName = corrId.flatMap { names[$0] } ?? "Unbekannt"
            let typeName = typeId.flatMap { typeNames[$0] }
            result.append(Series(
                correspondentId: corrId,
                documentTypeId: typeId,
                name: typeName.map { "\(corrName) · \($0)" } ?? corrName,
                months: sorted,
                missingMonths: missing,
                monthsSinceLast: max(0, sinceLast)
            ))
        }

        // Auffälliges zuerst.
        return result.sorted {
            ($0.hasProblem ? 0 : 1, -$0.monthsSinceLast) < ($1.hasProblem ? 0 : 1, -$1.monthsSinceLast)
        }
    }

    // MARK: - Monatsrechnung

    static func monthKey(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 1)
    }

    /// Monate zwischen zwei Schlüsseln („2026-01", „2026-04" → 3).
    static func monthsBetween(_ from: String, _ to: String) -> Int {
        guard let a = parse(from), let b = parse(to) else { return 0 }
        return (b.year - a.year) * 12 + (b.month - a.month)
    }

    static func missingMonths(from: String, to: String, present: Set<String>) -> [String] {
        guard let start = parse(from), parse(to) != nil else { return [] }
        let count = monthsBetween(from, to)
        guard count > 0 else { return [] }
        var missing: [String] = []
        for offset in 1..<count {
            let total = start.month - 1 + offset
            let key = String(format: "%04d-%02d", start.year + total / 12, total % 12 + 1)
            if !present.contains(key) { missing.append(key) }
        }
        return missing
    }

    private static func parse(_ key: String) -> (year: Int, month: Int)? {
        let parts = key.split(separator: "-")
        guard parts.count >= 2, let year = Int(parts[0]), let month = Int(parts[1]) else { return nil }
        return (year, month)
    }
}

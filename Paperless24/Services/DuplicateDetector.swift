import Foundation

/// Erkennt, ob ein gescanntes Dokument schon im Archiv liegt.
///
/// **Warum keine Textähnlichkeit:** Der erste Versuch (Juni 2026) verglich Wortmengen je
/// Sender und wurde wieder entfernt. Der Grund liegt in der Natur der Dokumente: Zwei
/// Stromrechnungen aus Januar und Februar sind zu über 90 % derselbe Text. Ähnlichkeit
/// unterscheidet Serienbriefe nicht von Dubletten und schlägt deshalb ständig falsch an.
///
/// Diese Fassung sucht stattdessen nach einer **harten Signatur**: Belegnummer, Betrag und
/// Datum. Die trifft entweder genau oder gar nicht — und nur damit lässt sich ein Treffer
/// belastbar als „das hast du schon" anzeigen.
///
/// Die verlässlichste Prüfung macht ohnehin der Server: Der Consumer lehnt ein identisches
/// Dokument beim Verarbeiten ab, und seit dem Verarbeitungsstatus (`ConsumptionTask`) sieht
/// der Nutzer das auch. Diese Prüfung hier greift *vorher* — sie erspart den Upload.
enum DuplicateDetector {

    struct Fingerprint: Equatable {
        /// Rechnungs-, Beleg- oder Kundennummer.
        var referenceNumbers: Set<String> = []
        /// Beträge in Cent, um Rundungs- und Formatfragen zu vermeiden.
        var amounts: Set<Int> = []
        /// Alle im Text gefundenen Datumsangaben.
        var dates: Set<Date> = []

        var isEmpty: Bool { referenceNumbers.isEmpty && amounts.isEmpty && dates.isEmpty }
    }

    struct Match {
        let documentId: Int
        let reason: String
        /// 0…1
        let confidence: Double
    }

    // MARK: - Signatur bilden

    /// Zieht Belegnummern, Beträge und Datumsangaben aus einem Text.
    static func fingerprint(of text: String) -> Fingerprint {
        guard !text.isEmpty else { return Fingerprint() }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        var print = Fingerprint()

        print.referenceNumbers = referenceNumbers(in: flat)
        print.amounts = amounts(in: flat)
        print.dates = Set(DeadlineDetector.dateMatches(in: flat).map(\.date))
        return print
    }

    /// Nummern, die hinter einem Beleg-Schlüsselwort stehen.
    ///
    /// Ohne Schlüsselwort wäre jede Zahlenkolonne eine Belegnummer — Telefonnummern, IBANs und
    /// Postleitzahlen inklusive.
    static func referenceNumbers(in text: String) -> Set<String> {
        let keywords = ["rechnungsnummer", "rechnungs-nr", "rechnung nr", "belegnummer",
                        "beleg-nr", "kundennummer", "kunden-nr", "vertragsnummer",
                        "auftragsnummer", "invoice no", "invoice number", "order number"]
        let lower = text.lowercased()
        var found: Set<String> = []

        for keyword in keywords {
            var searchStart = lower.startIndex
            while let range = lower.range(of: keyword, range: searchStart..<lower.endIndex) {
                searchStart = range.upperBound
                // Bis zu 40 Zeichen nach dem Schlüsselwort nach der Nummer sehen.
                let windowEnd = lower.index(range.upperBound,
                                            offsetBy: 40,
                                            limitedBy: lower.endIndex) ?? lower.endIndex
                let window = String(lower[range.upperBound..<windowEnd])
                if let number = firstIdentifier(in: window) { found.insert(number) }
            }
        }
        return found
    }

    /// Die erste Zeichenfolge, die als Nummer taugt: mindestens vier Zeichen, Ziffern dabei.
    private static func firstIdentifier(in text: String) -> String? {
        // Zeilenumbrüche gehören dazu: Die Nummer steht oft am Zeilenende, und ohne den
        // Umbruch als Trenner klebt das erste Wort der nächsten Zeile daran.
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: ":;,|()[]"))
        for part in text.components(separatedBy: separators) {
            let cleaned = part.trimmingCharacters(in: CharacterSet(charactersIn: ".-/#"))
            guard cleaned.count >= 4,
                  cleaned.contains(where: \.isNumber),
                  cleaned.allSatisfy({ $0.isNumber || $0.isLetter || $0 == "-" || $0 == "/" })
            else { continue }
            return cleaned
        }
        return nil
    }

    /// Beträge in Cent. Erkennt deutsche und englische Schreibweise.
    static func amounts(in text: String) -> Set<Int> {
        var found: Set<Int> = []
        // 1.234,56 / 1234,56 / 1,234.56 / 1234.56 — jeweils mit zwei Nachkommastellen, weil
        // nur dann von einem Geldbetrag auszugehen ist.
        let pattern = #"\b\d{1,3}(?:[.,]\d{3})*[.,]\d{2}\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let r = Range(match.range, in: text) else { continue }
            let raw = String(text[r])
            guard let cents = centsValue(raw), cents > 0 else { continue }
            found.insert(cents)
        }
        return found
    }

    static func centsValue(_ raw: String) -> Int? {
        // Das *letzte* Trennzeichen trennt die Nachkommastellen, alle anderen gruppieren.
        guard let lastSeparator = raw.lastIndex(where: { $0 == "," || $0 == "." }) else { return nil }
        let whole = raw[raw.startIndex..<lastSeparator].filter(\.isNumber)
        let fraction = raw[raw.index(after: lastSeparator)...].filter(\.isNumber)
        guard fraction.count == 2, let wholeValue = Int(whole), let fractionValue = Int(fraction)
        else { return nil }
        return wholeValue * 100 + fractionValue
    }

    // MARK: - Vergleichen

    /// Prüft eine Signatur gegen die Signaturen bekannter Dokumente.
    ///
    /// Ein Treffer verlangt **zwei** übereinstimmende Merkmale — eine gleiche Belegnummer
    /// allein kann ein Kundennummern-Aufdruck auf jedem Brief desselben Absenders sein, ein
    /// gleicher Betrag allein ein Dauerauftrag in gleicher Höhe.
    static func matches(for candidate: Fingerprint,
                        in known: [(documentId: Int, fingerprint: Fingerprint)]) -> [Match] {
        guard !candidate.isEmpty else { return [] }
        var results: [Match] = []

        for entry in known {
            var reasons: [String] = []
            let sharedNumbers = candidate.referenceNumbers.intersection(entry.fingerprint.referenceNumbers)
            let sharedAmounts = candidate.amounts.intersection(entry.fingerprint.amounts)
            let sharedDates = candidate.dates.intersection(entry.fingerprint.dates)

            if let number = sharedNumbers.sorted().first { reasons.append("Belegnummer \(number)") }
            if let cents = sharedAmounts.sorted().first {
                reasons.append(String(format: "Betrag %.2f", Double(cents) / 100))
            }
            if let date = sharedDates.sorted().first {
                reasons.append("Datum \(DateFormatting.apiDate(date))")
            }

            guard reasons.count >= 2 else { continue }
            // Belegnummer plus Betrag ist so eindeutig, wie es ohne Server geht.
            let confidence = !sharedNumbers.isEmpty && !sharedAmounts.isEmpty ? 1.0 : 0.7
            results.append(Match(documentId: entry.documentId,
                                 reason: reasons.joined(separator: ", "),
                                 confidence: confidence))
        }
        return results.sorted { $0.confidence > $1.confidence }
    }
}

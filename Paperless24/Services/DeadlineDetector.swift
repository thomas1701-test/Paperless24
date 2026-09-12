import Foundation

/// Erkennt Fristen im Text eines Dokuments.
///
/// **Warum deterministisch und nicht per Sprachmodell:** Ein erster Fristen-Radar wurde im
/// Juni 2026 gebaut und wieder entfernt, weil er „mittelgut" funktionierte. Ein Modell, das
/// aus einem Rechnungstext ein Datum „herausliest", verwechselt Rechnungsdatum, Lieferdatum
/// und Zahlungsziel — und jeder Falschtreffer kostet Vertrauen in die ganze Liste.
///
/// Deshalb hier: Datumsangaben werden mit festen Mustern gefunden, und ein Datum wird nur dann
/// zur Frist, wenn in seiner Nähe ein eindeutiges Schlüsselwort steht. Findet sich keines,
/// wird nichts vorgeschlagen. Lieber keine Frist als eine falsche.
enum DeadlineDetector {

    /// Schlüsselwörter je Art, mit Gewicht. Gewicht 1.0 = eindeutig, 0.6 = mehrdeutig.
    private static let keywords: [(phrase: String, kind: Deadline.Kind, weight: Double)] = [
        // Zahlung
        ("zahlbar bis", .payment, 1.0),
        ("zahlbar am", .payment, 1.0),
        ("zahlungsziel", .payment, 1.0),
        ("zahlung bis", .payment, 1.0),
        ("fällig am", .payment, 1.0),
        ("fällig bis", .payment, 1.0),
        ("fälligkeit", .payment, 1.0),
        ("zu zahlen bis", .payment, 1.0),
        ("überweisen sie bis", .payment, 1.0),
        ("zahlen sie bis", .payment, 1.0),
        ("bitte bis", .payment, 0.6),
        ("due date", .payment, 1.0),
        ("payable by", .payment, 1.0),
        // Kündigung
        ("kündigungsfrist", .cancellation, 1.0),
        ("kündigung bis", .cancellation, 1.0),
        ("kündbar bis", .cancellation, 1.0),
        ("kündigen bis", .cancellation, 1.0),
        ("widerrufsfrist", .cancellation, 1.0),
        ("widerruf bis", .cancellation, 1.0),
        ("vertragsende", .cancellation, 1.0),
        ("vertragslaufzeit bis", .cancellation, 1.0),
        ("verlängert sich automatisch", .cancellation, 0.6),
        ("mindestlaufzeit bis", .cancellation, 1.0),
        // Garantie
        ("garantie bis", .warranty, 1.0),
        ("garantie endet", .warranty, 1.0),
        ("garantiezeit", .warranty, 1.0),
        ("gewährleistung bis", .warranty, 1.0),
        ("gewährleistungsfrist", .warranty, 1.0),
        // Ablauf
        ("gültig bis", .expiry, 1.0),
        ("gueltig bis", .expiry, 1.0),
        ("ablaufdatum", .expiry, 1.0),
        ("läuft ab am", .expiry, 1.0),
        ("befristet bis", .expiry, 1.0),
        ("valid until", .expiry, 1.0),
        // Termin
        ("termin am", .appointment, 1.0),
        ("termin:", .appointment, 0.6),
    ]

    /// Zeichen vor dem Datum, in denen nach einem Schlüsselwort gesucht wird.
    ///
    /// 90 Zeichen deckt „Der Betrag ist zahlbar bis zum 30.09.2026" ab, ohne schon in den
    /// vorherigen Satz zu reichen.
    private static let lookBehind = 90
    /// Zeichen nach dem Datum — für „30.09.2026 (Zahlungsziel)".
    private static let lookAhead = 40

    /// Alle Fristen, die sich belegen lassen — die stärkste je Art, höchste Zuversicht zuerst.
    static func detect(in text: String, documentId: Int, now: Date = Date()) -> [Deadline] {
        guard !text.isEmpty else { return [] }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        let lower = flat.lowercased()
        let today = Calendar.current.startOfDay(for: now)

        var best: [Deadline.Kind: Deadline] = [:]

        for match in dateMatches(in: flat) {
            // Zu weit in der Vergangenheit ist keine Frist mehr, sondern Geschichte. Ein
            // überfälliger Betrag von letzter Woche ist dagegen genau das, was interessiert.
            guard let days = Calendar.current.dateComponents(
                [.day], from: today, to: Calendar.current.startOfDay(for: match.date)
            ).day, days >= -60, days <= 3650 else { continue }

            guard let hit = keyword(around: match.range, in: lower) else { continue }

            let deadline = Deadline(
                documentId: documentId, date: match.date, kind: hit.kind,
                evidence: evidence(around: match.range, in: flat),
                confidence: hit.weight
            )
            if let existing = best[hit.kind] {
                // Bei gleicher Art gewinnt die höhere Zuversicht, danach das frühere Datum:
                // Die nächste Frist ist die, die drängt.
                if deadline.confidence > existing.confidence
                    || (deadline.confidence == existing.confidence && deadline.date < existing.date) {
                    best[hit.kind] = deadline
                }
            } else {
                best[hit.kind] = deadline
            }
        }

        return best.values.sorted {
            $0.confidence == $1.confidence ? $0.date < $1.date : $0.confidence > $1.confidence
        }
    }

    /// Die wichtigste Frist eines Dokuments, wenn es eine eindeutige gibt.
    ///
    /// Mehrdeutige Treffer (Gewicht < 1) werden hier bewusst verworfen: Was automatisch
    /// vorgeschlagen wird, muss stimmen.
    static func primaryDeadline(in text: String, documentId: Int, now: Date = Date()) -> Deadline? {
        detect(in: text, documentId: documentId, now: now).first { $0.confidence >= 1.0 }
    }

    // MARK: - Datumsangaben finden

    struct DateMatch {
        let date: Date
        let range: Range<String.Index>
    }

    /// `dd.MM.yyyy`, `d.M.yy`, `dd. Monat yyyy` und `yyyy-MM-dd`.
    ///
    /// Eigene Muster statt `NSDataDetector` allein: Der Detektor liest „30.09.2026" in
    /// deutschen Texten je nach Region auch als Monat-Tag und liefert für Zahlenkolonnen
    /// (Rechnungsnummern, Kundennummern) Treffer, die keine Daten sind.
    static func dateMatches(in text: String) -> [DateMatch] {
        var result: [DateMatch] = []
        let calendar = Calendar(identifier: .gregorian)

        // 1) Numerisch: 30.09.2026 / 30.9.26 / 30-09-2026 / 30/09/2026
        let numeric = #"\b(\d{1,2})[.\-/](\d{1,2})[.\-/](\d{2,4})\b"#
        for m in regexMatches(numeric, in: text) {
            guard let d = Int(group(1, m, text)), let mo = Int(group(2, m, text)),
                  var y = Int(group(3, m, text)) else { continue }
            if y < 100 { y += y < 70 ? 2000 : 1900 }
            guard (1...31).contains(d), (1...12).contains(mo) else { continue }
            var comps = DateComponents()
            comps.day = d; comps.month = mo; comps.year = y
            // `date(from:)` liefert für den 31.02. den 03.03. — deshalb gegenprüfen.
            guard let date = calendar.date(from: comps),
                  calendar.component(.day, from: date) == d,
                  calendar.component(.month, from: date) == mo else { continue }
            result.append(DateMatch(date: date, range: m.range(in: text)))
        }

        // 2) ISO: 2026-09-30
        for m in regexMatches(#"\b(\d{4})-(\d{2})-(\d{2})\b"#, in: text) {
            guard let y = Int(group(1, m, text)), let mo = Int(group(2, m, text)),
                  let d = Int(group(3, m, text)), (1...12).contains(mo), (1...31).contains(d)
            else { continue }
            var comps = DateComponents()
            comps.day = d; comps.month = mo; comps.year = y
            guard let date = calendar.date(from: comps) else { continue }
            result.append(DateMatch(date: date, range: m.range(in: text)))
        }

        // 3) Ausgeschrieben: 30. September 2026 / 1. Mai 2027
        let monthNames = ["januar", "februar", "märz", "maerz", "april", "mai", "juni", "juli",
                          "august", "september", "oktober", "november", "dezember"]
        let monthNumber: [String: Int] = ["januar": 1, "februar": 2, "märz": 3, "maerz": 3,
                                          "april": 4, "mai": 5, "juni": 6, "juli": 7, "august": 8,
                                          "september": 9, "oktober": 10, "november": 11, "dezember": 12]
        let pattern = #"\b(\d{1,2})\.?\s+("# + monthNames.joined(separator: "|") + #")\s+(\d{4})\b"#
        for m in regexMatches(pattern, in: text, caseInsensitive: true) {
            guard let d = Int(group(1, m, text)),
                  let mo = monthNumber[group(2, m, text).lowercased()],
                  let y = Int(group(3, m, text)), (1...31).contains(d) else { continue }
            var comps = DateComponents()
            comps.day = d; comps.month = mo; comps.year = y
            guard let date = calendar.date(from: comps) else { continue }
            result.append(DateMatch(date: date, range: m.range(in: text)))
        }

        return result
    }

    // MARK: - Umgebung auswerten

    /// Sucht das Schlüsselwort, das dem Datum am *nächsten* steht.
    ///
    /// Die Nähe entscheidet, nicht die Reihenfolge in der Liste: In „Zahlbar bis 30.09.2026.
    /// Die Kündigungsfrist läuft bis zum 31.12.2026." liegen beide Schlüsselwörter im Fenster
    /// des zweiten Datums. Wer nur nach Gewicht wählt, erklärt die Kündigungsfrist zur
    /// Zahlungsfrist und verliert sie.
    private static func keyword(around range: Range<String.Index>,
                                in lowercasedText: String) -> (kind: Deadline.Kind, weight: Double)? {
        let behindText = behindWindow(before: range, in: lowercasedText, behind: lookBehind)
        let aheadText = aheadWindow(after: range, in: lowercasedText, ahead: lookAhead)

        var best: (kind: Deadline.Kind, weight: Double, distance: Int)? = nil

        func consider(_ entry: (phrase: String, kind: Deadline.Kind, weight: Double), _ distance: Int) {
            guard best == nil || distance < best!.distance
                || (distance == best!.distance && entry.weight > best!.weight) else { return }
            best = (entry.kind, entry.weight, distance)
        }

        for entry in keywords {
            // Davor: die letzte Erwähnung zählt, sie gehört zum Datum.
            if let found = behindText.range(of: entry.phrase, options: .backwards) {
                consider(entry, behindText.distance(from: found.upperBound, to: behindText.endIndex))
            }
            // Danach: die erste Erwähnung, etwa „30.09.2026 (Zahlungsziel)".
            if let found = aheadText.range(of: entry.phrase) {
                consider(entry, aheadText.distance(from: aheadText.startIndex, to: found.lowerBound))
            }
        }
        return best.map { (kind: $0.kind, weight: $0.weight) }
    }

    /// Der Text direkt *vor* dem Datum — ohne das Datum selbst.
    ///
    /// Das Datum mitzuzählen würde den Abstand um seine Länge verfälschen: „zahlbar bis
    /// 30.09.2026" käme auf 11 Zeichen Abstand und verlöre gegen ein Schlüsselwort, das
    /// hinter dem Datum im nächsten Satz steht.
    private static func behindWindow(before range: Range<String.Index>, in text: String,
                                     behind: Int) -> String {
        let endOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let startOffset = max(0, endOffset - behind)
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(text.startIndex, offsetBy: endOffset)
        return String(text[start..<end])
    }

    /// Der Text direkt nach dem Datum.
    private static func aheadWindow(after range: Range<String.Index>, in text: String,
                                    ahead: Int) -> String {
        let startOffset = text.distance(from: text.startIndex, to: range.upperBound)
        guard startOffset < text.count else { return "" }
        let endOffset = min(text.count, startOffset + ahead)
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(text.startIndex, offsetBy: endOffset)
        return String(text[start..<end])
    }

    private static func evidence(around range: Range<String.Index>, in text: String) -> String {
        let snippet = window(around: range, in: text, behind: lookBehind, ahead: lookAhead)
        return snippet
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func window(around range: Range<String.Index>, in text: String,
                               behind: Int, ahead: Int) -> String {
        let startOffset = max(0, text.distance(from: text.startIndex, to: range.lowerBound) - behind)
        let endOffset = min(text.count,
                            text.distance(from: text.startIndex, to: range.upperBound) + ahead)
        let start = text.index(text.startIndex, offsetBy: startOffset)
        let end = text.index(text.startIndex, offsetBy: endOffset)
        return String(text[start..<end])
    }

    // MARK: - Regex-Helfer

    private static func regexMatches(_ pattern: String, in text: String,
                                     caseInsensitive: Bool = false) -> [NSTextCheckingResult] {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func group(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String {
        guard index < match.numberOfRanges,
              let range = Range(match.range(at: index), in: text) else { return "" }
        return String(text[range])
    }
}

private extension NSTextCheckingResult {
    func range(in text: String) -> Range<String.Index> {
        Range(range, in: text) ?? text.startIndex..<text.startIndex
    }
}

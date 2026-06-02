import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Kapselt Apple Intelligence (on-device Foundation Models). Liefert nil, wenn das
/// Gerät die Modelle nicht unterstützt oder der Nutzer KI deaktiviert hat.
@MainActor
final class AIService {
    static let shared = AIService()
    private init() {}

    /// Letzte Fehlermeldung der KI (für Diagnose/Anzeige).
    private(set) var lastErrorDescription: String?

    /// Vom Nutzer in den Einstellungen steuerbar.
    private var userEnabled: Bool {
        UserDefaults.standard.object(forKey: "aiEnabled") as? Bool ?? true
    }

    /// Modell verfügbar UND vom Nutzer aktiviert.
    var isAvailable: Bool {
        guard userEnabled else { return false }
        return modelAvailable
    }

    var modelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return true
            default: return false
            }
        }
        #endif
        return false
    }

    // MARK: - Funktionen

    func summarize(_ text: String) async -> String? {
        let clean = trimmed(text)
        guard !clean.isEmpty else { return nil }
        return await respond(
            instructions: "Du fasst Dokumente knapp und sachlich auf Deutsch zusammen. Maximal drei Sätze, keine Einleitung.",
            prompt: "Fasse den Inhalt dieses Dokuments zusammen:\n\n\(clean)"
        )
    }

    func answer(question: String, context: String) async -> String? {
        return await respond(
            instructions: "Beantworte die Frage ausschließlich anhand des bereitgestellten Kontexts auf Deutsch. Steht die Antwort nicht im Kontext, sage das ehrlich.",
            prompt: "Kontext:\n\(trimmed(context))\n\nFrage: \(question)"
        )
    }

    /// Liefert Vorschläge als JSON-String: {"title","correspondent","type","tags":[],"date":"YYYY-MM-DD"}.
    func extractMetadata(text: String, tags: [String], correspondents: [String], types: [String]) async -> AISuggestion? {
        let clean = trimmed(text)
        guard !clean.isEmpty else { return nil }
        let instructions = """
        Du extrahierst Metadaten aus eingescannten Dokumenten. Antworte AUSSCHLIESSLICH mit \
        gültigem JSON ohne Markdown, Format:
        {"title": String, "correspondent": String, "type": String, "tags": [String], "date": "YYYY-MM-DD"}
        Wähle bevorzugt aus bekannten Werten, schlage sonst sinnvolle neue vor. Felder leer lassen ("" bzw. []), wenn unklar.
        """
        let prompt = """
        Bekannte Tags: \(tags.joined(separator: ", "))
        Bekannte Sender: \(correspondents.joined(separator: ", "))
        Bekannte Typen: \(types.joined(separator: ", "))

        Dokumenttext:
        \(clean)
        """
        guard let raw = await respond(instructions: instructions, prompt: prompt) else { return nil }
        return AISuggestion(json: raw)
    }

    // MARK: - Fristen-Radar

    func extractDeadlines(text: String) async -> [ExtractedDeadline] {
        let clean = trimmed(text)
        guard !clean.isEmpty else { return [] }
        let today = ISO8601DateFormatter().string(from: Date()).prefix(10)
        let instructions = """
        Du extrahierst Fristen und Termine aus Dokumenten. Heutiges Datum: \(today). \
        Antworte AUSSCHLIESSLICH mit gültigem JSON-Array ohne Markdown. Jedes Element:
        {"type": "payment|cancellation|warranty|withdrawal|general", "date": "YYYY-MM-DD", "detail": "kurze Beschreibung"}
        type-Bedeutung: payment=Zahlungsziel, cancellation=Kündigungsfrist/Vertragsende, \
        warranty=Garantie-Ablauf, withdrawal=Widerrufsfrist, general=sonstiger Termin. \
        Nur echte zukünftige oder relevante Fristen aufnehmen. Wenn keine, antworte mit [].
        """
        guard let raw = await respond(instructions: instructions, prompt: clean) else { return [] }
        return Self.parseDeadlines(raw)
    }

    func draftCancellation(documentText: String, senderName: String, senderAddress: String) async -> String? {
        let instructions = """
        Du formulierst ein höfliches, rechtssicheres deutsches Kündigungsschreiben. \
        Nutze die Absenderdaten und den Vertragskontext. Gib NUR den Brieftext zurück (ohne Erklärungen).
        """
        let prompt = """
        Absender:
        \(senderName)
        \(senderAddress)

        Vertragsdokument (Kontext):
        \(trimmed(documentText))
        """
        return await respond(instructions: instructions, prompt: prompt)
    }

    // MARK: - Natürlichsprachliche Suche

    func parseQuery(_ query: String, tags: [String], correspondents: [String], types: [String]) async -> ParsedQuery? {
        let instructions = """
        Du übersetzt natürlichsprachliche Suchanfragen in Filter. Antworte AUSSCHLIESSLICH mit JSON ohne Markdown:
        {"tag": String, "correspondent": String, "type": String, "dateFrom": "YYYY-MM-DD", "dateTo": "YYYY-MM-DD", "text": String}
        Wähle tag/correspondent/type nur aus den bekannten Werten. Unbenutzte Felder leer lassen ("").
        Heute: \(ISO8601DateFormatter().string(from: Date()).prefix(10)).
        """
        let prompt = """
        Bekannte Tags: \(tags.joined(separator: ", "))
        Bekannte Sender: \(correspondents.joined(separator: ", "))
        Bekannte Typen: \(types.joined(separator: ", "))

        Anfrage: \(query)
        """
        guard let raw = await respond(instructions: instructions, prompt: prompt) else { return nil }
        return ParsedQuery(json: raw)
    }

    // MARK: - Stapel-Trennung

    /// Liefert je Seite eine Gruppen-Nummer (gleiche Nummer = selbes Dokument). Fallback: alles Gruppe 1.
    func groupPages(_ pageTexts: [String]) async -> [Int] {
        guard pageTexts.count > 1 else { return pageTexts.map { _ in 1 } }
        let instructions = """
        Du gruppierst gescannte Seiten zu Dokumenten. Seiten mit neuem Briefkopf/Absender beginnen \
        ein neues Dokument. Antworte AUSSCHLIESSLICH mit einem JSON-Array von Ganzzahlen, \
        eine pro Seite, gleiche Zahl = selbes Dokument. Beispiel für 3 Seiten: [1,1,2]
        """
        let joined = pageTexts.enumerated()
            .map { "Seite \($0.offset + 1):\n\($0.element.prefix(500))" }
            .joined(separator: "\n\n")
        guard let raw = await respond(instructions: instructions, prompt: joined) else {
            return pageTexts.map { _ in 1 }
        }
        if let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]"),
           let data = String(raw[start...end]).data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [Int], arr.count == pageTexts.count {
            return arr
        }
        return pageTexts.map { _ in 1 }
    }

    private static func parseDeadlines(_ raw: String) -> [ExtractedDeadline] {
        guard let start = raw.firstIndex(of: "["), let end = raw.lastIndex(of: "]"),
              let data = String(raw[start...end]).data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        return arr.compactMap { obj in
            guard let dateStr = obj["date"] as? String,
                  let date = fmt.date(from: String(dateStr.prefix(10))) else { return nil }
            let type = DeadlineType(rawValue: (obj["type"] as? String) ?? "general") ?? .general
            let detail = (obj["detail"] as? String) ?? type.label
            return ExtractedDeadline(type: type, date: date, detail: detail)
        }
    }

    // MARK: - Intern

    private func respond(instructions: String, prompt: String) async -> String? {
        lastErrorDescription = nil
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                break
            case .unavailable(let reason):
                lastErrorDescription = "Modell nicht verfügbar: \(reason)"
                return nil
            @unknown default:
                lastErrorDescription = "Modell nicht verfügbar"
                return nil
            }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt)
                return response.content
            } catch {
                lastErrorDescription = Self.friendlyError(error)
                return nil
            }
        } else {
            lastErrorDescription = "iOS 26 erforderlich"
        }
        #else
        lastErrorDescription = "FoundationModels nicht verfügbar"
        #endif
        return nil
    }

    /// Übersetzt kryptische FoundationModels-Fehler in verständliche Hinweise.
    private static func friendlyError(_ error: Error) -> String {
        let desc = String(describing: error)
        if desc.contains("1026") || desc.contains("ModelManager") || desc.contains("assetsUnavailable") || desc.contains("modelNotReady") {
            return "Das Apple-Intelligence-Modell ist nicht bereit. Im Simulator wird es nicht unterstützt – bitte auf einem echten Gerät testen. Dort müssen Apple Intelligence aktiviert (Einstellungen › Apple Intelligence & Siri) und der Modell-Download abgeschlossen sein."
        }
        if desc.contains("exceededContextWindow") {
            return "Das Dokument ist zu lang für die Zusammenfassung."
        }
        if desc.contains("guardrail") {
            return "Der Inhalt wurde vom Sicherheitsfilter blockiert."
        }
        if desc.contains("unsupportedLanguage") || desc.contains("Locale") {
            return "Sprache oder Region wird von Apple Intelligence noch nicht unterstützt."
        }
        return error.localizedDescription
    }

    private func trimmed(_ s: String) -> String {
        // Konservativ unter dem ~4096-Token-Kontextfenster bleiben (inkl. Platz für die Antwort).
        String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3500))
    }
}

/// Geparste KI-Metadaten-Vorschläge.
struct AISuggestion {
    var title: String?
    var correspondent: String?
    var type: String?
    var tags: [String]
    var date: Date?

    init?(json raw: String) {
        // JSON aus evtl. umschließendem Text herauslösen.
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") else { return nil }
        let slice = String(raw[start...end])
        guard let data = slice.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        func str(_ key: String) -> String? {
            let v = (obj[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (v?.isEmpty == false) ? v : nil
        }
        title = str("title")
        correspondent = str("correspondent")
        type = str("type")
        tags = (obj["tags"] as? [String])?.filter { !$0.isEmpty } ?? []
        if let d = str("date") {
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            date = fmt.date(from: String(d.prefix(10)))
        }
    }
}

/// Geparste natürlichsprachliche Suchanfrage.
struct ParsedQuery {
    var tag: String?
    var correspondent: String?
    var type: String?
    var dateFrom: Date?
    var dateTo: Date?
    var text: String?

    init?(json raw: String) {
        guard let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}"),
              let data = String(raw[start...end]).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func str(_ key: String) -> String? {
            let v = (obj[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (v?.isEmpty == false) ? v : nil
        }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        tag = str("tag"); correspondent = str("correspondent"); type = str("type"); text = str("text")
        if let f = str("dateFrom") { dateFrom = fmt.date(from: String(f.prefix(10))) }
        if let t = str("dateTo") { dateTo = fmt.date(from: String(t.prefix(10))) }
    }
}

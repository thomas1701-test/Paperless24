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
                lastErrorDescription = String(describing: error)
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

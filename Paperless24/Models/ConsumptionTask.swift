import Foundation

/// Ein Verarbeitungsauftrag des Servers (`/api/tasks/`).
///
/// `POST /api/documents/post_document/` nimmt die Datei nur an und gibt eine Auftrags-ID
/// zurück. Die eigentliche Arbeit — OCR, Dublettenprüfung, Klassifikation — passiert danach
/// im Consumer. Bis 2.1.4 meldete die App „Fertig", sobald der Server die Datei angenommen
/// hatte; ob daraus ein Dokument wurde oder der Consumer es als Duplikat verworfen hat, war
/// nicht zu sehen.
struct ConsumptionTask: Decodable {
    let taskId: String
    /// `PENDING`, `STARTED`, `SUCCESS`, `FAILURE` (Celery-Zustände).
    let status: String
    /// Erfolgs- oder Fehlertext des Consumers.
    let result: String?
    let relatedDocument: Int?
    let taskFileName: String?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case status
        case result
        case relatedDocument = "related_document"
        case taskFileName = "task_file_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        taskId = try c.decodeIfPresent(String.self, forKey: .taskId) ?? ""
        status = (try c.decodeIfPresent(String.self, forKey: .status) ?? "PENDING").uppercased()
        result = try c.decodeIfPresent(String.self, forKey: .result)
        taskFileName = try c.decodeIfPresent(String.self, forKey: .taskFileName)
        // `related_document` liefert ngx je Version als Zahl oder als String.
        if let intValue = try? c.decodeIfPresent(Int.self, forKey: .relatedDocument) {
            relatedDocument = intValue
        } else if let stringValue = try? c.decodeIfPresent(String.self, forKey: .relatedDocument) {
            relatedDocument = Int(stringValue ?? "")
        } else {
            relatedDocument = nil
        }
    }

    var isFinished: Bool { status == "SUCCESS" || status == "FAILURE" }
    var didFail: Bool { status == "FAILURE" }

    /// Erkennt die Dublettenmeldung des Consumers.
    ///
    /// Der Consumer verweigert ein bereits vorhandenes Dokument mit einem Text, der „duplicate"
    /// enthält. Das ist die verlässlichste Dublettenerkennung, die zu haben ist — sie kommt vom
    /// Server, der alle Dokumente kennt, nicht aus einem Textvergleich auf dem Telefon.
    var isDuplicate: Bool {
        guard let result else { return false }
        let low = result.lowercased()
        return low.contains("duplicate") || low.contains("duplikat")
    }

    /// Kurze, lesbare Rückmeldung für die Oberfläche.
    var displayMessage: String {
        if isDuplicate { return "Schon im Archiv — der Server hat es als Duplikat abgelehnt." }
        if let result, !result.isEmpty { return result }
        switch status {
        case "SUCCESS": return "Verarbeitet"
        case "FAILURE": return "Verarbeitung fehlgeschlagen"
        case "STARTED": return "Wird verarbeitet…"
        default:        return "Wartet auf Verarbeitung…"
        }
    }
}

/// Zustand eines Uploads, den die App nachverfolgt.
struct UploadTaskStatus: Identifiable, Equatable {
    enum State: Equatable { case waiting, running, succeeded, failed, duplicate, unknown }

    let id: String
    let title: String
    var state: State = .waiting
    var message: String? = nil
    var documentId: Int? = nil

    var isFinished: Bool {
        state == .succeeded || state == .failed || state == .duplicate || state == .unknown
    }

    var symbolName: String {
        switch state {
        case .waiting, .running: return "clock"
        case .succeeded:         return "checkmark.circle.fill"
        case .failed:            return "exclamationmark.triangle.fill"
        case .duplicate:         return "doc.on.doc.fill"
        case .unknown:           return "questionmark.circle"
        }
    }
}

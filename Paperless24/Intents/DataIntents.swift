import AppIntents
import Foundation

/// Kurzbefehle, die *Daten* liefern statt nur die App zu öffnen.
///
/// Die vier bisherigen Intents (`ScanDocumentIntent` & Co.) setzen eine Marke und öffnen die
/// App. Damit lässt sich in der Kurzbefehle-App keine Automation bauen: Kein Intent nimmt einen
/// Wert an, keiner gibt einen zurück. Die hier ergänzen genau das — und ohne dafür die
/// Oberfläche zu starten.

// MARK: - Dokument als Kurzbefehl-Wert

/// Ein Dokument, wie Kurzbefehle es weitergeben kann.
struct DocumentEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Dokument")
    static var defaultQuery = DocumentEntityQuery()

    let id: Int
    let title: String
    let created: String
    let correspondent: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(correspondent ?? "")\(correspondent == nil ? "" : " · ")\(created.prefix(10))"
        )
    }

    /// Öffnet das Dokument in der App — dasselbe Schema, das Widget und Spotlight nutzen.
    var url: URL? { URL(string: "\(AppConstants.urlScheme)://document?id=\(id)") }
}

struct DocumentEntityQuery: EntityQuery {
    /// Die Dokumente zu diesen IDs — gezielt abgefragt. Vorher wurden die neuesten 200 geholt
    /// und darin gesucht; ältere Dokumente ließen sich in einem Kurzbefehl nicht auflösen.
    func entities(for identifiers: [Int]) async throws -> [DocumentEntity] {
        try await IntentDataSource.documents(ids: identifiers)
    }

    func suggestedEntities() async throws -> [DocumentEntity] {
        // Die zuletzt hinzugefügten aus der App Group — ohne Netzverkehr.
        IntentDataSource.recentFromAppGroup()
    }
}

// MARK: - Suche mit Rückgabewert

struct FindDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Dokumente finden"
    static var description = IntentDescription(
        "Sucht im Archiv und gibt die Treffer zurück — zum Weiterverarbeiten im Kurzbefehl."
    )
    /// Läuft ohne die App zu öffnen: Genau das macht den Intent für Automationen brauchbar.
    static var openAppWhenRun = false
    /// Nur bei entsperrtem Gerät. Vorher lieferte Siri Dokumenttitel und Sender auch vom
    /// Sperrbildschirm aus — an der Gerätesperre und an der App-Sperre vorbei.
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Suchbegriff")
    var query: String

    @Parameter(title: "Maximale Anzahl", default: 10, inclusiveRange: (1, 100))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Finde \(\.$query) im Archiv, höchstens \(\.$limit) Treffer")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[DocumentEntity]> {
        let results = try await IntentDataSource.search(query: query, limit: limit)
        return .result(value: results)
    }
}

// MARK: - Posteingangszahl

struct InboxCountIntent: AppIntent {
    static var title: LocalizedStringResource = "Posteingang zählen"
    static var description = IntentDescription(
        "Gibt zurück, wie viele Dokumente unbearbeitet sind."
    )
    static var openAppWhenRun = false
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        // Aus der App Group: keine Anmeldung, kein Netz, sofortige Antwort. Der Wert stammt
        // vom letzten Lauf der App — für „wie viel liegt an" genau richtig.
        let count = IntentDataSource.inboxCount()
        return .result(
            value: count,
            dialog: count == 0
                ? IntentDialog("Der Posteingang ist leer.")
                : IntentDialog("\(count) Dokumente liegen im Posteingang.")
        )
    }
}

// MARK: - Datei hochladen

struct UploadFileIntent: AppIntent {
    static var title: LocalizedStringResource = "Dokument hochladen"
    static var description = IntentDescription(
        "Übergibt eine Datei an Paperless 24. Die App öffnet sich mit dem Importformular."
    )
    /// Der Upload braucht das Formular (Titel, Sender, Typ, Tags) — und die App muss dafür
    /// nach vorn. Ein stiller Upload ohne Zuordnung würde nur den Posteingang füllen.
    static var openAppWhenRun = true

    @Parameter(title: "Datei", supportedContentTypes: [.pdf, .image])
    var file: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Lade \(\.$file) nach Paperless 24")
    }

    func perform() async throws -> some IntentResult {
        let data = try await file.data(contentType: file.type ?? .pdf)
        let name = file.filename.isEmpty ? "Import.pdf" : file.filename
        guard IntentDataSource.stageForImport(data: data, filename: name) else {
            throw IntentError.stagingFailed
        }
        return .result()
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case stagingFailed
    case notLoggedIn

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .stagingFailed: return "Die Datei konnte nicht übergeben werden."
        case .notLoggedIn:   return "Kein Konto angemeldet. Bitte zuerst in der App anmelden."
        }
    }
}

// MARK: - Datenzugriff ohne Oberfläche

/// Liest und schreibt für die Intents, ohne `AppStore` und ohne Oberfläche.
///
/// `AppStore` hängt am Main Actor und an der Ansicht; ein Kurzbefehl, der im Hintergrund läuft,
/// darf davon nichts brauchen.
enum IntentDataSource {

    static func inboxCount() -> Int {
        UserDefaults(suiteName: AppConstants.appGroupId)?.integer(forKey: "widget_inbox_count") ?? 0
    }

    static func recentFromAppGroup() -> [DocumentEntity] {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupId),
              let data = defaults.data(forKey: "widget_documents"),
              let docs = try? JSONDecoder().decode([WidgetDocumentPayload].self, from: data)
        else { return [] }
        return docs.map {
            DocumentEntity(id: $0.id, title: $0.title, created: $0.created,
                           correspondent: $0.correspondent)
        }
    }

    /// Sucht auf dem Server des aktiven Kontos.
    static func search(query: String, limit: Int) async throws -> [DocumentEntity] {
        guard let account = activeAccount(),
              let token = KeychainService.loadToken(for: account.serverUrl, username: account.username)
        else { throw IntentError.notLoggedIn }

        let api = PaperlessAPI(serverUrl: account.serverUrl, token: token)
        var documentQuery = DocumentQuery()
        documentQuery.searchText = query
        let page = try await api.fetchDocuments(query: documentQuery, page: 1,
                                               pageSize: min(max(limit, 1), 100))

        // Sendernamen einmal holen, damit die Rückgabe lesbar ist.
        let names: [Int: String]
        if let corrs = try? await api.fetchCorrespondents() {
            names = Dictionary(corrs.map { ($0.id, $0.safeName) }, uniquingKeysWith: { a, _ in a })
        } else {
            names = [:]
        }

        return page.documents.prefix(limit).map { doc in
            DocumentEntity(id: doc.id, title: doc.title, created: doc.created,
                           correspondent: doc.correspondent.flatMap { names[$0] })
        }
    }

    static func documents(ids: [Int]) async throws -> [DocumentEntity] {
        guard !ids.isEmpty else { return [] }
        guard let account = activeAccount(),
              let token = KeychainService.loadToken(for: account.serverUrl, username: account.username)
        else { throw IntentError.notLoggedIn }
        let api = PaperlessAPI(serverUrl: account.serverUrl, token: token)
        var result: [DocumentEntity] = []
        for id in ids.prefix(50) {
            guard let doc = try? await api.fetchDocumentDetail(id: id) else { continue }
            result.append(DocumentEntity(id: doc.id, title: doc.title, created: doc.created, correspondent: nil))
        }
        return result
    }

    /// Legt eine Datei so ab, wie es die Share-Erweiterung tut — die App holt sie beim
    /// nächsten Wechsel in den Vordergrund ab (`checkForSharedFile()`).
    static func stageForImport(data: Data, filename: String) -> Bool {
        // Eigene Datei statt des einen gemeinsamen Platzes — und mit Dateischutz.
        SharedImports.stage(data, filename: filename)
    }

    private static func activeAccount() -> Account? {
        let accounts = AccountService.load()
        if let id = AccountService.activeId(), let match = accounts.first(where: { $0.id == id }) {
            return match
        }
        return accounts.first
    }
}

/// Das Format, in dem die App die letzten Dokumente in der App Group ablegt.
private struct WidgetDocumentPayload: Codable {
    let id: Int
    let title: String
    let created: String
    let correspondent: String?
}

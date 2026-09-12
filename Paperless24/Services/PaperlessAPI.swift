import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case otpRequired
    case serverError(Int)
    case noData
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Ungültige URL"
        case .unauthorized:         return "Nicht autorisiert (401)"
        case .otpRequired:          return "2FA-Code erforderlich"
        case .serverError(let c):   return "Server Fehler: \(c)"
        case .noData:               return "Keine Daten erhalten"
        case .decodingError(let e): return "Datenfehler: \(e.localizedDescription)"
        }
    }
}

struct DocumentPage {
    let documents: [Document]
    let hasNext: Bool
    /// `count` der Antwort — die Gesamtzahl der Treffer über alle Seiten hinweg.
    var totalCount: Int? = nil
}

/// Handelt die paperless-ngx API-Version pro Server aus.
///
/// ngx nutzt DRF `AcceptHeaderVersioning`. Ohne `Accept: application/json; version=N` liefert
/// der Server seinen eigenen Default — und der hat sich mit jedem Major verschoben:
/// ≤2.13 → 1, 2.14 → 7, 2.15–2.19 → 9, 3.0 → 10. Ein Server-Upgrade ändert damit das
/// Antwortformat unter der App weg.
///
/// Version 9 ist die einzige, die von 2.15 bis 3.0.x durchgehend erlaubt ist
/// (3.0: `ALLOWED_VERSIONS = ["9", "10"]`) und entspricht dem Format, das die App dekodiert.
/// Ältere Server (≤2.14) kennen 9 nicht und antworten mit 406 — dann fällt die App dauerhaft
/// auf den Server-Default zurück, also exakt auf das bisherige Verhalten.
enum APIVersionNegotiator {
    /// API-Version, gegen die die App geschrieben ist.
    static let preferred = 9

    /// Ein Schlüssel pro Server statt eines Dictionaries — ein Dictionary müsste bei jedem
    /// Schreibvorgang gelesen und zurückgeschrieben werden, und parallel laufende Requests
    /// würden sich dabei gegenseitig überschreiben.
    private static func defaultsKey(_ server: String) -> String { "paperlessApiVersionMode.\(server)" }
    /// Sentinel: kein Version-Header, abgeleitet aus `X-Api-Version`.
    private static let serverDefault = -1
    /// Sentinel: kein Version-Header, erzwungen durch ein 406. Wird nie wieder hochgestuft —
    /// sonst würde ein Server, der `preferred` gedroppt hat, aber ein höheres Maximum meldet,
    /// dauerhaft zwischen 406 und Retry pendeln.
    private static let rejected = -2

    /// `nil`, solange für den Server noch nichts bekannt ist.
    private static func mode(for server: String) -> Int? {
        UserDefaults.standard.object(forKey: defaultsKey(server)) as? Int
    }

    /// `nil` bedeutet: keinen Version-Header senden.
    static func version(for server: String) -> Int? {
        guard let mode = mode(for: server) else { return preferred }
        return mode > 0 ? mode : nil
    }

    /// Wertet den `X-Api-Version`-Header aus, den ngx auf jede `/api/`-Antwort setzt.
    static func record(response: HTTPURLResponse, server: String) {
        guard mode(for: server) != rejected,
              let raw = response.value(forHTTPHeaderField: "X-Api-Version"),
              let serverMax = Int(raw) else { return }
        UserDefaults.standard.set(
            serverMax >= preferred ? preferred : serverDefault,
            forKey: defaultsKey(server)
        )
    }

    /// Nach einem 406: Server akzeptiert `preferred` nicht (ngx ≤2.14 oder ein künftiger,
    /// der 9 gedroppt hat). Ab jetzt ohne Header — der Server entscheidet.
    static func fallbackToServerDefault(server: String) {
        UserDefaults.standard.set(rejected, forKey: defaultsKey(server))
    }
}

struct PaperlessAPI {
    let serverUrl: String
    let token: String

    /// Ein stummer Server soll die Oberfläche nicht eine Minute lang blockieren.
    private static let requestTimeout: TimeInterval = 30
    /// Uploads dürfen länger dauern — ein großer Scan über eine schmale Leitung.
    private static let uploadTimeout: TimeInterval = 180

    private static var pageSize: Int {
        let stored = UserDefaults.standard.integer(forKey: "pageSize")
        return stored > 0 ? stored : 25
    }

    // MARK: - URL Builder

    /// Normalisiert die vom Nutzer eingegebene Server-Adresse.
    ///
    /// Eine Adresse ohne Schema bekommt `http://`. Das ist bewusst so: sehr viele
    /// paperless-ngx-Installationen laufen im Heimnetz ohne TLS, und ein erzwungenes
    /// `https://` macht genau die unerreichbar. Wer TLS nutzt, schreibt `https://` davor.
    ///
    /// Die Prüfung auf das Schema ist absichtlich genau: das frühere `hasPrefix("http")` traf
    /// auch auf einen Host zu, der schlicht so anfängt (`httpserver.local`) — der blieb dann
    /// ohne Schema stehen und ergab keine gültige URL.
    static func normalizedBase(_ raw: String) -> String {
        var clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasSuffix("/") { clean.removeLast() }
        let lower = clean.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return clean }
        return "http://\(clean)"
    }

    var serverBase: String { Self.normalizedBase(serverUrl) }

    /// Baut eine API-URL. Query-Werte gehen durch `URLComponents` — String-Interpolation
    /// würde ein `&` oder `+` im Suchbegriff als Trennzeichen durchreichen und die Anfrage
    /// zerlegen (oder fremde Parameter einschleusen lassen).
    private func url(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        try Self.url(base: serverBase, path: path, query: query)
    }

    /// Nicht `private`, damit die Tests den Aufbau direkt prüfen können.
    static func url(base: String, path: String, query: [URLQueryItem]) throws -> URL {
        guard var comps = URLComponents(string: "\(base)/api/\(path)") else { throw APIError.invalidURL }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.invalidURL }
        return url
    }

    private static func pageQuery(page: Int, extra: [URLQueryItem] = []) -> [URLQueryItem] {
        extra + [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ]
    }

    // MARK: - Auth Header

    private func authHeader() -> String { "Token \(token)" }

    private func makeRequest(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.timeoutInterval = Self.requestTimeout
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        if let version = APIVersionNegotiator.version(for: serverBase) {
            req.setValue("application/json; version=\(version)", forHTTPHeaderField: "Accept")
        }
        return req
    }

    /// Führt einen Request aus und wiederholt ihn einmal ohne Version-Header,
    /// falls der Server die angeforderte API-Version nicht kennt (406).
    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { return (data, response) }
        APIVersionNegotiator.record(response: http, server: serverBase)

        guard http.statusCode == 406,
              request.value(forHTTPHeaderField: "Accept")?.contains("version=") == true else {
            return (data, response)
        }
        APIVersionNegotiator.fallbackToServerDefault(server: serverBase)
        var retry = request
        retry.setValue(nil, forHTTPHeaderField: "Accept")
        return try await URLSession.shared.data(for: retry)
    }

    // MARK: - Token Exchange

    static func fetchToken(
        serverUrl: String,
        username: String,
        password: String,
        otp: String? = nil
    ) async throws -> String {
        let url = try url(base: normalizedBase(serverUrl), path: "token/", query: [])

        var tokenReq = URLRequest(url: url)
        tokenReq.httpMethod = "POST"
        tokenReq.timeoutInterval = requestTimeout
        tokenReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = ["username": username, "password": password]
        if let otp { body["code"] = otp }
        tokenReq.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: tokenReq)
        guard let http = response as? HTTPURLResponse else { throw APIError.noData }

        if (400...401).contains(http.statusCode) {
            let rawLower = (String(data: data, encoding: .utf8) ?? "").lowercased()
            let otpKeywords = ["otp", "totp", "mfa", "2fa", "one-time"]
            if otp == nil && otpKeywords.contains(where: { rawLower.contains($0) }) {
                throw APIError.otpRequired
            }
            throw APIError.unauthorized
        }
        if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else { throw APIError.noData }
        return token
    }

    // MARK: - Documents

    func fetchDocuments(page: Int, ordering: String = "-created,-id") async throws -> DocumentPage {
        try await fetchDocuments(page: page, pageSize: Self.pageSize, ordering: ordering)
    }

    /// Mit eigener Seitengröße. Die Listenansicht lädt in der vom Nutzer eingestellten
    /// Größe; der Spotlight-Index blättert dagegen in großen Schritten durch das Archiv
    /// und käme mit 25 pro Anfrage auf unnötig viele Runden.
    func fetchDocuments(page: Int, pageSize: Int, ordering: String = "-created,-id") async throws -> DocumentPage {
        let url = try url("documents/", query: [
            URLQueryItem(name: "ordering", value: ordering),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ])
        let req = makeRequest(url)
        let (data, response) = try await send(req)
        try validateResponse(response)
        return try Self.decodePage(data)
    }

    /// Gefilterte Liste. Die Filter stehen als Query-Parameter in der Anfrage, der Server
    /// entscheidet — nur so stimmt die Trefferzahl und nur so lässt sich *innerhalb* eines
    /// Filters weiterblättern.
    ///
    /// Wirft `APIError.serverError(400)`, wenn ein Server einen der Parameter nicht kennt.
    /// `AppStore` fängt das ab und fällt für diesen Server dauerhaft auf lokale Filterung
    /// zurück (`DocumentFilterSupport`), statt eine leere Liste zu zeigen.
    func fetchDocuments(query: DocumentQuery, page: Int, pageSize: Int,
                        ordering: String = "-created,-id") async throws -> DocumentPage {
        let url = try url("documents/", query: query.queryItems() + [
            URLQueryItem(name: "ordering", value: ordering),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ])
        let req = makeRequest(url)
        let (data, response) = try await send(req)
        try validateResponse(response)
        return try Self.decodePage(data)
    }

    /// Dokumente, die mindestens einen der übergebenen Tags tragen (`tags__id__in`).
    /// Für den Posteingang: die Inbox-Tags des Servers.
    func fetchDocuments(tagIDs: [Int], page: Int, pageSize: Int = 250,
                        ordering: String = "-added,-id") async throws -> DocumentPage {
        let url = try url("documents/", query: [
            URLQueryItem(name: "tags__id__in", value: tagIDs.sorted().map(String.init).joined(separator: ",")),
            URLQueryItem(name: "ordering", value: ordering),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "\(pageSize)")
        ])
        let req = makeRequest(url)
        let (data, response) = try await send(req)
        try validateResponse(response)
        return try Self.decodePage(data)
    }

    func searchDocuments(query: String, page: Int = 1) async throws -> DocumentPage {
        let url = try url("documents/", query: Self.pageQuery(
            page: page,
            extra: [URLQueryItem(name: "query", value: query)]
        ))
        let (data, response) = try await send(makeRequest(url))
        try validateResponse(response)
        return try Self.decodePage(data)
    }

    private static func decodePage(_ data: Data) throws -> DocumentPage {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.noData
        }
        let decoder = JSONDecoder()
        let results = (json["results"] as? [[String: Any]] ?? []).compactMap { dict -> Document? in
            guard let docData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(Document.self, from: docData)
        }
        let hasNext = json["next"] != nil && !(json["next"] is NSNull)
        return DocumentPage(documents: results, hasNext: hasNext, totalCount: json["count"] as? Int)
    }

    /// `-id` als Zweitkriterium hält die Seitenfolge eindeutig — siehe `orderingParam()`.
    func fetchAllDocuments(ordering: String = "-created,-id") async throws -> [Document] {
        var all: [Document] = []
        var page = 1
        while true {
            let result = try await fetchDocuments(page: page, ordering: ordering)
            let before = all.count
            all.appendUniqueByID(result.documents)
            // `next` allein reicht als Abbruchkriterium nicht: liefert ein Server bei
            // uneindeutiger Sortierung immer wieder dieselbe Seite, liefe die Schleife
            // sonst bis zum Speicherüberlauf.
            guard result.hasNext, all.count > before else { break }
            page += 1
        }
        return all
    }

    func fetchDocumentDetail(id: Int) async throws -> Document {
        let url = try url("documents/\(id)/")
        let (data, response) = try await send(makeRequest(url))
        try validateResponse(response)
        return try JSONDecoder().decode(Document.self, from: data)
    }

    func downloadDocument(id: Int) async throws -> Data {
        let url = try url("documents/\(id)/download/")
        var req = makeRequest(url)
        req.timeoutInterval = Self.uploadTimeout
        let (data, response) = try await send(req)
        try validateResponse(response)
        return data
    }

    func deleteDocument(id: Int) async throws {
        let url = try url("documents/\(id)/")
        var req = makeRequest(url)
        req.httpMethod = "DELETE"
        let (_, response) = try await send(req)
        if let http = response as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.serverError(http.statusCode)
        }
    }

    func uploadDocument(_ item: PendingUpload) async throws {
        let url = try url("documents/post_document/")
        var req = makeRequest(url)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.uploadTimeout
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func addField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"document\"; filename=\"\(item.filename)\"\r\n\r\n".data(using: .utf8)!)
        body.append(item.data)
        body.append("\r\n".data(using: .utf8)!)
        addField("title", item.title)
        addField("created", DateFormatting.apiDate(item.created))
        if let c = item.correspondent { addField("correspondent", "\(c)") }
        if let t = item.documentType { addField("document_type", "\(t)") }
        for tag in item.tags { addField("tags", "\(tag)") }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (_, response) = try await send(req)
        try validateResponse(response)
    }

    func patchDocument(id: Int, title: String, created: String, correspondent: Int?, documentType: Int?, archiveSerialNumber: Int?, tags: [Int], customFields: [CustomFieldEdit] = []) async throws {
        let url = try url("documents/\(id)/")
        var req = makeRequest(url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "title": title, "created": created, "tags": tags,
            "correspondent": correspondent ?? NSNull(),
            "document_type": documentType ?? NSNull(),
            "archive_serial_number": archiveSerialNumber ?? NSNull()
        ]
        // Nur gesetzte Felder senden — leere Werte würden sonst leere Einträge anlegen.
        let nonEmpty = customFields.filter { !$0.value.isEmpty }
        body["custom_fields"] = nonEmpty.map { ["field": $0.field, "value": $0.value.jsonValue] }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await send(req)
        try validateResponse(response)
    }

    // MARK: - Metadata

    /// Holt eine Metadaten-Liste über alle Seiten hinweg.
    ///
    /// Vorher fragte jede dieser Listen genau eine Seite mit `page_size=1000` ab. Ein Archiv
    /// mit mehr Einträgen verlor den Rest stillschweigend — bei den Tags konnte damit auch das
    /// Inbox-Tag fehlen, und der Posteingang blieb ohne Fehlermeldung leer.
    private func fetchAllPages<Item, Wrapper: Decodable>(
        _ path: String,
        as wrapper: Wrapper.Type,
        pageSize: Int = 500,
        maxPages: Int = 40,
        results: (Wrapper) -> [Item]?
    ) async throws -> [Item] {
        var all: [Item] = []
        var page = 1
        while page <= maxPages {
            let url = try url(path, query: [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "page_size", value: "\(pageSize)")
            ])
            let (data, response) = try await send(makeRequest(url))
            try validateResponse(response)
            let items = (try? JSONDecoder().decode(Wrapper.self, from: data)).flatMap(results) ?? []
            all.append(contentsOf: items)
            if items.count < pageSize { break }
            page += 1
        }
        return all
    }

    func fetchTags() async throws -> [Tag] {
        try await fetchAllPages("tags/", as: TagResponse.self) { $0.results }
    }

    func fetchCorrespondents() async throws -> [Correspondent] {
        try await fetchAllPages("correspondents/", as: CorrespondentResponse.self) { $0.results }
    }

    func fetchDocumentTypes() async throws -> [DocumentType] {
        try await fetchAllPages("document_types/", as: DocTypeResponse.self) { $0.results }
    }

    func fetchStatistics() async throws -> PaperlessStatistics {
        let url = try url("statistics/")
        let (data, response) = try await send(makeRequest(url))
        try validateResponse(response)
        return try JSONDecoder().decode(PaperlessStatistics.self, from: data)
    }

    func createTag(name: String) async throws -> Int {
        try await createMetadata(endpoint: "tags/", body: ["name": name, "color": "#2a80b9", "matching_algorithm": 1, "is_insensitive": true])
    }

    func createCorrespondent(name: String) async throws -> Int {
        try await createMetadata(endpoint: "correspondents/", body: ["name": name, "match": "", "matching_algorithm": 1, "is_insensitive": true])
    }

    func createDocumentType(name: String) async throws -> Int {
        try await createMetadata(endpoint: "document_types/", body: ["name": name, "match": "", "matching_algorithm": 1, "is_insensitive": true])
    }

    private func createMetadata(endpoint: String, body: [String: Any]) async throws -> Int {
        let url = try url(endpoint)
        var req = makeRequest(url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(req)
        try validateResponse(response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? Int else { throw APIError.noData }
        return id
    }

    func deleteTag(id: Int) async throws { try await deleteMetadata(endpoint: "tags/\(id)/") }
    func deleteCorrespondent(id: Int) async throws { try await deleteMetadata(endpoint: "correspondents/\(id)/") }
    func deleteDocumentType(id: Int) async throws { try await deleteMetadata(endpoint: "document_types/\(id)/") }

    private func deleteMetadata(endpoint: String) async throws {
        let url = try url(endpoint)
        var req = makeRequest(url)
        req.httpMethod = "DELETE"
        let (_, response) = try await send(req)
        if let http = response as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.serverError(http.statusCode)
        }
    }

    // MARK: - Notes

    func addNote(docId: Int, text: String) async throws {
        let url = try url("documents/\(docId)/notes/")
        var req = makeRequest(url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["note": text])
        let (_, response) = try await send(req)
        try validateResponse(response)
    }

    func deleteNote(docId: Int, noteId: Int) async throws {
        let url = try url("documents/\(docId)/notes/\(noteId)/")
        var req = makeRequest(url)
        req.httpMethod = "DELETE"
        let (_, response) = try await send(req)
        if let http = response as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.serverError(http.statusCode)
        }
    }

    // MARK: - Custom Fields

    func fetchCustomFields() async throws -> [CustomField] {
        try await fetchAllPages("custom_fields/", as: CustomFieldResponse.self) { $0.results }
    }

    // MARK: - Trash

    func fetchTrash() async throws -> [TrashDocument] {
        let url = try url("trash/", query: [URLQueryItem(name: "page_size", value: "1000")])
        let (data, response) = try await send(makeRequest(url))
        try validateResponse(response)
        return (try? JSONDecoder().decode(TrashResponse.self, from: data))?.results ?? []
    }

    func restoreFromTrash(ids: [Int]) async throws { try await trashAction("restore", ids: ids) }
    func emptyTrash(ids: [Int]) async throws { try await trashAction("empty", ids: ids) }

    private func trashAction(_ action: String, ids: [Int]) async throws {
        let url = try url("trash/")
        var req = makeRequest(url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["action": action, "documents": ids])
        let (_, response) = try await send(req)
        try validateResponse(response)
    }

    // MARK: - Share Links

    func fetchShareLinks(documentId: Int) async throws -> [DocShareLink] {
        let url = try url("share_links/", query: [
            URLQueryItem(name: "document", value: "\(documentId)"),
            URLQueryItem(name: "page_size", value: "1000")
        ])
        let (data, response) = try await send(makeRequest(url))
        try validateResponse(response)
        return (try? JSONDecoder().decode(ShareLinkResponse.self, from: data))?.results ?? []
    }

    func createShareLink(documentId: Int, expiration: Date?, fileVersion: String) async throws -> DocShareLink {
        let url = try url("share_links/")
        var req = makeRequest(url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["document": documentId, "file_version": fileVersion]
        if let expiration { body["expiration"] = ISO8601DateFormatter().string(from: expiration) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(req)
        try validateResponse(response)
        return try JSONDecoder().decode(DocShareLink.self, from: data)
    }

    func deleteShareLink(id: Int) async throws {
        let url = try url("share_links/\(id)/")
        var req = makeRequest(url)
        req.httpMethod = "DELETE"
        let (_, response) = try await send(req)
        if let http = response as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.serverError(http.statusCode)
        }
    }

    // MARK: - Saved Views

    func fetchSavedViews() async throws -> [SavedView] {
        try await fetchAllPages("saved_views/", as: SavedViewResponse.self) { $0.results }
    }

    func createSavedView(name: String, sortField: String, sortReverse: Bool, rules: [[String: Any]]) async throws -> SavedView {
        let url = try url("saved_views/")
        var req = makeRequest(url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "name": name,
            "show_on_dashboard": false,
            "show_in_sidebar": true,
            "sort_field": sortField,
            "sort_reverse": sortReverse,
            "filter_rules": rules
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await send(req)
        try validateResponse(response)
        return try JSONDecoder().decode(SavedView.self, from: data)
    }

    func deleteSavedView(id: Int) async throws {
        let url = try url("saved_views/\(id)/")
        var req = makeRequest(url)
        req.httpMethod = "DELETE"
        let (_, response) = try await send(req)
        if let http = response as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.serverError(http.statusCode)
        }
    }

    // MARK: - Thumbnail

    func thumbnailURL(for docId: Int) -> String {
        "\(serverBase)/api/documents/\(docId)/thumb/"
    }

    /// Lädt die Miniaturansicht als Rohdaten. Die Ansichten laden über `AuthImage`; der
    /// Spotlight-Index braucht die Bytes ohne den Umweg über eine View.
    func fetchThumbnail(for docId: Int) async throws -> Data {
        guard let url = URL(string: thumbnailURL(for: docId)) else { throw APIError.invalidURL }
        let (data, response) = try await send(makeRequest(url))
        try validateResponse(response)
        return data
    }

    // MARK: - Private

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }
    }
}

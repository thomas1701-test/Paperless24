import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case unauthorized
    case serverError(Int)
    case noData
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:         return "Ungültige URL"
        case .unauthorized:       return "Nicht autorisiert (401)"
        case .serverError(let c): return "Server Fehler: \(c)"
        case .noData:             return "Keine Daten erhalten"
        case .decodingError(let e): return "Datenfehler: \(e.localizedDescription)"
        }
    }
}

struct DocumentPage {
    let documents: [Document]
    let hasNext: Bool
}

struct PaperlessAPI {
    let serverUrl: String
    let token: String

    private static var pageSize: Int {
        let stored = UserDefaults.standard.integer(forKey: "pageSize")
        return stored > 0 ? stored : 25
    }

    // MARK: - URL Builder

    private func url(_ endpoint: String) throws -> URL {
        var clean = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasSuffix("/") { clean.removeLast() }
        let prefix = clean.lowercased().hasPrefix("http") ? "" : "http://"
        guard let url = URL(string: "\(prefix)\(clean)/api/\(endpoint)") else { throw APIError.invalidURL }
        return url
    }

    var serverBase: String {
        var clean = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasSuffix("/") { clean.removeLast() }
        let prefix = clean.lowercased().hasPrefix("http") ? "" : "http://"
        return "\(prefix)\(clean)"
    }

    // MARK: - Auth Header

    private func authHeader() -> String { "Token \(token)" }

    private func makeRequest(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        return req
    }

    // MARK: - Token Exchange

    static func fetchToken(serverUrl: String, username: String, password: String) async throws -> String {
        var clean = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasSuffix("/") { clean.removeLast() }
        let prefix = clean.lowercased().hasPrefix("http") ? "" : "http://"
        guard let url = URL(string: "\(prefix)\(clean)/api/token/") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["username": username, "password": password])

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.unauthorized }
            if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String else { throw APIError.noData }
        return token
    }

    // MARK: - Connection Check

    static func checkConnection(serverUrl: String, username: String, password: String) async throws {
        var clean = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasSuffix("/") { clean.removeLast() }
        let prefix = clean.lowercased().hasPrefix("http") ? "" : "http://"
        guard let url = URL(string: "\(prefix)\(clean)/api/tags/") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        let auth = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""
        req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 401 { throw APIError.unauthorized }
            if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }
        }
    }

    // MARK: - Documents

    func fetchDocuments(page: Int, ordering: String = "-created") async throws -> DocumentPage {
        let endpoint = "documents/?page=\(page)&page_size=\(Self.pageSize)&ordering=\(ordering)"
        let url = try url(endpoint)
        let req = makeRequest(url)
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.noData
        }
        let rawResults = json["results"] as? [[String: Any]] ?? []
        let decoder = JSONDecoder()
        let results = rawResults.compactMap { dict -> Document? in
            guard let docData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(Document.self, from: docData)
        }
        let hasNext = json["next"] != nil && !(json["next"] is NSNull)
        return DocumentPage(documents: results, hasNext: hasNext)
    }

    func searchDocuments(query: String, page: Int = 1) async throws -> DocumentPage {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let endpoint = "documents/?query=\(encoded)&page=\(page)&page_size=\(Self.pageSize)"
        let url = try url(endpoint)
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
        try validateResponse(response)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw APIError.noData }
        let decoder = JSONDecoder()
        let results = (json["results"] as? [[String: Any]] ?? []).compactMap { dict -> Document? in
            guard let docData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
            return try? decoder.decode(Document.self, from: docData)
        }
        let hasNext = json["next"] != nil && !(json["next"] is NSNull)
        return DocumentPage(documents: results, hasNext: hasNext)
    }

    func fetchAllDocuments(ordering: String = "-created") async throws -> [Document] {
        var all: [Document] = []
        var page = 1
        while true {
            let result = try await fetchDocuments(page: page, ordering: ordering)
            all.append(contentsOf: result.documents)
            guard result.hasNext else { break }
            page += 1
        }
        return all
    }

    func fetchDocumentDetail(id: Int) async throws -> Document {
        let url = try url("documents/\(id)/")
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
        try validateResponse(response)
        return try JSONDecoder().decode(Document.self, from: data)
    }

    func downloadDocument(id: Int) async throws -> Data {
        let url = try url("documents/\(id)/download/")
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
        try validateResponse(response)
        return data
    }

    func deleteDocument(id: Int) async throws {
        let url = try url("documents/\(id)/")
        var req = makeRequest(url)
        req.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.serverError(http.statusCode)
        }
    }

    func uploadDocument(_ item: PendingUpload) async throws {
        let url = try url("documents/post_document/")
        var req = makeRequest(url)
        req.httpMethod = "POST"
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
        addField("created", ISO8601DateFormatter().string(from: item.created))
        if let c = item.correspondent { addField("correspondent", "\(c)") }
        if let t = item.documentType { addField("document_type", "\(t)") }
        for tag in item.tags { addField("tags", "\(tag)") }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
    }

    func patchDocument(id: Int, title: String, created: String, correspondent: Int?, documentType: Int?, archiveSerialNumber: Int?, tags: [Int]) async throws {
        let url = try url("documents/\(id)/")
        var req = makeRequest(url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "title": title, "created": created, "tags": tags,
            "correspondent": correspondent ?? NSNull(),
            "document_type": documentType ?? NSNull(),
            "archive_serial_number": archiveSerialNumber ?? NSNull()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
    }

    // MARK: - Metadata

    func fetchTags() async throws -> [Tag] {
        let url = try url("tags/?page_size=1000")
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
        try validateResponse(response)
        return (try? JSONDecoder().decode(TagResponse.self, from: data))?.results ?? []
    }

    func fetchCorrespondents() async throws -> [Correspondent] {
        let url = try url("correspondents/?page_size=1000")
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
        try validateResponse(response)
        return (try? JSONDecoder().decode(CorrespondentResponse.self, from: data))?.results ?? []
    }

    func fetchDocumentTypes() async throws -> [DocumentType] {
        let url = try url("document_types/?page_size=1000")
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
        try validateResponse(response)
        return (try? JSONDecoder().decode(DocTypeResponse.self, from: data))?.results ?? []
    }

    func fetchStatistics() async throws -> PaperlessStatistics {
        let url = try url("statistics/")
        let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
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
        let (data, response) = try await URLSession.shared.data(for: req)
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
        let (_, response) = try await URLSession.shared.data(for: req)
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
        let (_, response) = try await URLSession.shared.data(for: req)
        try validateResponse(response)
    }

    func deleteNote(docId: Int, noteId: Int) async throws {
        let url = try url("documents/\(docId)/notes/\(noteId)/")
        var req = makeRequest(url)
        req.httpMethod = "DELETE"
        let (_, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 204 {
            throw APIError.serverError(http.statusCode)
        }
    }

    // MARK: - Thumbnail

    func thumbnailURL(for docId: Int) -> String {
        "\(serverBase)/api/documents/\(docId)/thumb/"
    }

    func thumbnailRequest(for docId: Int) -> URLRequest {
        var req = URLRequest(url: URL(string: thumbnailURL(for: docId))!)
        req.setValue(authHeader(), forHTTPHeaderField: "Authorization")
        return req
    }

    // MARK: - Private

    private func validateResponse(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 { throw APIError.unauthorized }
        if !(200...299).contains(http.statusCode) { throw APIError.serverError(http.statusCode) }
    }
}

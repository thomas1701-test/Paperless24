import Testing
import Foundation
import Network
@testable import Paperless24

/// Ein Kontowechsel darf keine Arbeit des vorherigen Kontos in das neue tragen.
///
/// Hintergrund (Codeprüfung 12.09.2026, B2/S2): Sync und Warteschlangen liefen nach
/// `switchAccount` weiter. Die Upload-Warteschlange bildete `api` in jeder Runde neu — die
/// zweite Datei von Konto A ging an den Server von Konto B —, und die späte Antwort von A
/// landete in der Dokumentliste und im Plattencache von B.
@MainActor
@Suite(.serialized)
struct AccountSwitchTests {

    @Test func wechselWaehrendUploadUndSync() async throws {
        // Konto A antwortet langsam, damit der Wechsel mitten in die Arbeit fällt.
        let serverA = try await TestHTTPServer.start(delay: 1.5, documentTitle: "A-Dokument", documentId: 42)
        let serverB = try await TestHTTPServer.start(delay: 0, documentTitle: "B-Dokument", documentId: 7)
        defer { serverA.stop(); serverB.stop() }

        let defaults = UserDefaults.standard
        let backup = (accounts: defaults.data(forKey: "accounts_v2"),
                      active: defaults.string(forKey: "activeAccountId"),
                      demo: defaults.object(forKey: "isDemoMode"))
        let accountA = Account(id: UUID(), serverUrl: serverA.baseURL, username: "a")
        let accountB = Account(id: UUID(), serverUrl: serverB.baseURL, username: "b")
        defer {
            defaults.set(backup.accounts, forKey: "accounts_v2")
            defaults.set(backup.active, forKey: "activeAccountId")
            defaults.set(backup.demo, forKey: "isDemoMode")
            for account in [accountA, accountB] {
                KeychainService.deleteToken(for: account.serverUrl, username: account.username)
                PersistenceService.deleteAccountFiles(accountId: account.id)
            }
            for key in defaults.dictionaryRepresentation().keys where key.contains("127.0.0.1") {
                defaults.removeObject(forKey: key)
            }
        }
        #expect(KeychainService.saveToken("token-a", for: accountA.serverUrl, username: "a"))
        #expect(KeychainService.saveToken("token-b", for: accountB.serverUrl, username: "b"))

        // Zwei wartende Uploads in Konto A.
        let uploads = (1...2).map {
            PendingUpload(data: Data(repeating: UInt8($0), count: 64), filename: "a\($0).pdf",
                          title: "A-Upload \($0)", created: Date(),
                          correspondent: nil, documentType: nil, tags: [])
        }
        PersistenceService.saveUploads(uploads, accountId: accountA.id)
        PersistenceService.waitForPendingWrites()

        defaults.set(false, forKey: "isDemoMode")
        AccountService.save([accountA, accountB])
        AccountService.setActiveId(accountA.id)

        let store = AppStore()
        store.sync()

        // Warten, bis der erste Upload bei A angekommen ist — dann wechseln.
        for _ in 0..<40 where !serverA.requests.contains(where: { $0.contains("post_document") }) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(serverA.requests.contains { $0.contains("post_document") })
        store.switchAccount(to: accountB.id)

        // A antwortet nach 1,5 s; genug Zeit für alles, was danach noch passieren könnte.
        try await Task.sleep(nanoseconds: 4_000_000_000)

        #expect(!serverB.requests.contains { $0.contains("post_document") },
                "Datei aus Konto A ging an den Server von Konto B")
        #expect(!store.documents.contains { $0.title == "A-Dokument" },
                "Antwort von Konto A landete in der Liste von Konto B")
        #expect(store.pendingUploads.isEmpty)
        #expect(store.activeAccountId == accountB.id)
        #expect(KeychainService.loadToken(for: accountB.serverUrl, username: "b") != nil)

        PersistenceService.waitForPendingWrites()
        let docsB = PersistenceService.load(
            [Document].self,
            fromURL: PersistenceService.accountDataURL(for: accountB.id, filename: "documents.json")
        ) ?? []
        #expect(!docsB.contains { $0.title == "A-Dokument" }, "Daten von A im Plattencache von B")

        // Der erste Upload ist bei A angekommen und muss aus dessen Warteschlange raus, der
        // zweite wartet dort weiter.
        let remainingA = PersistenceService.loadUploads(accountId: accountA.id)
        #expect(remainingA.map(\.title) == ["A-Upload 2"])
    }

    /// Weg und gleich wieder zurück, während ein Upload läuft: Keine Datei darf zweimal hinausgehen,
    /// und was angekommen ist, verschwindet auch aus der Warteschlange im Speicher.
    @Test func hinUndZurueckWaehrendUpload() async throws {
        let serverA = try await TestHTTPServer.start(delay: 1.5, documentTitle: "A-Dokument", documentId: 42)
        let serverB = try await TestHTTPServer.start(delay: 0, documentTitle: "B-Dokument", documentId: 7)
        defer { serverA.stop(); serverB.stop() }

        let defaults = UserDefaults.standard
        let backup = (accounts: defaults.data(forKey: "accounts_v2"),
                      active: defaults.string(forKey: "activeAccountId"),
                      demo: defaults.object(forKey: "isDemoMode"))
        let accountA = Account(id: UUID(), serverUrl: serverA.baseURL, username: "a")
        let accountB = Account(id: UUID(), serverUrl: serverB.baseURL, username: "b")
        defer {
            defaults.set(backup.accounts, forKey: "accounts_v2")
            defaults.set(backup.active, forKey: "activeAccountId")
            defaults.set(backup.demo, forKey: "isDemoMode")
            for account in [accountA, accountB] {
                KeychainService.deleteToken(for: account.serverUrl, username: account.username)
                PersistenceService.deleteAccountFiles(accountId: account.id)
            }
            for key in defaults.dictionaryRepresentation().keys where key.contains("127.0.0.1") {
                defaults.removeObject(forKey: key)
            }
        }
        #expect(KeychainService.saveToken("token-a", for: accountA.serverUrl, username: "a"))
        #expect(KeychainService.saveToken("token-b", for: accountB.serverUrl, username: "b"))

        let uploads = (1...2).map {
            PendingUpload(data: Data(repeating: UInt8($0), count: 64), filename: "a\($0).pdf",
                          title: "A-Upload \($0)", created: Date(),
                          correspondent: nil, documentType: nil, tags: [])
        }
        PersistenceService.saveUploads(uploads, accountId: accountA.id)
        PersistenceService.waitForPendingWrites()

        defaults.set(false, forKey: "isDemoMode")
        AccountService.save([accountA, accountB])
        AccountService.setActiveId(accountA.id)

        let store = AppStore()
        store.sync()
        for _ in 0..<40 where serverA.uploadedFilenames.isEmpty {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(serverA.uploadedFilenames == ["a1.pdf"])

        store.switchAccount(to: accountB.id)
        store.switchAccount(to: accountA.id)
        // Plattenstand von A laden lassen, dann einen neuen Durchlauf anstoßen.
        try await Task.sleep(nanoseconds: 500_000_000)
        store.sync()

        try await Task.sleep(nanoseconds: 5_000_000_000)

        let counts = Dictionary(serverA.uploadedFilenames.map { ($0, 1) }, uniquingKeysWith: +)
        #expect(counts["a1.pdf"] == 1, "a1.pdf ging \(counts["a1.pdf"] ?? 0)-mal hinaus")
        #expect(counts["a2.pdf"] == 1)
        #expect(serverB.uploadedFilenames.isEmpty)
        #expect(store.pendingUploads.isEmpty, "Übrig: \(store.pendingUploads.map(\.title))")
        PersistenceService.waitForPendingWrites()
        #expect(PersistenceService.loadUploads(accountId: accountA.id).isEmpty)
    }
}

/// Ein minimaler HTTP-Server für die Tests: beantwortet jede Anfrage nach `delay` Sekunden mit
/// einer Dokumentseite (bzw. `"OK"` für Uploads) und merkt sich die Anfragezeilen.
final class TestHTTPServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "test.http.server")
    private let lock = NSLock()
    private var _requests: [String] = []
    private var _uploadedFilenames: [String] = []
    private let delay: TimeInterval
    private let documentJSON: String
    /// Antwort je Anfragezeile; ohne sie gilt `documentJSON` für alles außer `post_document`.
    private let respond: (@Sendable (String) -> String)?
    let port: UInt16

    var baseURL: String { "http://127.0.0.1:\(port)" }

    var requests: [String] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    /// Dateinamen aus den Multipart-Körpern von `post_document`, in Eingangsreihenfolge.
    var uploadedFilenames: [String] {
        lock.lock(); defer { lock.unlock() }
        return _uploadedFilenames
    }

    private init(listener: NWListener, port: UInt16, delay: TimeInterval, documentJSON: String,
                 respond: (@Sendable (String) -> String)? = nil) {
        self.listener = listener
        self.port = port
        self.delay = delay
        self.documentJSON = documentJSON
        self.respond = respond
    }

    static func start(delay: TimeInterval, documentTitle: String, documentId: Int) async throws -> TestHTTPServer {
        let (listener, port) = try await listen()
        let json = #"{"count":1,"next":null,"results":[{"id":\#(documentId),"title":"\#(documentTitle)","created":"2026-01-01","tags":[]}]}"#
        let server = TestHTTPServer(listener: listener, port: port, delay: delay, documentJSON: json)
        listener.newConnectionHandler = { [server] connection in server.handle(connection) }
        return server
    }

    /// Server mit eigener Antwort je Anfragezeile (z. B. abhängig von `ordering=`).
    static func start(delay: TimeInterval = 0, respond: @escaping @Sendable (String) -> String) async throws -> TestHTTPServer {
        let (listener, port) = try await listen()
        let server = TestHTTPServer(listener: listener, port: port, delay: delay, documentJSON: "", respond: respond)
        listener.newConnectionHandler = { [server] connection in server.handle(connection) }
        return server
    }

    private static func listen() async throws -> (NWListener, UInt16) {
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "test.http.listener")
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: queue)
        }
        return (listener, port)
    }

    func stop() { listener.cancel() }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
                if isComplete || error != nil { connection.cancel() } else { receive(on: connection, buffer: buffer) }
                return
            }
            let header = String(decoding: buffer[..<headerEnd.lowerBound], as: UTF8.self)
            let length = header.split(separator: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            guard buffer.count - headerEnd.upperBound >= length else {
                receive(on: connection, buffer: buffer)
                return
            }
            let requestLine = String(header.split(separator: "\r\n").first ?? "")
            let bodyText = String(decoding: buffer[headerEnd.upperBound...], as: UTF8.self)
            let filename = bodyText.range(of: "filename=\"").flatMap { start in
                bodyText[start.upperBound...].split(separator: "\"", maxSplits: 1).first.map(String.init)
            }
            lock.lock()
            _requests.append(requestLine)
            if requestLine.contains("post_document"), let filename { _uploadedFilenames.append(filename) }
            lock.unlock()

            let body = respond?(requestLine)
                ?? (requestLine.contains("post_document") ? #""OK""# : documentJSON)
            let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                + "Content-Length: \(Data(body.utf8).count)\r\nConnection: close\r\n\r\n" + body
            queue.asyncAfter(deadline: .now() + delay) {
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
    }
}

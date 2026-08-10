import Testing
import Foundation
@testable import Paperless24

/// Deckt den Aufbau der Anfrage-URLs ab.
///
/// Der Anlass war die Query: Suchbegriffe wurden per String-Interpolation angehängt, ein `&`
/// im Suchtext zerlegte damit die Anfrage. Die Schema-Tests halten fest, dass eine schemalose
/// Adresse weiterhin über HTTP angesprochen wird — Heimnetz-Installationen ohne TLS wären
/// sonst nicht mehr erreichbar.
struct PaperlessAPIURLTests {

    // MARK: - Schema

    @Test("Adresse ohne Schema bekommt HTTP")
    func addsHTTPWhenSchemeIsMissing() {
        #expect(PaperlessAPI.normalizedBase("paperless.example.com") == "http://paperless.example.com")
        #expect(PaperlessAPI.normalizedBase("192.168.1.10:8000") == "http://192.168.1.10:8000")
    }

    @Test("Ausdrücklich getipptes HTTP bleibt erhalten")
    func keepsExplicitHTTP() {
        #expect(PaperlessAPI.normalizedBase("http://paperless.local") == "http://paperless.local")
        #expect(PaperlessAPI.normalizedBase("HTTP://paperless.local") == "HTTP://paperless.local")
    }

    @Test("HTTPS bleibt unverändert")
    func keepsHTTPS() {
        #expect(PaperlessAPI.normalizedBase("https://paperless.example.com") == "https://paperless.example.com")
    }

    @Test("Leerzeichen und abschließende Schrägstriche fallen weg")
    func trimsWhitespaceAndSlashes() {
        #expect(PaperlessAPI.normalizedBase("  https://example.com///  ") == "https://example.com")
    }

    /// `hasPrefix("http")` traf früher auch auf einen Host zu, der schlicht so anfängt —
    /// der blieb dann ohne Schema stehen und ergab keine gültige URL.
    @Test("Host, der mit „http“ beginnt, wird nicht für ein Schema gehalten")
    func hostStartingWithHTTPIsNotAScheme() {
        #expect(PaperlessAPI.normalizedBase("httpserver.local") == "http://httpserver.local")
    }

    // MARK: - Query

    @Test("Suchbegriff mit kaufmännischem Und bleibt ein einziger Parameter")
    func encodesAmpersandInQuery() throws {
        let url = try PaperlessAPI.url(
            base: "https://example.com",
            path: "documents/",
            query: [
                URLQueryItem(name: "query", value: "Meier & Sohn"),
                URLQueryItem(name: "page", value: "1")
            ]
        )
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(comps.queryItems)

        #expect(items.count == 2)
        #expect(items.first { $0.name == "query" }?.value == "Meier & Sohn")
        #expect(items.first { $0.name == "page" }?.value == "1")
        #expect(url.absoluteString.contains("%26"))
    }

    @Test("Pluszeichen bleibt ein Pluszeichen und wird nicht zum Leerzeichen")
    func encodesPlusInQuery() throws {
        let url = try PaperlessAPI.url(
            base: "https://example.com",
            path: "documents/",
            query: [URLQueryItem(name: "query", value: "C++ Rechnung")]
        )
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.queryItems?.first?.value == "C++ Rechnung")
    }

    @Test("Über den Suchbegriff lassen sich keine eigenen Parameter einschleusen")
    func cannotInjectExtraParameters() throws {
        let url = try PaperlessAPI.url(
            base: "https://example.com",
            path: "documents/",
            query: [URLQueryItem(name: "query", value: "x&page_size=99999&ordering=title")]
        )
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(comps.queryItems)

        #expect(items.count == 1)
        #expect(items.first?.value == "x&page_size=99999&ordering=title")
    }

    @Test("Pfad hängt unter /api/")
    func buildsAPIPath() throws {
        let url = try PaperlessAPI.url(base: "https://example.com", path: "documents/12/", query: [])
        #expect(url.absoluteString == "https://example.com/api/documents/12/")
    }
}

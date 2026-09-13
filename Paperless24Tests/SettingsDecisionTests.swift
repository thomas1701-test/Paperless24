import Testing
import Foundation
@testable import Paperless24

/// Login: standardmäßig `https`, `http` nur per Schalter — nicht mehr still ergänzt.
struct ServerAddressTests {
    @Test(arguments: [
        ("https://paper.example.org", ServerScheme.https, "paper.example.org"),
        ("HTTP://10.0.0.5:8000", ServerScheme.http, "10.0.0.5:8000"),
        ("  paper.local  ", nil, "paper.local"),
    ])
    func trenntSchema(raw: String, scheme: ServerScheme?, rest: String) {
        let parts = ServerAddress.split(raw)
        #expect(parts.scheme == scheme)
        #expect(parts.rest == rest)
    }

    @Test func setztGewaehltesSchema() {
        #expect(ServerAddress.compose(scheme: .https, input: "paper.local:8000/") == "https://paper.local:8000")
        #expect(ServerAddress.compose(scheme: .http, input: "paper.local") == "http://paper.local")
        // Der Schalter entscheidet: eingetipptes http:// allein reicht nicht.
        #expect(ServerAddress.compose(scheme: .https, input: "http://paper.local") == "https://paper.local")
        #expect(ServerAddress.compose(scheme: .https, input: "   ") == "")
    }

    @Test func vorbelegung() {
        #expect(ServerAddress.initialScheme(for: "") == .https)
        #expect(ServerAddress.initialScheme(for: "https://x") == .https)
        // Bestandskonto ohne Schema lief über http.
        #expect(ServerAddress.initialScheme(for: "paper.local:8000") == .http)
    }

    /// Erneutes Anmelden an einem alten Konto ohne Schema darf kein zweites Konto anlegen.
    @Test func gespeicherteSchreibweise() {
        let accounts = [(serverUrl: "paper.local:8000", username: "anna"),
                        (serverUrl: "https://cloud.example.org", username: "anna")]
        #expect(ServerAddress.storedSpelling(of: "http://paper.local:8000", username: "anna", accounts: accounts)
                == "paper.local:8000")
        #expect(ServerAddress.storedSpelling(of: "https://paper.local:8000", username: "anna", accounts: accounts) == nil)
        #expect(ServerAddress.storedSpelling(of: "http://paper.local:8000", username: "ben", accounts: accounts) == nil)
    }
}

/// KI-Vorschläge: Vorhandenes wird zugeordnet, Fehlendes kommt zur Rückfrage.
struct SuggestionResolverTests {
    private let corrs = [(id: 1, name: "Stadtwerke"), (id: 2, name: "Finanzamt")]
    private let types = [(id: 10, name: "Rechnung")]
    private let tags = [(id: 20, name: "Wohnung"), (id: 21, name: "Steuer")]

    @Test func ordnetVorhandenesZu() {
        let r = SuggestionResolver.resolve(
            correspondent: "stadtwerke", type: "RECHNUNG", tags: ["wohnung", "Steuer", "Wohnung"],
            correspondents: corrs, types: types, allTags: tags)
        #expect(r.correspondent == 1)
        #expect(r.documentType == 10)
        #expect(r.tags == [20, 21])
        #expect(r.missing.isEmpty)
    }

    @Test func fehlendesWirdNichtAngelegtSondernVorgeschlagen() {
        let r = SuggestionResolver.resolve(
            correspondent: "Telekom", type: "Vertrag", tags: ["Handy", "handy ", "Steuer", "  "],
            correspondents: corrs, types: types, allTags: tags)
        #expect(r.correspondent == nil)
        #expect(r.documentType == nil)
        #expect(r.tags == [21])
        #expect(r.missing == [
            MetadataProposal(kind: .correspondent, name: "Telekom"),
            MetadataProposal(kind: .docType, name: "Vertrag"),
            MetadataProposal(kind: .tag, name: "Handy"),
        ])
    }
}

/// Spotlight-Schalter in „Datenschutz & Spotlight".
struct SpotlightSettingsTests {
    private func defaults() -> UserDefaults {
        let name = "spotlight-test-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    @Test func ohneWerteAn() {
        let d = defaults()
        #expect(AppStore.spotlightEnabled(d))
        #expect(AppStore.spotlightIncludesContent(d))
    }

    @Test func volltextSchalter() {
        let d = defaults()
        d.set(false, forKey: "spotlightFullText")
        #expect(!AppStore.spotlightIncludesContent(d))
        d.set(true, forKey: "spotlightFullText")
        #expect(AppStore.spotlightIncludesContent(d))
    }

    @Test func appSperreSchlaegtVolltext() {
        let d = defaults()
        d.set(true, forKey: "spotlightFullText")
        d.set(true, forKey: "useFaceID")
        #expect(!AppStore.spotlightIncludesContent(d))
    }

    @Test func ganzAus() {
        let d = defaults()
        d.set(false, forKey: "spotlightEnabled")
        #expect(!AppStore.spotlightEnabled(d))
    }
}

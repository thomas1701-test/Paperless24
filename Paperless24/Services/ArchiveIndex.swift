import Foundation
import NaturalLanguage

/// Lokaler Bedeutungsindex über das Archiv — die Grundlage für „Archiv fragen".
///
/// Vorher rankte die Frage-Funktion `store.documents`, also die gerade geladene Seite. Bei der
/// Standard-Seitengröße durchsuchte „Wann läuft mein Vertrag aus?" also 25 von mehreren tausend
/// Dokumenten, ohne das kenntlich zu machen — die Antwortqualität war Glückssache.
///
/// Der Index hält je Dokument einen Vektor (`NLEmbedding.vector(for:)`) statt des Textes. Das
/// kostet einmal Rechenzeit beim Aufbau, dafür ist eine Frage danach ein Vergleich von
/// Zahlenreihen statt tausender Embedding-Aufrufe.
actor ArchiveIndex {

    /// Ein Eintrag: Dokument-ID und sein Vektor.
    struct Entry: Codable {
        let id: Int
        let vector: [Double]
    }

    private var entries: [Int: [Double]] = [:]
    private var accountId: UUID?
    private var isLoaded = false

    static let shared = ArchiveIndex()

    /// Zeichen je Dokument, die in den Vektor einfließen.
    ///
    /// Der Anfang eines Dokuments trägt die Bedeutung: Briefkopf, Betreff, erster Absatz. Mehr
    /// Text verwässert den Vektor eher, als dass er ihn schärft.
    private static let textLimit = 600

    // MARK: - Laden und Sichern

    func use(account: UUID?) async {
        guard account != accountId else { return }
        accountId = account
        entries = [:]
        isLoaded = false
        await load()
    }

    private func load() async {
        guard !isLoaded, let accountId else { return }
        isLoaded = true
        let url = PersistenceService.accountDataURL(for: accountId, filename: "archiveindex.json")
        guard let list = PersistenceService.load([Entry].self, fromURL: url) else { return }
        entries = Dictionary(list.map { ($0.id, $0.vector) }, uniquingKeysWith: { a, _ in a })
    }

    private func save() {
        guard let accountId else { return }
        let url = PersistenceService.accountDataURL(for: accountId, filename: "archiveindex.json")
        PersistenceService.save(entries.map { Entry(id: $0.key, vector: $0.value) }, toURL: url)
    }

    // MARK: - Aufbau

    var count: Int { entries.count }

    func contains(_ id: Int) -> Bool { entries[id] != nil }

    /// Nimmt Dokumente auf, die noch nicht im Index stehen.
    ///
    /// Gibt zurück, wie viele hinzugekommen sind.
    @discardableResult
    func index(_ documents: [(id: Int, text: String)], force: Bool = false) async -> Int {
        await load()
        guard let embedding = Self.embedding() else { return 0 }
        var added = 0
        for doc in documents {
            if !force, entries[doc.id] != nil { continue }
            let text = String(doc.text.prefix(Self.textLimit))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let vector = embedding.vector(for: text) else { continue }
            entries[doc.id] = vector
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func remove(_ id: Int) {
        guard entries.removeValue(forKey: id) != nil else { return }
        save()
    }

    func clear() {
        entries = [:]
        save()
    }

    // MARK: - Abfrage

    /// Die IDs der Dokumente, die am besten zur Frage passen.
    ///
    /// Kosinus-Ähnlichkeit statt `NLEmbedding.distance`: Der Vektor der Frage wird einmal
    /// gebildet und dann gegen alle gespeicherten gerechnet — bei 5.000 Dokumenten ist das
    /// eine Frage von Millisekunden statt 5.000 Embedding-Aufrufen.
    func bestMatches(for query: String, limit: Int) async -> [Int] {
        await load()
        guard !entries.isEmpty,
              let embedding = Self.embedding(),
              let queryVector = embedding.vector(for: query) else { return [] }

        return entries
            .compactMap { id, vector -> (Int, Double)? in
                let score = Self.cosine(queryVector, vector)
                return score.isFinite ? (id, score) : nil
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Rechnen

    private static func embedding() -> NLEmbedding? {
        NLEmbedding.sentenceEmbedding(for: .german) ?? NLEmbedding.sentenceEmbedding(for: .english)
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        var dot = 0.0, normA = 0.0, normB = 0.0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return -1 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}

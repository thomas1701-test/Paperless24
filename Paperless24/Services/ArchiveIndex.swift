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

    /// Ein Eintrag im alten JSON-Format (bis 2.2.0) — nur noch zum einmaligen Umzug.
    struct Entry: Codable {
        let id: Int
        let vector: [Double]
    }

    /// `Float` statt `Double`: halber Speicher, und die Genauigkeit reicht für einen
    /// Ähnlichkeitsvergleich allemal.
    private var entries: [Int: [Float]] = [:]
    private var accountId: UUID?
    private var isLoaded = false
    /// Ungesicherte Änderungen — siehe `index(_:account:persist:)`.
    private var isDirty = false

    static let shared = ArchiveIndex()

    /// Zeichen je Dokument, die in den Vektor einfließen.
    ///
    /// Der Anfang eines Dokuments trägt die Bedeutung: Briefkopf, Betreff, erster Absatz. Mehr
    /// Text verwässert den Vektor eher, als dass er ihn schärft.
    private static let textLimit = 600

    private static let fileName = "archiveindex.bin"
    private static let legacyFileName = "archiveindex.json"

    // MARK: - Laden und Sichern

    /// Jede öffentliche Methode nimmt das Konto mit. Vorher gab es ein separates
    /// `use(account:)` — zwischen diesem Aufruf und dem eigentlichen Zugriff konnte ein anderer
    /// Aufrufer auf ein anderes Konto umschalten, und die Vektoren von Konto A landeten im Index
    /// von Konto B. Innerhalb einer Methode gibt es keinen Wartepunkt, das Umschalten und der
    /// Zugriff laufen also am Stück.
    private func use(account: UUID?) {
        guard account != accountId else { return }
        // Ungesichertes des bisherigen Kontos nicht verlieren.
        if isDirty { save() }
        accountId = account
        entries = [:]
        isLoaded = false
        load()
    }

    private func load() {
        guard !isLoaded, let accountId else { return }
        isLoaded = true
        let url = PersistenceService.accountDataURL(for: accountId, filename: Self.fileName)
        if let data = try? Data(contentsOf: url), let decoded = Self.decode(data) {
            entries = decoded
            return
        }
        // Umzug aus dem JSON-Format: 512 Zahlen je Dokument als Text, bei 5.000 Dokumenten gut
        // 50 MB — und bei jedem Aufbauschritt komplett neu geschrieben.
        let legacyURL = PersistenceService.accountDataURL(for: accountId, filename: Self.legacyFileName)
        guard let list = PersistenceService.load([Entry].self, fromURL: legacyURL) else { return }
        entries = Dictionary(list.map { ($0.id, $0.vector.map(Float.init)) }, uniquingKeysWith: { a, _ in a })
        save()
        try? FileManager.default.removeItem(at: legacyURL)
    }

    private func save() {
        guard let accountId else { return }
        let url = PersistenceService.accountDataURL(for: accountId, filename: Self.fileName)
        try? PersistenceService.writeFile(Self.encode(entries), to: url)
        isDirty = false
    }

    /// Schreibt ausstehende Änderungen — nach einem Aufbau mit `persist: false`.
    func flush(account: UUID?) {
        guard account == accountId, isDirty else { return }
        save()
    }

    // MARK: - Dateiformat

    /// Binär: Kopf (Version, Anzahl, Dimension als `UInt32`), dann je Eintrag die ID als
    /// `Int64` und der Vektor als `Float32`, alles Little Endian.
    static func encode(_ entries: [Int: [Float]]) -> Data {
        let dimension = entries.values.first?.count ?? 0
        let valid = entries.filter { $0.value.count == dimension }
        var data = Data(capacity: 12 + valid.count * (8 + dimension * 4))
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        append(UInt32(1))
        append(UInt32(valid.count))
        append(UInt32(dimension))
        for (id, vector) in valid {
            append(Int64(id))
            for value in vector { append(value.bitPattern) }
        }
        return data
    }

    static func decode(_ data: Data) -> [Int: [Float]]? {
        var offset = 0
        func read<T: FixedWidthInteger>(_ type: T.Type) -> T? {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else { return nil }
            var value: T = 0
            withUnsafeMutableBytes(of: &value) { buffer in
                data.copyBytes(to: buffer, from: data.index(data.startIndex, offsetBy: offset)..<data.index(data.startIndex, offsetBy: offset + size))
            }
            offset += size
            return T(littleEndian: value)
        }
        guard read(UInt32.self) == 1, let count = read(UInt32.self), let dimension = read(UInt32.self),
              data.count == 12 + Int(count) * (8 + Int(dimension) * 4) else { return nil }
        var result: [Int: [Float]] = [:]
        result.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let id = read(Int64.self) else { return nil }
            var vector = [Float](repeating: 0, count: Int(dimension))
            for index in vector.indices {
                guard let bits = read(UInt32.self) else { return nil }
                vector[index] = Float(bitPattern: bits)
            }
            result[Int(id)] = vector
        }
        return result
    }

    // MARK: - Aufbau

    func count(account: UUID?) -> Int {
        use(account: account)
        return entries.count
    }

    /// Nimmt Dokumente auf, die noch nicht im Index stehen.
    ///
    /// `persist: false` für den seitenweisen Vollaufbau: Dort wurde der ganze Index vorher nach
    /// jeder Seite neu geschrieben; jetzt einmal am Ende über `flush(account:)`.
    ///
    /// Gibt zurück, wie viele hinzugekommen sind.
    @discardableResult
    func index(_ documents: [(id: Int, text: String)], account: UUID?, force: Bool = false,
               persist: Bool = true) -> Int {
        use(account: account)
        guard accountId != nil else { return 0 }
        guard let embedding = Self.embedding() else { return 0 }
        var added = 0
        for doc in documents {
            if !force, entries[doc.id] != nil { continue }
            let text = String(doc.text.prefix(Self.textLimit))
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let vector = embedding.vector(for: text) else { continue }
            entries[doc.id] = vector.map(Float.init)
            added += 1
        }
        if added > 0 {
            isDirty = true
            if persist { save() }
        }
        return added
    }

    func remove(_ id: Int, account: UUID?) {
        use(account: account)
        guard entries.removeValue(forKey: id) != nil else { return }
        save()
    }

    func clear(account: UUID?) {
        use(account: account)
        entries = [:]
        save()
    }

    // MARK: - Abfrage

    /// Die IDs der Dokumente, die am besten zur Frage passen.
    ///
    /// Kosinus-Ähnlichkeit statt `NLEmbedding.distance`: Der Vektor der Frage wird einmal
    /// gebildet und dann gegen alle gespeicherten gerechnet — bei 5.000 Dokumenten ist das
    /// eine Frage von Millisekunden statt 5.000 Embedding-Aufrufen.
    func bestMatches(for query: String, limit: Int, account: UUID?) -> [Int] {
        use(account: account)
        guard !entries.isEmpty,
              let embedding = Self.embedding(),
              let queryVector = embedding.vector(for: query)?.map(Float.init) else { return [] }

        return entries
            .compactMap { id, vector -> (Int, Float)? in
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

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return -1 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        guard normA > 0, normB > 0 else { return -1 }
        return dot / (normA.squareRoot() * normB.squareRoot())
    }
}

import Foundation

struct Document: Identifiable, Codable, Hashable {
    let id: Int
    var title: String
    var content: String?
    var created: String
    var added: String?
    var correspondent: Int?
    var documentType: Int?
    var archiveSerialNumber: Int?
    var tags: [Int]
    var notes: [Note]?
    var customFields: [CustomFieldEdit] = []
    /// Trefferinfo der Volltextsuche (`__search_hit__`), nur bei einer Suche gesetzt.
    var searchHit: SearchHit? = nil

    enum CodingKeys: String, CodingKey {
        case id, title, content, created, added, correspondent, tags, notes
        case documentType = "document_type"
        case archiveSerialNumber = "archive_serial_number"
        case customFields = "custom_fields"
        case searchHit = "__search_hit__"
    }

    var dateObject: Date? { DateFormatting.parseAPIDate(created) }

    var safeNotes: [Note] { notes ?? [] }
}

extension Document {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        content = try? c.decode(String.self, forKey: .content)
        created = (try? c.decode(String.self, forKey: .created)) ?? ""
        added = try? c.decode(String.self, forKey: .added)
        correspondent = try? c.decode(Int.self, forKey: .correspondent)
        documentType = try? c.decode(Int.self, forKey: .documentType)
        archiveSerialNumber = try? c.decode(Int.self, forKey: .archiveSerialNumber)
        tags = (try? c.decode([Int].self, forKey: .tags)) ?? []
        notes = try? c.decode([Note].self, forKey: .notes)
        customFields = (try? c.decode([CustomFieldEdit].self, forKey: .customFields)) ?? []
        searchHit = try? c.decode(SearchHit.self, forKey: .searchHit)
    }
}

/// Trefferinfo, die paperless-ngx bei `?query=` je Dokument mitliefert.
struct SearchHit: Codable, Hashable {
    var score: Double? = nil
    /// Textausschnitt mit Markierungen um die Treffer. Whoosh (ngx 2.x) liefert
    /// `<span class="match">…</span>`, Tantivy (3.0) eine andere Auszeichnung — deshalb wird
    /// hier nichts interpretiert, sondern nur die Auszeichnung entfernt.
    var highlights: String? = nil
    var noteHighlights: String? = nil
    var rank: Int? = nil

    enum CodingKeys: String, CodingKey {
        case score, highlights, rank
        case noteHighlights = "note_highlights"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `score` kommt je Version als Zahl oder als String.
        if let d = try? c.decodeIfPresent(Double.self, forKey: .score) {
            score = d
        } else if let s = try? c.decodeIfPresent(String.self, forKey: .score) {
            score = Double(s ?? "")
        }
        highlights = try? c.decodeIfPresent(String.self, forKey: .highlights)
        noteHighlights = try? c.decodeIfPresent(String.self, forKey: .noteHighlights)
        rank = try? c.decodeIfPresent(Int.self, forKey: .rank)
    }
}

extension Document {
    /// Ein Satz aus dem Dokument, in dem der Suchbegriff steht.
    ///
    /// Entscheidet darüber, ob man ein Dokument überhaupt öffnen muss — bis 2.1.4 zeigte die
    /// Trefferliste nur Titel und Sender. Bevorzugt wird der Ausschnitt des Servers; fehlt er
    /// (ältere Version, Offline-Suche), wird er aus dem erkannten Text gebildet.
    func searchSnippet(for query: String, maxLength: Int = 160) -> String? {
        if let raw = searchHit?.highlights ?? searchHit?.noteHighlights {
            let plain = Self.strippingMarkup(raw)
            if !plain.isEmpty { return String(plain.prefix(maxLength)) }
        }
        return Self.snippet(from: content, matching: query, maxLength: maxLength)
    }

    /// Entfernt die Auszeichnung aus dem Ausschnitt des Servers.
    static func strippingMarkup(_ raw: String) -> String {
        let withoutTags = raw.replacingOccurrences(
            of: "<[^>]+>", with: "", options: .regularExpression
        )
        return withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\u{0022}")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Schneidet um den ersten Treffer herum aus. Ohne Treffer der Anfang des Textes.
    static func snippet(from content: String?, matching query: String, maxLength: Int) -> String? {
        guard let content, !content.isEmpty else { return nil }
        let flat = content
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, let range = flat.range(of: term, options: .caseInsensitive) else {
            return String(flat.prefix(maxLength))
        }
        // Etwas Text vor dem Treffer, damit der Satz verständlich bleibt.
        let lead = 40
        let startOffset = max(0, flat.distance(from: flat.startIndex, to: range.lowerBound) - lead)
        let start = flat.index(flat.startIndex, offsetBy: startOffset)
        let snippet = String(flat[start...].prefix(maxLength))
        return (startOffset > 0 ? "…" : "") + snippet
    }
}

struct UploadContainer: Identifiable {
    let id = UUID()
    let data: Data
    let filename: String
}

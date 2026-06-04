import Foundation
import NaturalLanguage

/// Semantisches Ranking von Dokumenten gegen eine Suchanfrage (on-device Embeddings).
/// Findet inhaltlich passende Dokumente, auch wenn der Suchbegriff nicht wörtlich vorkommt.
enum SemanticRanker {
    static func rank(_ query: String, in docs: [Document], limit: Int = 60) -> [Document] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return docs }

        let embedding = NLEmbedding.sentenceEmbedding(for: .german)
            ?? NLEmbedding.sentenceEmbedding(for: .english)

        guard let embedding else {
            // Fallback ohne Embeddings: einfache Stichwortsuche.
            let low = q.lowercased()
            return docs.filter {
                $0.title.lowercased().contains(low) || ($0.content?.lowercased().contains(low) ?? false)
            }
        }

        let scored = docs.compactMap { doc -> (Document, Double)? in
            let text = doc.title + " " + (doc.content?.prefix(500).description ?? "")
            let dist = embedding.distance(between: q, and: text)
            // Distanz 2.0 = maximal unähnlich; alles darüber/ungültige ignorieren.
            return (dist.isFinite && dist < 1.6) ? (doc, dist) : nil
        }.sorted { $0.1 < $1.1 }

        return scored.prefix(limit).map { $0.0 }
    }
}

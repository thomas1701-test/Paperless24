import SwiftUI
import NaturalLanguage

/// „Frag dein Archiv": semantische Suche über geladene Dokumente + KI-Antwort.
struct AskArchiveView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @State private var question = ""
    @State private var answer: String?
    @State private var sources: [Document] = []
    @State private var isThinking = false
    @State private var statusText = ""
    @State private var openDoc: Document?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isThinking {
                            VStack(spacing: 12) {
                                ProgressView().scaleEffect(1.3)
                                Text(statusText.isEmpty ? "Einen Moment …" : statusText)
                                    .font(.subheadline).foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                        }
                        if let answer {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Antwort", systemImage: "sparkles").font(.headline).foregroundColor(palette.accent)
                                Text(answer).font(.body)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.accent.opacity(0.08)).cornerRadius(12)
                        }
                        if !sources.isEmpty {
                            Text("Gefundene Dokumente").font(.subheadline).foregroundColor(.secondary)
                            ForEach(sources) { doc in
                                Button {
                                    openDoc = doc
                                    store.registerReviewEvent()
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.text").foregroundColor(palette.accent)
                                        Text(doc.title).foregroundColor(.primary).lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                        if !AIService.shared.modelAvailable && answer != nil {
                            Text("Hinweis: Apple Intelligence ist auf diesem Gerät nicht verfügbar – es wird nur semantisch gesucht.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding()
                }

                HStack {
                    TextField("Frag dein Archiv …", text: $question)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await ask() } }
                    Button { Task { await ask() } } label: {
                        if isThinking {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill").font(.title2)
                        }
                    }
                    .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty || isThinking)
                }
                .padding()
            }
            .navigationTitle("Archiv fragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
            }
            .sheet(item: $openDoc) { doc in
                NavigationStack {
                    DocumentDetailView(doc: doc,
                                       onSave: { _, _, _, _, _, _, _, _ in },
                                       onDelete: { _ in })
                }
            }
        }
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isThinking = true
        answer = nil
        sources = []
        statusText = "Durchsuche dein Archiv …"
        let top = await rankedDocuments(for: q, limit: 5)
        sources = top

        if AIService.shared.isAvailable {
            statusText = "Formuliere Antwort … (kann einige Sekunden dauern)"
        }
        let context = top.map { doc in
            "Titel: \(doc.title)\nInhalt: \(doc.content?.prefix(1200) ?? "")"
        }.joined(separator: "\n\n---\n\n")
        if let llm = await AIService.shared.answer(question: q, context: context) {
            answer = llm
        } else {
            answer = top.isEmpty ? "Keine passenden Dokumente gefunden." : "Passende Dokumente unten."
        }
        statusText = ""
        isThinking = false
    }

    /// Ein Dokument, reduziert auf das, was für die Rangordnung nötig ist. Nur Werttypen,
    /// damit die Berechnung in einer eigenen Task laufen kann.
    private struct RankInput: Sendable {
        let id: Int
        /// Gekürzt — das Embedding wertet ohnehin nur den Anfang sinnvoll aus.
        let text: String
        /// Vollständiger Titel + Inhalt in Kleinschreibung, für die Stichwort-Rückfallebene.
        let haystack: String
    }

    /// Rangordnung per Satz-Embedding (Fallback: Stichwortsuche).
    ///
    /// Die Berechnung läuft abseits des Main Threads: `NLEmbedding.distance` wird für *jedes*
    /// Dokument aufgerufen, bei einem größeren Archiv blockierte das die Oberfläche mehrere
    /// Sekunden lang.
    private func rankedDocuments(for query: String, limit: Int) async -> [Document] {
        let docs = store.documents
        let account = store.activeAccountId

        // Zuerst der Index: Er kennt das ganze Archiv, nicht nur die geladene Seite. Was er
        // findet, muss aber auch als Dokument vorliegen — sonst fehlt der Text für die Antwort.
        let indexed = await ArchiveIndex.shared.bestMatches(for: query, limit: limit * 3, account: account)
        if !indexed.isEmpty {
            let matched = indexed.compactMap { id in docs.first { $0.id == id } }
            if matched.count >= min(limit, 3) { return Array(matched.prefix(limit)) }
            // Zu wenige davon geladen: die fehlenden einzeln nachholen.
            var result = matched
            for id in indexed where !result.contains(where: { $0.id == id }) {
                guard result.count < limit else { break }
                if let doc = await store.fetchDocumentDetail(id: id) { result.append(doc) }
            }
            if !result.isEmpty { return result }
        }

        let inputs = docs.map {
            RankInput(
                id: $0.id,
                text: $0.title + " " + ($0.content?.prefix(500) ?? ""),
                haystack: ($0.title + " " + ($0.content ?? "")).lowercased()
            )
        }

        let rankedIds = await Task.detached(priority: .userInitiated) { () -> [Int] in
            let embedding = NLEmbedding.sentenceEmbedding(for: .german)
                ?? NLEmbedding.sentenceEmbedding(for: .english)

            guard let embedding else {
                let q = query.lowercased()
                return inputs.filter { $0.haystack.contains(q) }.prefix(limit).map(\.id)
            }

            return inputs.compactMap { input -> (Int, Double)? in
                let dist = embedding.distance(between: query, and: input.text)
                return dist.isFinite ? (input.id, dist) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
        }.value

        // Reihenfolge der Rangordnung beibehalten.
        return rankedIds.compactMap { id in docs.first { $0.id == id } }
    }
}

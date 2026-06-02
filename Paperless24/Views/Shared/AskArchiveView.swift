import SwiftUI
import NaturalLanguage

/// „Frag dein Archiv": semantische Suche über geladene Dokumente + KI-Antwort.
struct AskArchiveView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var question = ""
    @State private var answer: String?
    @State private var sources: [Document] = []
    @State private var isThinking = false
    @State private var openDoc: Document?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isThinking {
                            HStack { ProgressView(); Text("Durchsuche dein Archiv …").foregroundColor(.secondary) }
                        }
                        if let answer {
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Antwort", systemImage: "sparkles").font(.headline).foregroundColor(.purple)
                                Text(answer).font(.body)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.08)).cornerRadius(12)
                        }
                        if !sources.isEmpty {
                            Text("Gefundene Dokumente").font(.subheadline).foregroundColor(.secondary)
                            ForEach(sources) { doc in
                                Button { openDoc = doc } label: {
                                    HStack {
                                        Image(systemName: "doc.text").foregroundColor(.blue)
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
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
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
                NavigationView {
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
        let top = rankedDocuments(for: q, limit: 5)
        sources = top
        let context = top.map { doc in
            "Titel: \(doc.title)\nInhalt: \(doc.content?.prefix(1200) ?? "")"
        }.joined(separator: "\n\n---\n\n")
        if let llm = await AIService.shared.answer(question: q, context: context) {
            answer = llm
        } else {
            answer = top.isEmpty ? "Keine passenden Dokumente gefunden." : "Passende Dokumente unten."
        }
        isThinking = false
    }

    /// Rangordnung per Satz-Embedding (Fallback: Stichwortsuche).
    private func rankedDocuments(for query: String, limit: Int) -> [Document] {
        let docs = store.documents
        let embedding = NLEmbedding.sentenceEmbedding(for: .german)
            ?? NLEmbedding.sentenceEmbedding(for: .english)

        guard let embedding else {
            let q = query.lowercased()
            return Array(docs.filter {
                $0.title.lowercased().contains(q) || ($0.content?.lowercased().contains(q) ?? false)
            }.prefix(limit))
        }

        let scored = docs.compactMap { doc -> (Document, Double)? in
            let text = doc.title + " " + (doc.content?.prefix(500).description ?? "")
            let dist = embedding.distance(between: query, and: text)
            return dist.isFinite ? (doc, dist) : nil
        }.sorted { $0.1 < $1.1 }
        return scored.prefix(limit).map { $0.0 }
    }
}

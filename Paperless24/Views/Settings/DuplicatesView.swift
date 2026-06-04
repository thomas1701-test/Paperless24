import SwiftUI

/// Findet mögliche Dubletten anhand von Titel- und Inhaltsähnlichkeit.
struct DuplicatesView: View {
    @EnvironmentObject var store: AppStore
    @State private var groups: [[Document]] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack { ProgressView(); Text("Analysiere …").foregroundColor(.secondary) }
            } else if groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle").font(.system(size: 44)).foregroundColor(.green)
                    Text("Keine Dubletten gefunden").foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                ForEach(groups.indices, id: \.self) { i in
                    Section("\(groups[i].count) ähnliche Dokumente") {
                        NavigationLink {
                            DuplicateCompareView(docs: groups[i])
                        } label: {
                            Label("Nebeneinander vergleichen", systemImage: "rectangle.split.2x1")
                                .foregroundColor(.accentColor)
                        }
                        ForEach(groups[i]) { doc in
                            NavigationLink {
                                DocumentDetailView(doc: doc,
                                                   onSave: { _, _, _, _, _, _, _, _ in },
                                                   onDelete: { store.deleteDocument(id: $0); recompute() })
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(doc.title).lineLimit(1)
                                    Text(String(doc.created.prefix(10))).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    store.deleteDocument(id: doc.id); recompute()
                                } label: { Label("Löschen", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Dubletten")
        .toolbar { Button { recompute() } label: { Image(systemName: "arrow.clockwise") } }
        .task { recompute() }
    }

    private func recompute() {
        isLoading = true
        let docs = store.documents
        Task.detached(priority: .userInitiated) {
            let result = Self.findGroups(docs)
            await MainActor.run { groups = result; isLoading = false }
        }
    }

    /// Greedy-Gruppierung nach Wort-Jaccard innerhalb Korrespondenten-Buckets.
    nonisolated static func findGroups(_ docs: [Document]) -> [[Document]] {
        func tokens(_ doc: Document) -> Set<String> {
            let s = (doc.title + " " + (doc.content?.prefix(800).description ?? "")).lowercased()
            return Set(s.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init).filter { $0.count > 2 })
        }
        func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
            guard !a.isEmpty, !b.isEmpty else { return 0 }
            let inter = a.intersection(b).count
            return Double(inter) / Double(a.union(b).count)
        }

        let buckets = Dictionary(grouping: docs) { $0.correspondent ?? -1 }
        var result: [[Document]] = []
        for (_, bucket) in buckets where bucket.count >= 2 && bucket.count <= 300 {
            let toks = bucket.map { ($0, tokens($0)) }
            var groups: [(rep: Set<String>, docs: [Document])] = []
            for (doc, t) in toks {
                if let idx = groups.firstIndex(where: { jaccard($0.rep, t) >= 0.65 }) {
                    groups[idx].docs.append(doc)
                } else {
                    groups.append((t, [doc]))
                }
            }
            result.append(contentsOf: groups.filter { $0.docs.count >= 2 }.map { $0.docs })
        }
        return result.sorted { $0.count > $1.count }
    }
}

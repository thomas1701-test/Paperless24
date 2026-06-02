import SwiftUI

/// „Habe ich das schon?" – Aufnahme per Kamera, OCR, Textabgleich gegen das Archiv.
struct DuplicateCheckView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = true
    @State private var isChecking = false
    @State private var done = false
    @State private var matches: [(doc: Document, score: Double)] = []
    @State private var openDoc: Document?

    var body: some View {
        NavigationView {
            Group {
                if isChecking {
                    VStack(spacing: 12) { ProgressView(); Text("Gleiche mit deinem Archiv ab …").foregroundColor(.secondary) }
                } else if done {
                    if matches.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.seal").font(.system(size: 50)).foregroundColor(.green)
                            Text("Nicht gefunden").font(.title3)
                            Text("Dieses Dokument scheint noch nicht im Archiv zu sein.")
                                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding()
                    } else {
                        List {
                            SwiftUI.Section {
                                Label("Mögliche Treffer gefunden", systemImage: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                            }
                            ForEach(matches, id: \.doc.id) { match in
                                Button { openDoc = match.doc } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(match.doc.title).foregroundColor(.primary).lineLimit(1)
                                            Text(String(match.doc.created.prefix(10))).font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text("\(Int(match.score * 100)) %").font(.caption).foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Color.clear
                }
            }
            .navigationTitle("Schon vorhanden?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
                if done {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button { done = false; matches = []; showScanner = true } label: { Image(systemName: "camera") }
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                PageScannerView(isPresented: $showScanner) { pages in
                    if let first = pages.first { check(first) } else if !done { dismiss() }
                }
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

    private func check(_ image: UIImage) {
        isChecking = true
        let docs = store.documents
        Task {
            let text = await OCRService.recognizeText(in: image)
            let result = Self.rank(text, in: docs)
            await MainActor.run {
                matches = result
                done = true
                isChecking = false
            }
        }
    }

    nonisolated static func rank(_ text: String, in docs: [Document]) -> [(doc: Document, score: Double)] {
        func tokens(_ s: String) -> Set<String> {
            Set(s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init).filter { $0.count > 2 })
        }
        let query = tokens(text)
        guard !query.isEmpty else { return [] }
        let scored = docs.compactMap { doc -> (Document, Double)? in
            let t = tokens(doc.title + " " + (doc.content?.prefix(800).description ?? ""))
            guard !t.isEmpty else { return nil }
            let score = Double(query.intersection(t).count) / Double(query.union(t).count)
            return score >= 0.3 ? (doc, score) : nil
        }
        return scored.sorted { $0.1 > $1.1 }.prefix(5).map { $0 }
    }
}

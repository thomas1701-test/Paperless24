import SwiftUI

/// Zeigt die Dokumente einer Dubletten-Gruppe nebeneinander zum Vergleich.
struct DuplicateCompareView: View {
    @EnvironmentObject var store: AppStore
    @State private var docs: [Document]
    @State private var openDoc: Document?

    init(docs: [Document]) {
        _docs = State(initialValue: docs)
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                ForEach(docs) { doc in
                    VStack(alignment: .leading, spacing: 6) {
                        AuthImage(docId: doc.id,
                                  urlString: store.thumbnailURL(for: doc.id),
                                  token: store.authToken(),
                                  contentMode: .fit)
                            .frame(height: 200)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                            .onTapGesture { openDoc = doc }

                        Text(doc.title).font(.caption).fontWeight(.medium).lineLimit(2)
                        Text(String(doc.created.prefix(10))).font(.caption2).foregroundColor(.secondary)
                        if let corr = store.allCorrespondents.first(where: { $0.id == doc.correspondent }) {
                            Text(corr.safeName).font(.caption2).foregroundColor(.secondary)
                        }
                        if let c = doc.content, !c.isEmpty {
                            Text(c.prefix(120) + "…").font(.caption2).foregroundColor(.secondary).lineLimit(3)
                        }
                        HStack {
                            Button { openDoc = doc } label: { Label("Öffnen", systemImage: "eye") }
                            Spacer()
                            Button(role: .destructive) { delete(doc) } label: { Image(systemName: "trash") }
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                    .padding(8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(10)
                }
            }
            .padding()
        }
        .navigationTitle("Vergleich")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .sheet(item: $openDoc) { doc in
            NavigationView {
                DocumentDetailView(doc: doc,
                                   onSave: { _, _, _, _, _, _, _, _ in },
                                   onDelete: { id in store.deleteDocument(id: id); remove(id); openDoc = nil })
            }
        }
    }

    private func delete(_ doc: Document) {
        store.deleteDocument(id: doc.id)
        remove(doc.id)
    }

    private func remove(_ id: Int) {
        docs.removeAll { $0.id == id }
    }
}

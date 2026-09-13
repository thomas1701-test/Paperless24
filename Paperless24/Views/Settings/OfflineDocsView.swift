import SwiftUI

struct OfflineDocsView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var store: AppStore
    @State private var selectedDoc: Document? = nil
    /// Einmal ermittelt. Vorher prüfte jede Body-Auswertung für jedes geladene Dokument die Platte
    /// (samt `createDirectory`) — dreimal, weil die Liste an drei Stellen gelesen wurde.
    @State private var offlineDocs: [Document] = []

    private func refresh() {
        guard let accountId = store.activeAccountId else { offlineDocs = []; return }
        let docs = store.documents
        Task {
            offlineDocs = await Task.detached(priority: .userInitiated) {
                docs.filter { PersistenceService.fileExists(docId: $0.id, accountId: accountId) }
            }.value
        }
    }

    var body: some View {
        List {
            if offlineDocs.isEmpty { Text("Keine Downloads").foregroundColor(.gray) }
            ForEach(offlineDocs) { doc in
                NavigationLink(destination: DocumentDetailView(
                    doc: doc,
                    onSave: { id, title, date, corr, type, asn, tags, customFields in
                        store.addPendingEdit(docId: id, title: title, created: date, corr: corr, type: type, asn: asn, tags: tags, customFields: customFields)
                    },
                    onDelete: { store.deleteDocument(id: $0) }
                )) {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill").foregroundColor(.green)
                        Text(doc.title)
                    }
                }
            }
            .onDelete(perform: deleteLocal)
        }
        .themedSurface(palette)
        .navigationTitle("Offline Dateien")
        .onAppear(perform: refresh)
    }

    private func deleteLocal(at offsets: IndexSet) {
        let ids = offsets.map { offlineDocs[$0].id }
        for id in ids { store.deleteLocalFile(docId: id) }
        offlineDocs.removeAll { ids.contains($0.id) }
    }
}

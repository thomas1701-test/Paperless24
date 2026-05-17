import SwiftUI

struct OfflineDocsView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedDoc: Document? = nil

    var offlineDocs: [Document] {
        store.documents.filter { store.fileExists(docId: $0.id) }
    }

    var body: some View {
        List {
            if offlineDocs.isEmpty { Text("Keine Downloads").foregroundColor(.gray) }
            ForEach(offlineDocs) { doc in
                NavigationLink(destination: DocumentDetailView(
                    doc: doc,
                    onSave: { id, title, date, corr, type, asn, tags in
                        store.addPendingEdit(docId: id, title: title, created: date, corr: corr, type: type, asn: asn, tags: tags)
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
        .navigationTitle("Offline Dateien")
    }

    private func deleteLocal(at offsets: IndexSet) {
        for index in offsets { store.deleteLocalFile(docId: offlineDocs[index].id) }
    }
}

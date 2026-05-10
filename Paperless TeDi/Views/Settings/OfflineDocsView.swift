import SwiftUI

struct OfflineDocsView: View {
    @EnvironmentObject var store: AppStore

    var offlineDocs: [Document] {
        store.documents.filter { store.fileExists(docId: $0.id) }
    }

    var body: some View {
        List {
            if offlineDocs.isEmpty { Text("Keine Downloads").foregroundColor(.gray) }
            ForEach(offlineDocs) { doc in
                HStack {
                    Image(systemName: "arrow.down.doc.fill").foregroundColor(.green)
                    Text(doc.title)
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

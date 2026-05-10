import SwiftUI

struct PendingQueueView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section(header: Text("Uploads")) {
                if store.pendingUploads.isEmpty { Text("Leer").foregroundColor(.secondary) }
                ForEach(store.pendingUploads) { item in
                    HStack {
                        Image(systemName: "doc")
                        Text(item.title)
                        Spacer()
                        Image(systemName: "clock").foregroundColor(.orange)
                    }
                }
                .onDelete(perform: store.removePendingUpload)
            }
            Section(header: Text("Bearbeitungen")) {
                if store.pendingEdits.isEmpty { Text("Leer").foregroundColor(.secondary) }
                ForEach(store.pendingEdits) { item in
                    HStack {
                        Image(systemName: "pencil")
                        Text(item.title)
                        Spacer()
                        Image(systemName: "clock").foregroundColor(.blue)
                    }
                }
                .onDelete(perform: store.removePendingEdit)
            }
        }
        .navigationTitle("Warteschlange")
    }
}

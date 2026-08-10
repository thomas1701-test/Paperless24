import SwiftUI

/// Papierkorb: gelöschte Dokumente wiederherstellen oder endgültig löschen.
struct TrashView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var store: AppStore
    @State private var isLoading = true
    @State private var selection = Set<Int>()
    @State private var showEmptyConfirm = false
    @State private var emptyTargets: [Int] = []

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Lädt...")
            } else if store.trashedDocs.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "trash").font(.system(size: 50)).foregroundColor(.gray)
                    Text("Papierkorb ist leer").foregroundColor(.gray)
                }
            } else {
                List(selection: $selection) {
                    ForEach(store.trashedDocs) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.safeTitle).font(.body)
                            if let deleted = item.deletedAt {
                                Text("gelöscht: \(String(deleted.prefix(10)))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                store.restoreFromTrash(ids: [item.id])
                            } label: { Label("Wiederherstellen", systemImage: "arrow.uturn.backward") }
                            .tint(.green)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                emptyTargets = [item.id]; showEmptyConfirm = true
                            } label: { Label("Löschen", systemImage: "trash") }
                        }
                    }
                }
                .environment(\.editMode, .constant(.active))
            }
        }
        .themedSurface(palette)
        .navigationTitle("Papierkorb")
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !selection.isEmpty {
                    Button {
                        store.restoreFromTrash(ids: Array(selection)); selection.removeAll()
                    } label: { Image(systemName: "arrow.uturn.backward") }
                    Button(role: .destructive) {
                        emptyTargets = Array(selection); showEmptyConfirm = true
                    } label: { Image(systemName: "trash") }
                } else if !store.trashedDocs.isEmpty {
                    Button(role: .destructive) {
                        emptyTargets = store.trashedDocs.map { $0.id }; showEmptyConfirm = true
                    } label: { Text("Alle leeren") }
                }
            }
        }
        .confirmationDialog("Endgültig löschen?", isPresented: $showEmptyConfirm, titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) {
                store.emptyTrash(ids: emptyTargets)
                selection.removeAll()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("\(emptyTargets.count) Dokument(e) können nicht wiederhergestellt werden.")
        }
        .task {
            await store.loadTrash()
            isLoading = false
        }
    }
}

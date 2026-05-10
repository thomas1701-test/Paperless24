import SwiftUI

struct TagListView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSheet = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(store.allTags) { tag in
                HStack {
                    Circle().fill(Color(hex: tag.safeColor)).frame(width: 10, height: 10)
                    Text(tag.safeName)
                }
            }
            .onDelete { offsets in
                offsets.forEach { store.deleteTag(id: store.allTags[$0].id) }
            }
        }
        .navigationTitle("Tags")
        .toolbar {
            Button { showSheet = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showSheet) {
            SimpleInputSheet(title: "Neuer Tag", text: $newName, onSave: {
                Task { _ = await store.createTag(name: newName) }
                showSheet = false
            }, onCancel: { showSheet = false })
        }
    }
}

struct CorrespondentListView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSheet = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(store.allCorrespondents) { c in Text(c.safeName) }
                .onDelete { offsets in
                    offsets.forEach { store.deleteCorrespondent(id: store.allCorrespondents[$0].id) }
                }
        }
        .navigationTitle("Sender")
        .toolbar {
            Button { showSheet = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showSheet) {
            SimpleInputSheet(title: "Neuer Sender", text: $newName, onSave: {
                Task { _ = await store.createCorrespondent(name: newName) }
                showSheet = false
            }, onCancel: { showSheet = false })
        }
    }
}

struct DocTypeListView: View {
    @EnvironmentObject var store: AppStore
    @State private var showSheet = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(store.allDocTypes) { t in Text(t.safeName) }
                .onDelete { offsets in
                    offsets.forEach { store.deleteDocumentType(id: store.allDocTypes[$0].id) }
                }
        }
        .navigationTitle("Typen")
        .toolbar {
            Button { showSheet = true } label: { Image(systemName: "plus") }
        }
        .sheet(isPresented: $showSheet) {
            SimpleInputSheet(title: "Neuer Typ", text: $newName, onSave: {
                Task { _ = await store.createDocumentType(name: newName) }
                showSheet = false
            }, onCancel: { showSheet = false })
        }
    }
}

struct ChangelogView: View {
    var body: some View {
        List(AppConstants.appChangelog) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("v\(entry.version)").font(.headline)
                    Spacer()
                    Text(entry.date).font(.caption).foregroundColor(.secondary)
                }
                ForEach(entry.changes, id: \.self) { change in
                    Text("• \(change)").font(.subheadline)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Changelog")
    }
}

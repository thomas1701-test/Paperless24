import SwiftUI

struct TagListView: View {
    @Environment(\.palette) private var palette
    @EnvironmentObject var store: AppStore
    @State private var showSheet = false
    @State private var newName = ""
    @State private var searchText = ""

    private var displayedTags: [(tag: Tag, depth: Int)] {
        guard !searchText.isEmpty else { return store.hierarchicalTags() }
        return store.allTags
            .filter { $0.safeName.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.safeName.localizedCompare($1.safeName) == .orderedAscending }
            .map { ($0, 0) }
    }

    var body: some View {
        List {
            ForEach(displayedTags, id: \.tag.id) { entry in
                HStack {
                    if entry.depth > 0 {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2).foregroundColor(.secondary)
                            .padding(.leading, CGFloat(entry.depth - 1) * 16)
                    }
                    Circle().fill(Color(hex: entry.tag.safeColor)).frame(width: 10, height: 10)
                    Text(entry.tag.safeName)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.deleteTag(id: entry.tag.id)
                    } label: { Label("Löschen", systemImage: "trash") }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Tag suchen")
        .themedSurface(palette)
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
    @Environment(\.palette) private var palette
    @EnvironmentObject var store: AppStore
    @State private var showSheet = false
    @State private var newName = ""
    @State private var searchText = ""

    private var filtered: [Correspondent] {
        guard !searchText.isEmpty else { return store.allCorrespondents }
        return store.allCorrespondents.filter { $0.safeName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            ForEach(filtered) { c in
                Text(c.safeName)
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteCorrespondent(id: c.id)
                        } label: { Label("Löschen", systemImage: "trash") }
                    }
            }
        }
        .searchable(text: $searchText, prompt: "Sender suchen")
        .themedSurface(palette)
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
    @Environment(\.palette) private var palette
    @EnvironmentObject var store: AppStore
    @State private var showSheet = false
    @State private var newName = ""
    @State private var searchText = ""

    private var filtered: [DocumentType] {
        guard !searchText.isEmpty else { return store.allDocTypes }
        return store.allDocTypes.filter { $0.safeName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            ForEach(filtered) { t in
                Text(t.safeName)
                    .swipeActions {
                        Button(role: .destructive) {
                            store.deleteDocumentType(id: t.id)
                        } label: { Label("Löschen", systemImage: "trash") }
                    }
            }
        }
        .searchable(text: $searchText, prompt: "Typ suchen")
        .themedSurface(palette)
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
    @Environment(\.palette) private var palette
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
        .themedSurface(palette)
        .navigationTitle("Changelog")
    }
}

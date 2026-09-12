import SwiftUI

/// Eigene Felder anlegen, umbenennen und löschen.
///
/// Die API kann das längst; die App konnte Felder bisher nur lesen und befüllen.
struct CustomFieldListView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    @State private var showNew = false
    @State private var newName = ""
    @State private var newType: CustomFieldType = .string
    @State private var newOptions = ""
    @State private var renaming: CustomField? = nil
    @State private var renameText = ""
    @State private var deleting: CustomField? = nil
    @State private var isWorking = false
    @State private var searchText = ""

    private var filtered: [CustomField] {
        guard !searchText.isEmpty else { return store.allCustomFields }
        return store.allCustomFields.filter { $0.safeName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List {
            Section {
                ForEach(filtered) { field in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.safeName)
                            Text(field.type.label).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if field.type == .select,
                           let options = field.extraData?.selectOptions, !options.isEmpty {
                            Text("\(options.count) Optionen")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .contextMenu {
                        Button {
                            renameText = field.safeName
                            renaming = field
                        } label: { Label("Umbenennen", systemImage: "pencil") }
                        Button(role: .destructive) { deleting = field } label: {
                            Label("Löschen", systemImage: "trash")
                        }
                    }
                }
                if filtered.isEmpty {
                    Text(searchText.isEmpty ? "Keine eigenen Felder" : "Kein Treffer")
                        .foregroundColor(.secondary)
                }
            } footer: {
                Text("Der Datentyp lässt sich nachträglich nicht ändern — das gibt der Server "
                     + "nicht her. Löschen entfernt das Feld samt Werten aus allen Dokumenten.")
            }
        }
        .searchable(text: $searchText, prompt: "Feld suchen")
        .themedSurface(palette)
        .navigationTitle("Eigene Felder")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { newName = ""; newType = .string; newOptions = ""; showNew = true } label: {
                    Image(systemName: "plus")
                }
                .disabled(store.isDemoMode)
            }
        }
        .task { await store.syncCustomFields() }
        .sheet(isPresented: $showNew) { newFieldSheet }
        .alert("Umbenennen", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Abbrechen", role: .cancel) { renaming = nil }
            Button("Speichern") {
                guard let field = renaming else { return }
                let name = renameText
                renaming = nil
                Task { await store.renameCustomField(id: field.id, to: name) }
            }
        }
        .alert("Feld löschen?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }
        )) {
            Button("Abbrechen", role: .cancel) { deleting = nil }
            Button("Löschen", role: .destructive) {
                guard let field = deleting else { return }
                deleting = nil
                Task { await store.deleteCustomField(id: field.id) }
            }
        } message: {
            Text("Die Werte dieses Feldes verschwinden damit aus allen Dokumenten.")
        }
    }

    private var newFieldSheet: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z. B. Fälligkeit", text: $newName)
                }
                Section("Typ") {
                    Picker("Typ", selection: $newType) {
                        ForEach([CustomFieldType.string, .date, .integer, .float, .monetary,
                                 .boolean, .url, .select, .documentlink], id: \.rawValue) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                if newType == .select {
                    Section {
                        TextField("Optionen, mit Komma getrennt", text: $newOptions)
                    } footer: {
                        Text("Beispiel: offen, bezahlt, storniert")
                    }
                }
            }
            .navigationTitle("Neues Feld")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { showNew = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let options = newOptions
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                        let type = newType
                        showNew = false
                        Task {
                            isWorking = true
                            await store.createCustomField(name: name, type: type, selectOptions: options)
                            isWorking = false
                        }
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
                }
            }
        }
    }
}

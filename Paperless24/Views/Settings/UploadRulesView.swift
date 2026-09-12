import SwiftUI

/// Regeln zum Vorbelegen des Importformulars.
struct UploadRulesView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    @State private var editing: UploadRule? = nil

    var body: some View {
        List {
            Section {
                ForEach(store.uploadRules) { rule in
                    Button { editing = rule } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(rule.name.isEmpty ? "Ohne Namen" : rule.name)
                                    .foregroundColor(.primary)
                                if !rule.isEnabled {
                                    Text("aus").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Text(describe(rule)).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { store.uploadRules.remove(atOffsets: $0); store.saveUploadRules() }
                .onMove { store.uploadRules.move(fromOffsets: $0, toOffset: $1); store.saveUploadRules() }

                if store.uploadRules.isEmpty {
                    Text("Keine Regeln").foregroundColor(.secondary)
                }
            } header: {
                Text("Regeln")
            } footer: {
                Text("Die erste passende Regel gewinnt — „Jeder Import\u{201C} gehört deshalb "
                     + "ans Ende. Vorbelegt wird nur, was im Formular noch leer ist; "
                     + "gespeichert wird erst mit dem Hochladen.")
            }
        }
        .themedSurface(palette)
        .navigationTitle("Import-Regeln")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editing = UploadRule() } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .navigationBarLeading) { EditButton() }
        }
        .sheet(item: $editing) { rule in
            UploadRuleEditor(rule: rule) { saved in
                if let index = store.uploadRules.firstIndex(where: { $0.id == saved.id }) {
                    store.uploadRules[index] = saved
                } else {
                    store.uploadRules.append(saved)
                }
                store.saveUploadRules()
            }
        }
    }

    private func describe(_ rule: UploadRule) -> String {
        var parts: [String] = []
        switch rule.trigger {
        case .anyImport: parts.append("jeder Import")
        case .filenameContains: parts.append("Name enthält „\(rule.pattern)\u{201C}")
        }
        if let id = rule.correspondent,
           let name = store.allCorrespondents.first(where: { $0.id == id })?.safeName {
            parts.append(name)
        }
        if let id = rule.documentType,
           let name = store.allDocTypes.first(where: { $0.id == id })?.safeName {
            parts.append(name)
        }
        if !rule.tags.isEmpty { parts.append("\(rule.tags.count) Tag(s)") }
        return parts.joined(separator: " · ")
    }
}

private struct UploadRuleEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State var rule: UploadRule
    let onSave: (UploadRule) -> Void

    @State private var showCorrPicker = false
    @State private var showTypePicker = false
    @State private var showTagPicker = false
    @State private var tagSelection = Set<Int>()

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z. B. Kontoauszüge", text: $rule.name)
                    Toggle("Aktiv", isOn: $rule.isEnabled)
                }

                Section("Wann") {
                    Picker("Auslöser", selection: $rule.trigger) {
                        ForEach(UploadRule.Trigger.allCases) { Text($0.label).tag($0) }
                    }
                    if rule.trigger == .filenameContains {
                        TextField("Textteil im Dateinamen", text: $rule.pattern)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }

                Section {
                    Button {
                        showCorrPicker = true
                    } label: {
                        pickerLabel("Sender", value: rule.correspondent.flatMap { id in
                            store.allCorrespondents.first { $0.id == id }?.safeName
                        })
                    }
                    Button {
                        showTypePicker = true
                    } label: {
                        pickerLabel("Typ", value: rule.documentType.flatMap { id in
                            store.allDocTypes.first { $0.id == id }?.safeName
                        })
                    }
                    Button {
                        tagSelection = Set(rule.tags)
                        showTagPicker = true
                    } label: {
                        pickerLabel("Tags", value: rule.tags.isEmpty ? nil : "\(rule.tags.count)")
                    }
                } header: {
                    Text("Was vorbelegt wird")
                }

                Section {
                    TextField("Titel-Vorlage", text: $rule.titleTemplate)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Leer lassen, um den Dateinamen zu behalten. "
                         + "{dateiname} und {datum} werden ersetzt.")
                }
            }
            .navigationTitle(rule.name.isEmpty ? "Neue Regel" : rule.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { onSave(rule); dismiss() }
                }
            }
            .sheet(isPresented: $showCorrPicker) {
                FilterPickerSheet(
                    title: "Sender",
                    items: store.allCorrespondents.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                    noneLabel: "Keiner", selectedId: $rule.correspondent
                )
            }
            .sheet(isPresented: $showTypePicker) {
                FilterPickerSheet(
                    title: "Typ",
                    items: store.allDocTypes.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                    noneLabel: "Keiner", selectedId: $rule.documentType
                )
            }
            .sheet(isPresented: $showTagPicker, onDismiss: { rule.tags = Array(tagSelection) }) {
                MultiSelectPickerSheet(
                    title: "Tags",
                    items: store.allTags.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                    colors: Dictionary(store.allTags.map { ($0.id, $0.safeColor) },
                                       uniquingKeysWith: { a, _ in a }),
                    selected: $tagSelection
                )
            }
        }
    }

    private func pickerLabel(_ title: String, value: String?) -> some View {
        HStack {
            Text(title).foregroundColor(.primary)
            Spacer()
            Text(value ?? "—").foregroundColor(.secondary)
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
    }
}

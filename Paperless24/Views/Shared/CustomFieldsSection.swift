import SwiftUI

/// Editierbare Custom-Field-Sektion für das Bearbeiten-Formular. Rendert je nach Feldtyp
/// das passende Eingabe-Element und schreibt Änderungen zurück in `values`.
struct CustomFieldsSection: View {
    @EnvironmentObject var store: AppStore
    @Binding var values: [CustomFieldEdit]
    @Environment(\.palette) private var palette

    @State private var linkPickerField: CustomField? = nil

    var body: some View {
        if !store.allCustomFields.isEmpty {
            Section("Felder") {
                ForEach(store.allCustomFields) { field in
                    row(for: field)
                }
            }
            .sheet(item: $linkPickerField) { field in
                DocumentLinkPickerSheet(selected: intsBinding(field))
            }
        }
    }

    @ViewBuilder
    private func row(for field: CustomField) -> some View {
        switch field.type {
        case .string:
            LabeledContent(field.safeName) {
                TextField("", text: textBinding(field)).multilineTextAlignment(.trailing)
            }
        case .url:
            LabeledContent(field.safeName) {
                TextField("https://", text: textBinding(field))
                    .keyboardType(.URL).autocapitalization(.none)
                    .multilineTextAlignment(.trailing)
            }
        case .integer:
            LabeledContent(field.safeName) {
                TextField("0", text: numberBinding(field, isInt: true))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
        case .float:
            LabeledContent(field.safeName) {
                TextField("0", text: numberBinding(field, isInt: false))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        case .monetary:
            LabeledContent(field.safeName) {
                TextField(field.extraData?.defaultCurrency ?? "0,00", text: textBinding(field))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
        case .boolean:
            Toggle(field.safeName, isOn: boolBinding(field))
        case .date:
            DatePicker(field.safeName, selection: dateBinding(field), displayedComponents: .date)
        case .select:
            Picker(field.safeName, selection: selectBinding(field)) {
                Text("—").tag("")
                ForEach(field.extraData?.selectOptions ?? []) { opt in
                    Text(opt.safeLabel).tag(opt.id ?? opt.safeLabel)
                }
            }
        case .documentlink:
            Button {
                linkPickerField = field
            } label: {
                HStack {
                    Text(field.safeName).foregroundColor(.primary)
                    Spacer()
                    Text(linkSummary(field)).foregroundColor(.secondary).font(.caption).lineLimit(1)
                    Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                }
            }
        }
    }

    // MARK: - Bindings

    private func value(_ field: CustomField) -> CFValue {
        values.first(where: { $0.field == field.id })?.value ?? .none
    }

    private func setValue(_ field: CustomField, _ newValue: CFValue) {
        if let idx = values.firstIndex(where: { $0.field == field.id }) {
            values[idx].value = newValue
        } else {
            values.append(CustomFieldEdit(field: field.id, value: newValue))
        }
    }

    private func textBinding(_ field: CustomField) -> Binding<String> {
        Binding(
            get: { if case .text(let s) = value(field) { return s }; return "" },
            set: { setValue(field, $0.isEmpty ? .none : .text($0)) }
        )
    }

    private func numberBinding(_ field: CustomField, isInt: Bool) -> Binding<String> {
        Binding(
            get: {
                switch value(field) {
                case .integer(let i): return "\(i)"
                case .number(let d): return String(format: "%g", d)
                default: return ""
                }
            },
            set: { raw in
                if raw.isEmpty { setValue(field, .none); return }
                if isInt, let i = Int(raw) { setValue(field, .integer(i)) }
                else if let d = Double(raw.replacingOccurrences(of: ",", with: ".")) { setValue(field, .number(d)) }
            }
        )
    }

    private func boolBinding(_ field: CustomField) -> Binding<Bool> {
        Binding(
            get: { if case .bool(let b) = value(field) { return b }; return false },
            set: { setValue(field, .bool($0)) }
        )
    }

    /// Über `DateFormatting` statt eines eigenen `DateFormatter`: Der ließ Kalender und Locale
    /// offen — mit buddhistischem oder japanischem Kalender entstand ein falsches Jahr.
    private func dateBinding(_ field: CustomField) -> Binding<Date> {
        Binding(
            get: { if case .text(let s) = value(field), let d = DateFormatting.parseAPIDate(s) { return d }; return Date() },
            set: { setValue(field, .text(DateFormatting.apiDate($0))) }
        )
    }

    private func selectBinding(_ field: CustomField) -> Binding<String> {
        Binding(
            get: { if case .text(let s) = value(field) { return s }; return "" },
            set: { setValue(field, $0.isEmpty ? .none : .text($0)) }
        )
    }

    private func intsBinding(_ field: CustomField) -> Binding<[Int]> {
        Binding(
            get: { if case .ints(let a) = value(field) { return a }; return [] },
            set: { setValue(field, $0.isEmpty ? .none : .ints($0)) }
        )
    }

    private func linkSummary(_ field: CustomField) -> String {
        if case .ints(let ids) = value(field), !ids.isEmpty {
            return "\(ids.count) verknüpft"
        }
        return "Keine"
    }
}

/// Mehrfach-Auswahl von Dokumenten für ein documentlink-Custom-Field.
struct DocumentLinkPickerSheet: View {
    @EnvironmentObject var store: AppStore
    @Binding var selected: [Int]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var searchText = ""

    private var filtered: [Document] {
        guard !searchText.isEmpty else { return store.documents }
        return store.documents.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { doc in
                Button {
                    if let idx = selected.firstIndex(of: doc.id) { selected.remove(at: idx) }
                    else { selected.append(doc.id) }
                } label: {
                    HStack {
                        Text(doc.title).foregroundColor(.primary).lineLimit(1)
                        Spacer()
                        if selected.contains(doc.id) {
                            Image(systemName: "checkmark").foregroundColor(palette.accent)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Dokument suchen")
            .navigationTitle("Verknüpfen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}

import SwiftUI

/// Filter nach einem Custom Field: Feld wählen, optional nach Textwert eingrenzen.
struct CustomFieldFilterSheet: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedField: Int?
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Feld") {
                    Picker("Feld", selection: $selectedField) {
                        Text("Kein Filter").tag(Int?.none)
                        ForEach(store.allCustomFields) { field in
                            Text(field.safeName).tag(field.id as Int?)
                        }
                    }
                }
                if selectedField != nil {
                    Section("Enthält Text (optional)") {
                        TextField("z. B. Wert", text: $text)
                    }
                }
            }
            .navigationTitle("Feld-Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zurücksetzen") {
                        selectedField = nil; text = ""; dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

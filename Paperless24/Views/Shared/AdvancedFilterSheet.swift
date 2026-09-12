import SwiftUI

/// Mehrfach- und Negativfilter.
///
/// Bewusst getrennt von den Schnellfilter-Chips: Die Chips halten je Kategorie *einen* Wert,
/// tragen die Beschriftung der Leiste und werden von den gespeicherten Server-Ansichten
/// gesetzt. Beides in ein Steuerelement zu pressen hätte beide Aufgaben verschlechtert.
/// `AppStore.activeQuery` führt Chip-Auswahl und die Mengen von hier zusammen.
struct AdvancedFilterSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    @Binding var tags: Set<Int>
    @Binding var excludedTags: Set<Int>
    @Binding var correspondents: Set<Int>
    @Binding var documentTypes: Set<Int>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    pickerRow("Alle diese Tags", systemImage: "tag", selection: tags) {
                        MultiSelectPickerSheet(
                            title: "Alle diese Tags",
                            items: store.allTags.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                            colors: Dictionary(store.allTags.map { ($0.id, $0.safeColor) },
                                               uniquingKeysWith: { a, _ in a }),
                            selected: $tags
                        )
                    }
                    pickerRow("Keiner dieser Tags", systemImage: "tag.slash", selection: excludedTags) {
                        MultiSelectPickerSheet(
                            title: "Keiner dieser Tags",
                            items: store.allTags.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                            colors: Dictionary(store.allTags.map { ($0.id, $0.safeColor) },
                                               uniquingKeysWith: { a, _ in a }),
                            selected: $excludedTags
                        )
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("„Alle diese Tags“ verlangt jeden ausgewählten Tag am Dokument, nicht irgendeinen.")
                }

                Section("Sender") {
                    pickerRow("Einer dieser Sender", systemImage: "person", selection: correspondents) {
                        MultiSelectPickerSheet(
                            title: "Sender",
                            items: store.allCorrespondents.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                            selected: $correspondents
                        )
                    }
                }

                Section("Typen") {
                    pickerRow("Einer dieser Typen", systemImage: "doc.text", selection: documentTypes) {
                        MultiSelectPickerSheet(
                            title: "Typen",
                            items: store.allDocTypes.map { FilterPickerItem(id: $0.id, name: $0.safeName) },
                            selected: $documentTypes
                        )
                    }
                }

                if count > 0 {
                    Section {
                        Button(role: .destructive) {
                            tags = []; excludedTags = []; correspondents = []; documentTypes = []
                        } label: {
                            Label("Alle zurücksetzen", systemImage: "xmark.circle.fill")
                        }
                    }
                }
            }
            .navigationTitle("Mehr Filter")
            .navigationBarTitleDisplayMode(.inline)
            .themedSurface(palette)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }

    private var count: Int {
        tags.count + excludedTags.count + correspondents.count + documentTypes.count
    }

    private func pickerRow<Sheet: View>(
        _ title: String, systemImage: String, selection: Set<Int>,
        @ViewBuilder sheet: () -> Sheet
    ) -> some View {
        NavigationLink {
            sheet()
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                if selection.isEmpty {
                    Text("Alle").foregroundColor(.secondary)
                } else {
                    Text("\(selection.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Capsule().fill(palette.accent.opacity(0.18)))
                        .foregroundColor(palette.accent)
                }
            }
        }
    }
}

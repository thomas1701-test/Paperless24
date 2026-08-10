import SwiftUI

/// Durchsuchbare Mehrfachauswahl (z. B. Tags). Pendant zu `FilterPickerSheet`,
/// aber mit `Set<Int>`-Binding und Häkchen-Toggle statt Einfachauswahl.
struct MultiSelectPickerSheet: View {
    let title: String
    let items: [FilterPickerItem]
    /// Optionale Farbe je id (Hex), z. B. Tag-Farbe für den Farbpunkt.
    var colors: [Int: String] = [:]
    @Binding var selected: Set<Int>
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var searchText = ""

    private var filtered: [FilterPickerItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { item in
                Button {
                    if selected.contains(item.id) { selected.remove(item.id) }
                    else { selected.insert(item.id) }
                } label: {
                    HStack {
                        if let hex = colors[item.id] {
                            Circle().fill(Color(hex: hex)).frame(width: 12, height: 12)
                        }
                        Text(item.name)
                        Spacer()
                        if selected.contains(item.id) {
                            Image(systemName: "checkmark").foregroundColor(palette.accent)
                        }
                    }
                }
                .foregroundColor(.primary)
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "\(title) suchen")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

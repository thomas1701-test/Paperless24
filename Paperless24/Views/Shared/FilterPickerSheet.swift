import SwiftUI

struct FilterPickerItem: Identifiable {
    let id: Int
    let name: String
}

struct FilterPickerSheet: View {
    let title: String
    let items: [FilterPickerItem]
    var noneLabel: String = "Alle"
    @Binding var selectedId: Int?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State private var searchText = ""

    private var filtered: [FilterPickerItem] {
        guard !searchText.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    selectedId = nil
                    dismiss()
                } label: {
                    HStack {
                        Text(noneLabel)
                        Spacer()
                        if selectedId == nil {
                            Image(systemName: "checkmark").foregroundColor(palette.accent)
                        }
                    }
                }
                .foregroundColor(.primary)

                ForEach(filtered) { item in
                    Button {
                        selectedId = item.id
                        dismiss()
                    } label: {
                        HStack {
                            Text(item.name)
                            Spacer()
                            if selectedId == item.id {
                                Image(systemName: "checkmark").foregroundColor(palette.accent)
                            }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "\(title) suchen")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

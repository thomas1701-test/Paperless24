import SwiftUI

struct QuickTagSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let doc: Document

    @State private var selectedTags: Set<Int>
    @State private var selectedCorrespondent: Int?
    @State private var assignMode = 0

    init(doc: Document) {
        self.doc = doc
        _selectedTags = State(initialValue: Set(doc.tags))
        _selectedCorrespondent = State(initialValue: doc.correspondent)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("Modus", selection: $assignMode) {
                    Text("Tags").tag(0)
                    Text("Sender").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if assignMode == 0 {
                    List(store.allTags) { tag in
                        Button {
                            store.haptic(.light)
                            if selectedTags.contains(tag.id) { selectedTags.remove(tag.id) }
                            else { selectedTags.insert(tag.id) }
                        } label: {
                            HStack {
                                Circle().fill(Color(hex: tag.safeColor)).frame(width: 12, height: 12)
                                Text(tag.safeName).foregroundColor(.primary)
                                Spacer()
                                if selectedTags.contains(tag.id) {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    List {
                        Button {
                            store.haptic(.light)
                            selectedCorrespondent = nil
                        } label: {
                            HStack {
                                Text("Kein Sender").foregroundColor(.primary).italic()
                                Spacer()
                                if selectedCorrespondent == nil {
                                    Image(systemName: "checkmark").foregroundColor(.accentColor)
                                }
                            }
                        }
                        ForEach(store.allCorrespondents) { corr in
                            Button {
                                store.haptic(.light)
                                selectedCorrespondent = corr.id
                            } label: {
                                HStack {
                                    Text(corr.safeName).foregroundColor(.primary)
                                    Spacer()
                                    if selectedCorrespondent == corr.id {
                                        Image(systemName: "checkmark").foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Schnellzuweisung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        store.addPendingEdit(
                            docId: doc.id, title: doc.title,
                            created: doc.dateObject ?? Date(),
                            corr: selectedCorrespondent, type: doc.documentType,
                            asn: doc.archiveSerialNumber, tags: Array(selectedTags)
                        )
                        store.haptic(.medium)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

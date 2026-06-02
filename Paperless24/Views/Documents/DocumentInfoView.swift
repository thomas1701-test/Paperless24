import SwiftUI

/// Read-only-Übersicht der Metadaten und Custom Fields eines Dokuments.
struct DocumentInfoView: View {
    @EnvironmentObject var store: AppStore
    let doc: Document

    var body: some View {
        List {
            Section("Metadaten") {
                infoRow("Sender", store.allCorrespondents.first { $0.id == doc.correspondent }?.safeName ?? "—")
                infoRow("Typ", store.allDocTypes.first { $0.id == doc.documentType }?.safeName ?? "—")
                infoRow("ASN", doc.archiveSerialNumber.map { "\($0)" } ?? "—")
                infoRow("Datum", String(doc.created.prefix(10)))
                if !doc.tags.isEmpty {
                    LabeledContent("Tags") {
                        Text(doc.tags.compactMap { id in store.allTags.first { $0.id == id }?.safeName }.joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if !doc.customFields.isEmpty {
                Section("Felder") {
                    ForEach(doc.customFields) { entry in
                        infoRow(store.customField(id: entry.field)?.safeName ?? "Feld",
                                store.customFieldDisplay(entry.value, fieldId: entry.field))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

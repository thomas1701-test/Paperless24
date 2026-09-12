import SwiftUI

/// Read-only-Übersicht der Metadaten und Custom Fields eines Dokuments.
struct DocumentInfoView: View {
    @EnvironmentObject var store: AppStore
    let doc: Document

    @State private var summary: String?
    @State private var isSummarizing = false
    @State private var similar: [Document] = []
    @State private var isLoadingSimilar = false

    var body: some View {
        List {
            if AIService.shared.isAvailable, let content = doc.content, !content.isEmpty {
                Section("Zusammenfassung") {
                    if let summary {
                        Text(summary).font(.body)
                    } else {
                        Button {
                            Task {
                                isSummarizing = true
                                if let result = await AIService.shared.summarize(content) {
                                    summary = result
                                    store.registerReviewEvent()
                                } else {
                                    summary = "Keine Zusammenfassung möglich.\n\nGrund: \(AIService.shared.lastErrorDescription ?? "unbekannt")"
                                }
                                isSummarizing = false
                            }
                        } label: {
                            HStack {
                                if isSummarizing { ProgressView().padding(.trailing, 4) }
                                Label("Mit Apple Intelligence zusammenfassen", systemImage: "sparkles")
                                    .foregroundColor(.purple)
                            }
                        }
                        .disabled(isSummarizing)
                    }
                }
            }

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

            if !similar.isEmpty {
                Section {
                    ForEach(similar) { other in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.title).lineLimit(1)
                            Text(String(other.created.prefix(10)))
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Ähnliche Dokumente")
                } footer: {
                    // Der Server rechnet auf seinem Volltextindex und kennt damit das ganze
                    // Archiv — anders als die App, die nur die geladene Seite sieht.
                    Text("Vom Server ermittelt.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .task {
            guard similar.isEmpty else { return }
            isLoadingSimilar = true
            similar = await store.similarDocuments(to: doc.id)
            isLoadingSimilar = false
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }
}

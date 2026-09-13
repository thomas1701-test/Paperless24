import SwiftUI
import PDFKit
import Vision

struct MetadataFormSection: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.locale) private var locale

    @Binding var correspondent: Int?
    @Binding var documentType: Int?
    @Binding var tags: Set<Int>
    @Binding var date: Date

    @State private var newName = ""
    @State private var isAnalyzing = false
    @State private var analysisResult = ""
    @State private var activeSheet: ActiveSheet?
    /// Von der KI genannte Einträge, die es noch nicht gibt — warten auf Bestätigung.
    @State private var proposals: [MetadataProposal] = []
    @State private var selectedProposals: Set<String> = []

    var pdfData: Data?

    /// Das einzige Sheet dieser Section – entweder ein durchsuchbarer Auswahl-Picker
    /// oder das Neu-Anlegen-Formular. Bewusst EIN gemeinsamer `.sheet`-Modifier:
    /// mehrere `.sheet` an Geschwister-Sections im selben Form kollidieren in SwiftUI
    /// und reißen die ganze Präsentation (inkl. Eltern-Sheet) ab.
    private enum ActiveSheet: Identifiable {
        case sender, docType, tags
        case newEntry(MetadataType)
        case proposals
        var id: String {
            switch self {
            case .sender: return "sender"
            case .docType: return "docType"
            case .tags: return "tags"
            case .newEntry(let t): return "new-\(t)"
            case .proposals: return "proposals"
            }
        }
    }

    private var correspondentName: String {
        store.allCorrespondents.first { $0.id == correspondent }?.safeName ?? String(localized: "Kein Sender", locale: locale)
    }
    private var documentTypeName: String {
        store.allDocTypes.first { $0.id == documentType }?.safeName ?? String(localized: "Kein Typ", locale: locale)
    }
    private var correspondentItems: [FilterPickerItem] {
        store.allCorrespondents.map { FilterPickerItem(id: $0.id, name: $0.safeName) }
    }
    private var docTypeItems: [FilterPickerItem] {
        store.allDocTypes.map { FilterPickerItem(id: $0.id, name: $0.safeName) }
    }
    private var tagItems: [FilterPickerItem] {
        store.allTags.map { FilterPickerItem(id: $0.id, name: $0.safeName) }
    }
    private var tagColors: [Int: String] {
        Dictionary(uniqueKeysWithValues: store.allTags.map { ($0.id, $0.safeColor) })
    }

    var body: some View {
        Section("Details") {
            HStack {
                Button { activeSheet = .sender } label: {
                    HStack {
                        Text("Sender")
                        Spacer()
                        Text(correspondentName)
                            .foregroundColor(correspondent == nil ? .secondary : .blue)
                    }
                }
                .buttonStyle(.plain)
                Button {
                    newName = ""; activeSheet = .newEntry(.correspondent)
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.green)
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button { activeSheet = .docType } label: {
                    HStack {
                        Text("Typ")
                        Spacer()
                        Text(documentTypeName)
                            .foregroundColor(documentType == nil ? .secondary : .blue)
                    }
                }
                .buttonStyle(.plain)
                Button {
                    newName = ""; activeSheet = .newEntry(.docType)
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.green)
                }
                .buttonStyle(.borderless)
            }
        }

        Section("Tags") {
            HStack {
                Button { activeSheet = .tags } label: {
                    HStack {
                        Text("Tags:")
                        Spacer()
                        if tags.isEmpty { Text("Keine").foregroundColor(.secondary) }
                        else { Text("\(tags.count) \(String(localized: "gewählt", locale: locale))").foregroundColor(.blue) }
                    }
                }
                .buttonStyle(.plain)
                Button {
                    newName = ""; activeSheet = .newEntry(.tag)
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.green)
                }
                .buttonStyle(.borderless)
            }
        }

        Section {
            HStack {
                if isAnalyzing { ProgressView().padding(.trailing, 5); Text("KI denkt...").font(.caption) }
                else if !analysisResult.isEmpty { Text(analysisResult).foregroundColor(.purple).font(.caption) }
                Spacer()
                Button { Task { await runAnalysis() } } label: {
                    Image(systemName: "wand.and.stars").foregroundColor(.purple)
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .sender:
                FilterPickerSheet(title: String(localized: "Sender", locale: locale), items: correspondentItems, noneLabel: String(localized: "Kein Sender", locale: locale), selectedId: $correspondent)
                    .presentationDetents([.medium, .large])
            case .docType:
                FilterPickerSheet(title: String(localized: "Typ", locale: locale), items: docTypeItems, noneLabel: String(localized: "Kein Typ", locale: locale), selectedId: $documentType)
                    .presentationDetents([.medium, .large])
            case .tags:
                MultiSelectPickerSheet(title: String(localized: "Tags", locale: locale), items: tagItems, colors: tagColors, selected: $tags)
                    .presentationDetents([.medium, .large])
            case .newEntry(let type):
                SimpleInputSheet(
                    title: type == .tag ? "Neuer Tag" : (type == .correspondent ? "Neuer Sender" : "Neuer Typ"),
                    text: $newName,
                    onSave: {
                        Task {
                            switch type {
                            case .tag:
                                if let id = await store.createTag(name: newName) { tags.insert(id) }
                            case .correspondent:
                                correspondent = await store.createCorrespondent(name: newName)
                            case .docType:
                                documentType = await store.createDocumentType(name: newName)
                            }
                        }
                        activeSheet = nil
                    },
                    onCancel: { activeSheet = nil }
                )
            case .proposals:
                proposalSheet
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// Rückfrage, bevor KI-Vorschläge neue Stammdaten auf dem Server anlegen. Vorher legte
    /// jeder Tipp auf den Zauberstab ungefragt Tags, Sender und Typen an — auch Tippfehler
    /// und Fantasienamen des Modells.
    private var proposalSheet: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(proposals) { proposal in
                        Toggle(isOn: Binding(
                            get: { selectedProposals.contains(proposal.id) },
                            set: { on in
                                if on { selectedProposals.insert(proposal.id) } else { selectedProposals.remove(proposal.id) }
                            }
                        )) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: proposal.name)
                                    Text(kindLabel(proposal.kind)).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: kindIcon(proposal.kind))
                            }
                        }
                    }
                } footer: {
                    Text("Die KI schlägt Einträge vor, die es auf dem Server noch nicht gibt. Nur die ausgewählten werden angelegt und dem Dokument zugeordnet.")
                }
            }
            .navigationTitle("Neu anlegen?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Nicht anlegen") {
                        proposals = []
                        activeSheet = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        let chosen = proposals.filter { selectedProposals.contains($0.id) }
                        proposals = []
                        activeSheet = nil
                        Task { await create(chosen) }
                    }
                    .disabled(selectedProposals.isEmpty)
                }
            }
        }
    }

    private func kindLabel(_ kind: MetadataType) -> LocalizedStringKey {
        switch kind {
        case .tag: return "Tag"
        case .correspondent: return "Sender"
        case .docType: return "Typ"
        }
    }

    private func kindIcon(_ kind: MetadataType) -> String {
        switch kind {
        case .tag: return "tag"
        case .correspondent: return "person"
        case .docType: return "doc"
        }
    }

    private func create(_ chosen: [MetadataProposal]) async {
        var failed: [String] = []
        for proposal in chosen {
            switch proposal.kind {
            case .correspondent:
                if let id = await store.createCorrespondent(name: proposal.name) { correspondent = id } else { failed.append(proposal.name) }
            case .docType:
                if let id = await store.createDocumentType(name: proposal.name) { documentType = id } else { failed.append(proposal.name) }
            case .tag:
                if let id = await store.createTag(name: proposal.name) { tags.insert(id) } else { failed.append(proposal.name) }
            }
        }
        if !failed.isEmpty {
            analysisResult = String(format: String(localized: "Nicht angelegt: %@", locale: locale),
                                    failed.joined(separator: ", "))
        }
    }

    func runAnalysis() async {
        guard let data = pdfData else { return }

        isAnalyzing = true
        analysisResult = ""

        // Rendern und Texterkennung laufen in `OCRService` abseits des Main Threads —
        // vorher stand die Oberfläche währenddessen still.
        let fullText = await OCRService.recognizeFirstPage(ofPDF: data)

        // Bevorzugt Apple Intelligence; fällt sonst auf die Stichwort-Logik zurück.
        if AIService.shared.isAvailable {
            analysisResult = "KI analysiert..."
            if let suggestion = await AIService.shared.extractMetadata(
                text: fullText,
                tags: store.allTags.map { $0.safeName },
                correspondents: store.allCorrespondents.map { $0.safeName },
                types: store.allDocTypes.map { $0.safeName }
            ) {
                applySuggestion(suggestion)
                analysisResult = "KI-Vorschläge übernommen"
                isAnalyzing = false
                return
            }
        }

        let lower = fullText.lowercased()
        for c in store.allCorrespondents {
            if lower.contains(c.safeName.lowercased()) { correspondent = c.id; break }
        }
        for t in store.allTags {
            if lower.contains(t.safeName.lowercased()) { tags.insert(t.id); break }
        }
        if let d = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
            .matches(in: fullText, range: NSRange(location: 0, length: fullText.utf16.count))
            .first?.date {
            date = d
            analysisResult = "Datum gefunden"
        } else {
            analysisResult = "Fertig"
        }
        isAnalyzing = false
    }

    /// Übernimmt KI-Vorschläge, soweit es die Einträge schon gibt. Fehlende werden erst nach
    /// Rückfrage angelegt (`proposalSheet`).
    private func applySuggestion(_ s: AISuggestion) {
        let resolved = SuggestionResolver.resolve(
            correspondent: s.correspondent, type: s.type, tags: s.tags,
            correspondents: store.allCorrespondents.map { ($0.id, $0.safeName) },
            types: store.allDocTypes.map { ($0.id, $0.safeName) },
            allTags: store.allTags.map { ($0.id, $0.safeName) }
        )
        if let id = resolved.correspondent { correspondent = id }
        if let id = resolved.documentType { documentType = id }
        tags.formUnion(resolved.tags)
        if let d = s.date { date = d }

        // Im Demo-Modus gibt es keinen Server, auf dem etwas angelegt werden könnte.
        guard !resolved.missing.isEmpty, !store.isDemoMode else { return }
        proposals = resolved.missing
        selectedProposals = Set(resolved.missing.map(\.id))
        activeSheet = .proposals
    }
}

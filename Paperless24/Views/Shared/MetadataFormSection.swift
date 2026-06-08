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

    @State private var showSheet = false
    @State private var sheetType: MetadataType = .tag
    @State private var newName = ""
    @State private var isAnalyzing = false
    @State private var analysisResult = ""
    @State private var activePicker: ActivePicker?

    var pdfData: Data?

    /// Welches durchsuchbare Auswahl-Sheet gerade offen ist.
    private enum ActivePicker: Int, Identifiable {
        case sender, docType, tags
        var id: Int { rawValue }
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
                Button { activePicker = .sender } label: {
                    HStack {
                        Text("Sender")
                        Spacer()
                        Text(correspondentName)
                            .foregroundColor(correspondent == nil ? .secondary : .blue)
                    }
                }
                .buttonStyle(.plain)
                Button {
                    newName = ""; sheetType = .correspondent; showSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.green)
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button { activePicker = .docType } label: {
                    HStack {
                        Text("Typ")
                        Spacer()
                        Text(documentTypeName)
                            .foregroundColor(documentType == nil ? .secondary : .blue)
                    }
                }
                .buttonStyle(.plain)
                Button {
                    newName = ""; sheetType = .docType; showSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.green)
                }
                .buttonStyle(.borderless)
            }
        }
        .sheet(item: $activePicker) { picker in
            switch picker {
            case .sender:
                FilterPickerSheet(title: String(localized: "Sender", locale: locale), items: correspondentItems, noneLabel: String(localized: "Kein Sender", locale: locale), selectedId: $correspondent)
                    .presentationDetents([.medium, .large])
            case .docType:
                FilterPickerSheet(title: String(localized: "Typ", locale: locale), items: docTypeItems, noneLabel: String(localized: "Kein Typ", locale: locale), selectedId: $documentType)
                    .presentationDetents([.medium, .large])
            case .tags:
                MultiSelectPickerSheet(title: String(localized: "Tags", locale: locale), items: tagItems, colors: tagColors, selected: $tags)
                    .presentationDetents([.medium, .large])
            }
        }

        Section("Tags") {
            HStack {
                Button { activePicker = .tags } label: {
                    HStack {
                        Text("Tags:")
                        Spacer()
                        if tags.isEmpty { Text("Keine").foregroundColor(.secondary) }
                        else { Text("\(tags.count) \(String(localized: "gewählt", locale: locale))").foregroundColor(.blue) }
                    }
                }
                .buttonStyle(.plain)
                Button {
                    newName = ""; sheetType = .tag; showSheet = true
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
        .sheet(isPresented: $showSheet) {
            SimpleInputSheet(
                title: sheetType == .tag ? "Neuer Tag" : (sheetType == .correspondent ? "Neuer Sender" : "Neuer Typ"),
                text: $newName,
                onSave: {
                    Task {
                        switch sheetType {
                        case .tag:
                            if let id = await store.createTag(name: newName) { tags.insert(id) }
                        case .correspondent:
                            correspondent = await store.createCorrespondent(name: newName)
                        case .docType:
                            documentType = await store.createDocumentType(name: newName)
                        }
                    }
                    showSheet = false
                },
                onCancel: { showSheet = false }
            )
        }
    }

    func runAnalysis() async {
        guard let data = pdfData,
              let pdf = PDFDocument(data: data),
              let page = pdf.page(at: 0),
              let cgImage = page.thumbnail(of: CGSize(width: 1000, height: 1000), for: .mediaBox).cgImage else { return }

        isAnalyzing = true
        analysisResult = ""

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        try? VNImageRequestHandler(cgImage: cgImage).perform([request])

        guard let observations = request.results as? [VNRecognizedTextObservation] else {
            isAnalyzing = false; return
        }
        let fullText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")

        // Bevorzugt Apple Intelligence; fällt sonst auf die Stichwort-Logik zurück.
        if AIService.shared.isAvailable {
            analysisResult = "KI analysiert..."
            if let suggestion = await AIService.shared.extractMetadata(
                text: fullText,
                tags: store.allTags.map { $0.safeName },
                correspondents: store.allCorrespondents.map { $0.safeName },
                types: store.allDocTypes.map { $0.safeName }
            ) {
                await applySuggestion(suggestion)
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

    /// Wendet KI-Vorschläge an; legt fehlende Tags/Sender/Typen bei Bedarf an.
    private func applySuggestion(_ s: AISuggestion) async {
        if let name = s.correspondent {
            if let existing = store.allCorrespondents.first(where: { $0.safeName.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                correspondent = existing.id
            } else if let id = await store.createCorrespondent(name: name) {
                correspondent = id
            }
        }
        if let name = s.type {
            if let existing = store.allDocTypes.first(where: { $0.safeName.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                documentType = existing.id
            } else if let id = await store.createDocumentType(name: name) {
                documentType = id
            }
        }
        for name in s.tags {
            if let existing = store.allTags.first(where: { $0.safeName.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                tags.insert(existing.id)
            } else if let id = await store.createTag(name: name) {
                tags.insert(id)
            }
        }
        if let d = s.date { date = d }
    }
}

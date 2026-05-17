import SwiftUI
import PDFKit
import Vision

struct MetadataFormSection: View {
    @EnvironmentObject var store: AppStore

    @Binding var correspondent: Int?
    @Binding var documentType: Int?
    @Binding var tags: Set<Int>
    @Binding var date: Date

    @State private var showSheet = false
    @State private var sheetType: MetadataType = .tag
    @State private var newName = ""
    @State private var isAnalyzing = false
    @State private var analysisResult = ""

    var pdfData: Data?

    var body: some View {
        Section("Details") {
            HStack {
                Picker("Sender", selection: $correspondent) {
                    Text("-").tag(Int?.none)
                    ForEach(store.allCorrespondents) { c in Text(c.safeName).tag(c.id as Int?) }
                }
                Button {
                    newName = ""; sheetType = .correspondent; showSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.green)
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Picker("Typ", selection: $documentType) {
                    Text("-").tag(Int?.none)
                    ForEach(store.allDocTypes) { t in Text(t.safeName).tag(t.id as Int?) }
                }
                Button {
                    newName = ""; sheetType = .docType; showSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundColor(.green)
                }
                .buttonStyle(.borderless)
            }
        }

        Section("Tags") {
            HStack {
                Text("Tags:")
                Spacer()
                Menu {
                    ForEach(store.allTags) { t in
                        Button {
                            if tags.contains(t.id) { tags.remove(t.id) } else { tags.insert(t.id) }
                        } label: {
                            Label(t.safeName, systemImage: tags.contains(t.id) ? "checkmark" : "")
                        }
                    }
                } label: {
                    if tags.isEmpty { Text("Keine").foregroundColor(.secondary) }
                    else { Text("\(tags.count) gewählt").foregroundColor(.blue) }
                }
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
        let fullText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()

        for c in store.allCorrespondents {
            if fullText.contains(c.safeName.lowercased()) { correspondent = c.id; break }
        }
        for t in store.allTags {
            if fullText.contains(t.safeName.lowercased()) { tags.insert(t.id); break }
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
}

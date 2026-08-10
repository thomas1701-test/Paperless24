import SwiftUI

/// Scannt einen Stapel, trennt ihn (KI) in einzelne Dokumente und lädt sie hoch.
struct BatchScanView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = true
    @State private var pages: [UIImage] = []
    @State private var groups: [Int] = []
    @State private var isProcessing = false

    private var maxGroup: Int { max(groups.max() ?? 1, 1) }
    private var documentCount: Int { Set(groups).count }

    var body: some View {
        NavigationStack {
            Group {
                if isProcessing {
                    VStack(spacing: 12) { ProgressView(); Text("Analysiere Seiten …").foregroundColor(.secondary) }
                } else if pages.isEmpty {
                    VStack(spacing: 12) { ProgressView(); Text("Scanner wird geöffnet …").foregroundColor(.secondary) }
                } else {
                    List {
                        SwiftUI.Section {
                            Text("\(pages.count) Seiten → \(documentCount) Dokument(e)")
                                .font(.caption).foregroundColor(.secondary)
                        } footer: {
                            Text("Seiten mit gleicher Nummer werden zu einem Dokument zusammengefasst.")
                        }
                        ForEach(pages.indices, id: \.self) { i in
                            HStack(spacing: 12) {
                                Image(uiImage: pages[i]).resizable().scaledToFit()
                                    .frame(width: 46, height: 64).cornerRadius(4)
                                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                                Text("Seite \(i + 1)")
                                Spacer()
                                Stepper("Dok. \(groups[i])", value: groupBinding(i), in: 1...(maxGroup + 1))
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stapel scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                if !pages.isEmpty && !isProcessing {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hochladen") { upload() }
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                PageScannerView(isPresented: $showScanner) { scanned in
                    pages = scanned
                    if scanned.isEmpty { dismiss() } else { process(scanned) }
                }
            }
        }
    }

    private func groupBinding(_ i: Int) -> Binding<Int> {
        Binding(get: { groups.indices.contains(i) ? groups[i] : 1 },
                set: { if groups.indices.contains(i) { groups[i] = $0 } })
    }

    private func process(_ scanned: [UIImage]) {
        isProcessing = true
        Task {
            if AIService.shared.isAvailable {
                var texts: [String] = []
                for img in scanned { texts.append(await OCRService.recognizeText(in: img)) }
                groups = await AIService.shared.groupPages(texts)
            } else {
                groups = Array(repeating: 1, count: scanned.count)
            }
            if groups.count != scanned.count { groups = Array(repeating: 1, count: scanned.count) }
            isProcessing = false
        }
    }

    private func upload() {
        let grouped = Dictionary(grouping: pages.indices, by: { groups[$0] })
        let stamp = Int(Date().timeIntervalSince1970)
        var n = 0
        for key in grouped.keys.sorted() {
            n += 1
            let imgs = grouped[key]!.sorted().map { pages[$0] }
            let pdf = OCRService.pdf(from: imgs)
            store.addToQueue(data: pdf, filename: "Stapel_\(stamp)_\(n).pdf",
                             title: "Scan \(n)", created: Date(), corr: nil, type: nil, tags: [])
        }
        dismiss()
    }
}

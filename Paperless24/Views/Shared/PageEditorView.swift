import SwiftUI
import PDFKit

/// Seiten drehen, löschen und umsortieren — vor dem Hochladen.
///
/// Der häufigste Grund, ein frisch gescanntes Dokument noch einmal anzufassen: eine Seite steht
/// auf dem Kopf, das Deckblatt liegt hinten, oder eine leere Rückseite ist mitgescannt. Bisher
/// hieß das: verwerfen und neu scannen.
///
/// Gearbeitet wird auf einer Kopie; erst „Sichern" gibt die geänderten Daten zurück.
struct PageEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette

    let data: Data
    let onSave: (Data) -> Void

    @State private var document: PDFDocument? = nil
    @State private var thumbnails: [UIImage] = []
    @State private var selection: Int? = nil
    @State private var isWorking = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        NavigationStack {
            Group {
                if let document, document.pageCount > 0 {
                    grid(pageCount: document.pageCount)
                } else if isWorking {
                    ProgressView()
                } else {
                    Text("Die Datei enthält keine Seiten.").foregroundColor(.secondary)
                }
            }
            .navigationTitle("Seiten")
            .navigationBarTitleDisplayMode(.inline)
            .themedSurface(palette)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(document == nil)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        rotateSelected(by: -90)
                    } label: { Image(systemName: "rotate.left") }
                        .disabled(selection == nil)
                    Button {
                        rotateSelected(by: 90)
                    } label: { Image(systemName: "rotate.right") }
                        .disabled(selection == nil)
                    Spacer()
                    Button {
                        move(by: -1)
                    } label: { Image(systemName: "arrow.up") }
                        .disabled(selection == nil || selection == 0)
                    Button {
                        move(by: 1)
                    } label: { Image(systemName: "arrow.down") }
                        .disabled(selection == nil || selection == (document?.pageCount ?? 1) - 1)
                    Spacer()
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: { Image(systemName: "trash") }
                        // Die letzte Seite darf nicht weg — ein PDF ohne Seiten ist keine Datei.
                        .disabled(selection == nil || (document?.pageCount ?? 0) <= 1)
                }
            }
            .task { load() }
        }
    }

    private func grid(pageCount: Int) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<pageCount, id: \.self) { index in
                    VStack(spacing: 4) {
                        if index < thumbnails.count {
                            Image(uiImage: thumbnails[index])
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 150)
                                .background(Color(.secondarySystemBackground))
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.secondarySystemBackground))
                                .frame(height: 150)
                        }
                        Text("Seite \(index + 1)").font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selection == index ? palette.accent : .clear, lineWidth: 2)
                    )
                    .onTapGesture { selection = (selection == index ? nil : index) }
                }
            }
            .padding()
        }
    }

    // MARK: - Bearbeiten

    private func load() {
        isWorking = true
        // Eigene Kopie: Ein `PDFDocument` auf den übergebenen Daten würde das Original ändern.
        document = PDFDocument(data: data)
        renderThumbnails()
        isWorking = false
    }

    private func renderThumbnails() {
        guard let document else { thumbnails = []; return }
        thumbnails = (0..<document.pageCount).compactMap { index in
            document.page(at: index)?.thumbnail(of: CGSize(width: 220, height: 300), for: .mediaBox)
        }
    }

    private func rotateSelected(by degrees: Int) {
        guard let index = selection, let page = document?.page(at: index) else { return }
        // PDFKit rechnet in ganzen Vierteldrehungen; negative Werte sind erlaubt, Werte über
        // 360 nicht überall — deshalb normalisieren.
        page.rotation = ((page.rotation + degrees) % 360 + 360) % 360
        renderThumbnails()
    }

    private func deleteSelected() {
        guard let index = selection, let document, document.pageCount > 1 else { return }
        document.removePage(at: index)
        selection = nil
        renderThumbnails()
    }

    private func move(by offset: Int) {
        guard let index = selection, let document else { return }
        let target = index + offset
        guard target >= 0, target < document.pageCount, let page = document.page(at: index) else { return }
        document.removePage(at: index)
        document.insert(page, at: target)
        selection = target
        renderThumbnails()
    }

    private func save() {
        guard let document, let output = document.dataRepresentation() else { return }
        onSave(output)
        dismiss()
    }
}

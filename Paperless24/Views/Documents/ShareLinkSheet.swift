import SwiftUI

/// Verwaltet öffentliche Freigabe-Links eines Dokuments.
struct ShareLinkSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let documentId: Int

    @State private var links: [DocShareLink] = []
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var useExpiration = false
    @State private var expiration = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var fileVersion = "archive"
    @State private var copiedSlug: String? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Neuen Link erstellen") {
                    Picker("Version", selection: $fileVersion) {
                        Text("Archiviert").tag("archive")
                        Text("Original").tag("original")
                    }
                    Toggle("Ablaufdatum", isOn: $useExpiration)
                    if useExpiration {
                        DatePicker("Läuft ab", selection: $expiration, in: Date()..., displayedComponents: .date)
                    }
                    Button {
                        Task { await createLink() }
                    } label: {
                        HStack {
                            if isCreating { ProgressView().padding(.trailing, 4) }
                            Text("Link erstellen")
                        }
                    }
                    .disabled(isCreating)
                }

                Section("Bestehende Links") {
                    if isLoading {
                        HStack { ProgressView(); Text("Lädt...").foregroundColor(.secondary) }
                    } else if links.isEmpty {
                        Text("Keine Links vorhanden").foregroundColor(.secondary)
                    } else {
                        ForEach(links) { link in
                            linkRow(link)
                        }
                    }
                }
            }
            .navigationTitle("Freigabe-Links")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
            .onAppear { Task { await reload() } }
            .alert("Freigabe-Links", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func linkRow(_ link: DocShareLink) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let url = link.publicURL(serverBase: store.makeServerBase()) {
                Text(url.absoluteString).font(.caption).foregroundColor(.blue).lineLimit(1)
            }
            HStack {
                if let exp = link.expiration {
                    Label("bis \(String(exp.prefix(10)))", systemImage: "clock")
                        .font(.caption2).foregroundColor(.secondary)
                } else {
                    Label("unbegrenzt", systemImage: "infinity")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    if let url = link.publicURL(serverBase: store.makeServerBase()) {
                        UIPasteboard.general.string = url.absoluteString
                        copiedSlug = link.slug
                        store.haptic(.light)
                    }
                } label: {
                    Label(copiedSlug == link.slug ? "Kopiert" : "Kopieren",
                          systemImage: copiedSlug == link.slug ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .swipeActions {
            Button(role: .destructive) {
                Task { await revoke(link) }
            } label: { Label("Widerrufen", systemImage: "trash") }
        }
    }

    private func reload() async {
        isLoading = true
        links = await store.fetchShareLinks(documentId: documentId)
        isLoading = false
    }

    private func createLink() async {
        isCreating = true
        if let new = await store.createShareLink(documentId: documentId,
                                                 expiration: useExpiration ? expiration : nil,
                                                 fileVersion: fileVersion) {
            links.insert(new, at: 0)
        } else {
            errorMessage = String(localized: "Der Link konnte nicht erstellt werden.")
        }
        isCreating = false
    }

    private func revoke(_ link: DocShareLink) async {
        if let failure = await store.deleteShareLink(id: link.id) {
            // Der Link bleibt stehen: Er ist weiterhin öffentlich erreichbar.
            errorMessage = String(localized: "Der Link wurde nicht widerrufen und ist weiterhin gültig.")
                + "\n\n" + failure
            return
        }
        links.removeAll { $0.id == link.id }
    }
}

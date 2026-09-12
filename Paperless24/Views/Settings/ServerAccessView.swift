import SwiftUI
import UniformTypeIdentifiers

/// Eigene HTTP-Header und Client-Zertifikat für den aktiven Server.
struct ServerAccessView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    @State private var headers: [HeaderRow] = []
    @State private var showCertPicker = false
    @State private var certPassword = ""
    @State private var showPasswordPrompt = false
    @State private var pendingCertData: Data? = nil
    @State private var hasCert = false
    @State private var message: String? = nil

    private var server: String { store.makeServerBase() }

    struct HeaderRow: Identifiable, Equatable {
        let id = UUID()
        var name: String
        var value: String
    }

    var body: some View {
        List {
            Section {
                ForEach($headers) { $row in
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name, z. B. CF-Access-Client-Id", text: $row.name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.callout)
                        SecureField("Wert", text: $row.value)
                            .font(.caption)
                    }
                }
                .onDelete { headers.remove(atOffsets: $0) }

                Button {
                    headers.append(HeaderRow(name: "", value: ""))
                } label: {
                    Label("Kopfzeile hinzufügen", systemImage: "plus")
                }
            } header: {
                Text("Eigene Kopfzeilen")
            } footer: {
                Text("Wird jeder Anfrage an diesen Server mitgegeben — für Cloudflare Access "
                     + "(CF-Access-Client-Id / -Secret), Authelia oder einen Proxy mit "
                     + "Basic-Auth. Werte werden verdeckt angezeigt.")
            }

            Section {
                if hasCert {
                    Label("Zertifikat hinterlegt", systemImage: "checkmark.seal")
                        .foregroundColor(.green)
                    Button(role: .destructive) {
                        ServerCredentials.removeCertificate(for: server)
                        ClientCertSessionProvider.shared.invalidate(server: server)
                        hasCert = false
                    } label: { Label("Zertifikat entfernen", systemImage: "trash") }
                } else {
                    Button {
                        showCertPicker = true
                    } label: { Label("PKCS#12-Datei wählen (.p12)", systemImage: "doc.badge.plus") }
                }
            } header: {
                Text("Client-Zertifikat (mTLS)")
            } footer: {
                Text("Nur nötig, wenn der Server ein Client-Zertifikat verlangt. Die Datei "
                     + "enthält den privaten Schlüssel und wird im Schlüsselbund dieses Geräts "
                     + "abgelegt — sie verlässt das Gerät nicht und wandert nicht in Backups.")
            }

            Section {
                Button("Speichern und Verbindung prüfen") { save() }
                    .disabled(server.isEmpty)
            }
        }
        .themedSurface(palette)
        .navigationTitle("Serverzugang")
        .onAppear(perform: load)
        .fileImporter(isPresented: $showCertPicker,
                      allowedContentTypes: [UTType(filenameExtension: "p12") ?? .data,
                                            UTType(filenameExtension: "pfx") ?? .data]) { result in
            switch result {
            case .success(let url):
                // Die Datei liegt außerhalb der App-Sandbox — Zugriff muss angefordert werden.
                let needsStop = url.startAccessingSecurityScopedResource()
                defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
                pendingCertData = try? Data(contentsOf: url)
                showPasswordPrompt = pendingCertData != nil
                if pendingCertData == nil { message = "Die Datei ließ sich nicht lesen." }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert("Kennwort des Zertifikats", isPresented: $showPasswordPrompt) {
            SecureField("Kennwort", text: $certPassword)
            Button("Abbrechen", role: .cancel) { pendingCertData = nil; certPassword = "" }
            Button("Importieren") { importCertificate() }
        } message: {
            Text("PKCS#12-Dateien sind immer mit einem Kennwort geschützt.")
        }
        .alert("Serverzugang", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func load() {
        headers = ServerCredentials.headers(for: server)
            .sorted { $0.key < $1.key }
            .map { HeaderRow(name: $0.key, value: $0.value) }
        hasCert = ServerCredentials.hasCertificate(for: server)
    }

    private func importCertificate() {
        defer { pendingCertData = nil; certPassword = "" }
        guard let data = pendingCertData else { return }
        if ServerCredentials.storeCertificate(data, password: certPassword, for: server) {
            hasCert = true
            ClientCertSessionProvider.shared.invalidate(server: server)
            message = "Zertifikat importiert."
        } else {
            message = "Import fehlgeschlagen — falsches Kennwort oder keine gültige PKCS#12-Datei."
        }
    }

    private func save() {
        let map = Dictionary(
            headers
                .map { (name: $0.name.trimmingCharacters(in: .whitespaces), value: $0.value) }
                .filter { !$0.name.isEmpty && !$0.value.isEmpty }
                .map { ($0.name, $0.value) },
            uniquingKeysWith: { _, last in last }
        )
        ServerCredentials.setHeaders(map, for: server)
        ClientCertSessionProvider.shared.invalidate(server: server)
        Task { message = await store.probeConnection() }
    }
}

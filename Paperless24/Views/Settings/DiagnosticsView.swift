import SwiftUI
import UIKit

/// Diagnose — was die App über diesen Server weiß.
///
/// paperless-ngx läuft bei jedem anders: eigene Version, eigener Reverse Proxy, eigene
/// API-Version. Bei einer bezahlten App ist die Frage „warum geht das bei mir nicht" der
/// häufigste Supportfall, und die Antwort steckt fast immer in diesen Werten. Der Knopf
/// „Kopieren" legt sie als Text in die Zwischenablage, damit sie in eine Mail passen.
struct DiagnosticsView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.palette) private var palette

    @State private var probe: String? = nil
    @State private var isProbing = false
    @State private var copied = false

    var body: some View {
        List {
            Section("Server") {
                row("Adresse", store.serverUrl.isEmpty ? "—" : store.serverUrl)
                row("Benutzer", store.username.isEmpty ? "—" : store.username)
                row("Angemeldet", store.hasValidToken() ? "ja" : "nein")
                row("API-Version", apiVersionText)
                row("Server-Filter", filterSupportText)
            }

            Section("Verbindung") {
                row("Zustand", store.isOffline ? "offline" : "online")
                if let error = store.lastSyncError {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Letzter Fehler").font(.caption).foregroundColor(.secondary)
                        Text(error).font(.caption).foregroundColor(.red)
                    }
                }
                Button {
                    Task { await runProbe() }
                } label: {
                    HStack {
                        Text("Verbindung prüfen")
                        if isProbing { Spacer(); ProgressView().controlSize(.small) }
                    }
                }
                .disabled(isProbing)
                if let probe {
                    Text(probe).font(.caption).foregroundColor(.secondary)
                }
            }

            Section("Daten") {
                row("Dokumente geladen", "\(store.documents.count)")
                row("Tags", "\(store.allTags.count)")
                row("Sender", "\(store.allCorrespondents.count)")
                row("Typen", "\(store.allDocTypes.count)")
                row("Eigene Felder", "\(store.allCustomFields.count)")
                row("Posteingang-Tags", store.inboxTagIDs.isEmpty ? "keiner gesetzt" : "\(store.inboxTagIDs.count)")
                row("Zwischengespeichert", "\(store.cachedCount) Dateien / \(store.storageSize)")
            }

            Section("Warteschlange") {
                row("Uploads offen", "\(store.pendingUploads.count)")
                row("Änderungen offen", "\(store.pendingEdits.count)")
                row("Verarbeitung verfolgt", "\(store.uploadTaskStatuses.count)")
            }

            Section("Gerät") {
                row("App-Version", appVersion)
                row("iOS", UIDevice.current.systemVersion)
                row("KI verfügbar", AIService.shared.modelAvailable ? "ja" : "nein")
                if let aiError = AIService.shared.lastErrorDescription {
                    Text(aiError).font(.caption).foregroundColor(.secondary)
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = report
                    copied = true
                    store.haptic(.light)
                } label: {
                    Label(copied ? "Kopiert" : "Bericht kopieren",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                if !DocumentFilterSupport.isSupported(store.serverUrl) && !store.serverUrl.isEmpty {
                    Button("Server-Filter erneut versuchen") {
                        DocumentFilterSupport.reset(store.serverUrl)
                        store.applyFilters(debounce: false)
                    }
                }
            } footer: {
                Text("Der Bericht enthält Serveradresse und Benutzername, aber kein Passwort "
                     + "und keine Dokumentinhalte.")
            }
        }
        .themedSurface(palette)
        .navigationTitle("Diagnose")
    }

    // MARK: - Bausteine

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundColor(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private var apiVersionText: String {
        guard !store.serverUrl.isEmpty else { return "—" }
        if let version = APIVersionNegotiator.version(for: store.serverUrl) {
            return "\(version) (angefragt)"
        }
        return "Server-Standard"
    }

    private var filterSupportText: String {
        guard !store.serverUrl.isEmpty else { return "—" }
        return DocumentFilterSupport.isSupported(store.serverUrl) ? "aktiv" : "abgeschaltet (400)"
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// Ein Textblock, der in eine Supportmail passt.
    private var report: String {
        var lines = ["Paperless 24 — Diagnose"]
        lines.append("App: \(appVersion), iOS \(UIDevice.current.systemVersion)")
        lines.append("Server: \(store.serverUrl)")
        lines.append("Benutzer: \(store.username), angemeldet: \(store.hasValidToken() ? "ja" : "nein")")
        lines.append("API-Version: \(apiVersionText)")
        lines.append("Server-Filter: \(filterSupportText)")
        lines.append("Zustand: \(store.isOffline ? "offline" : "online")")
        if let error = store.lastSyncError { lines.append("Letzter Fehler: \(error)") }
        if let probe { lines.append("Prüfung: \(probe)") }
        lines.append("Daten: \(store.documents.count) Dokumente, \(store.allTags.count) Tags, "
                     + "\(store.allCorrespondents.count) Sender, \(store.allDocTypes.count) Typen")
        lines.append("Posteingang-Tags: \(store.inboxTagIDs.count)")
        lines.append("Warteschlange: \(store.pendingUploads.count) Uploads, \(store.pendingEdits.count) Änderungen")
        lines.append("KI verfügbar: \(AIService.shared.modelAvailable ? "ja" : "nein")")
        return lines.joined(separator: "\n")
    }

    private func runProbe() async {
        isProbing = true
        probe = await store.probeConnection()
        isProbing = false
    }
}

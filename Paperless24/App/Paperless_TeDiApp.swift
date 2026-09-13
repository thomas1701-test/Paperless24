import SwiftUI
import os

@main
struct Paperless24App: App {
    private static let logger = Logger(subsystem: "de.tedi.paperless", category: "import")

    @StateObject private var store = AppStore()
    @AppStorage("appLanguage") private var appLanguage = ""
    @Environment(\.scenePhase) private var scenePhase

    init() {
        NotificationService.registerBackgroundTask()
        SettingsSyncService.start()
        NotificationService.scheduleRefresh()
    }

    private var locale: Locale {
        appLanguage.isEmpty ? .current : Locale(identifier: appLanguage)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, locale)
                .onOpenURL { url in
                    if url.scheme == AppConstants.urlScheme {
                        if url.host == "check_shared" {
                            checkForSharedFile()
                        } else if url.host == "document" {
                            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                            if let idStr = components?.queryItems?.first(where: { $0.name == "id" })?.value,
                               let id = Int(idStr) {
                                store.triggerOpenDocument(id: id)
                            }
                        } else if url.host == "exchange" || url.host == "import" {
                            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                            let filename = components?.queryItems?.first(where: { $0.name == "name" })?.value ?? "Import.pdf"
                            if let pasteboard = UIPasteboard(name: UIPasteboard.Name("PaperlessExchange"), create: false),
                               let data = pasteboard.data(forPasteboardType: "com.paperless24.data") {
                                store.handleImportData(data: data, filename: filename)
                                pasteboard.items = []
                            } else if let data = UIPasteboard.general.data(forPasteboardType: "com.paperless24.shared") {
                                store.handleImportData(data: data, filename: filename)
                                UIPasteboard.general.items = []
                            }
                        } else if url.host == "inbox" {
                            // Aus dem Sperrbildschirm-Widget. Vorher kannte die App diese Adresse
                            // nicht — der Tipp öffnete sie, landete aber nicht im Posteingang.
                            store.requestInbox = true
                        } else if url.host == "pick" {
                            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
                            if let callback = components?.queryItems?.first(where: { $0.name == "callback" })?.value,
                               AppConstants.isAllowedPickerCallback(callback) {
                                store.pickerCallbackURL = callback
                            }
                        }
                    } else if url.isFileURL {
                        store.handleIncomingFile(url: url)
                    }
                }
                // Auffangnetz: Öffnet die Erweiterung die App nicht (aus einem Share-Sheet
                // darf sie das nicht immer), liegt die Datei trotzdem in der App Group.
                // Beim nächsten Start bzw. Wechsel in den Vordergrund holen wir sie ab.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        checkForSharedFile()
                        handleControlRequests()
                        NotificationService.clearBadge()
                        store.appDidBecomeActive()
                    } else if phase == .background {
                        store.appDidEnterBackground()
                    }
                }
                // Beim Kaltstart steht die Szene je nach System schon auf `active`, dann
                // bleibt `onChange` stumm — deshalb zusätzlich einmal beim Erscheinen.
                .task { checkForSharedFile(); handleControlRequests() }
        }
    }

    /// Löst aus, was über ein Control im Control Center oder auf dem Sperrbildschirm
    /// angetippt wurde.
    ///
    /// Controls können die App nur öffnen, nicht in ihr navigieren. Der Wunsch liegt deshalb
    /// als Marke in der App Group und wird hier eingelöst — und sofort gelöscht, damit der
    /// nächste Start nicht wieder im Scanner landet.
    private func handleControlRequests() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupId) else { return }
        if defaults.bool(forKey: "control_request_scan") {
            defaults.removeObject(forKey: "control_request_scan")
            store.requestScan = true
        }
        if defaults.bool(forKey: "control_request_inbox") {
            defaults.removeObject(forKey: "control_request_inbox")
            store.requestInbox = true
        }
    }

    /// Holt die nächste geteilte Datei ab. Weitere folgen, sobald das Importformular schließt
    /// (`MainDocView`).
    private func checkForSharedFile() {
        store.importNextSharedFile()
    }
}

import SwiftUI

@main
struct Paperless_TeDiApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
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
                               let data = pasteboard.data(forPasteboardType: "com.paperlesstedi.data") {
                                store.handleImportData(data: data, filename: filename)
                                pasteboard.items = []
                            } else if let data = UIPasteboard.general.data(forPasteboardType: "com.paperlesstedi.shared") {
                                store.handleImportData(data: data, filename: filename)
                                UIPasteboard.general.items = []
                            }
                        }
                    } else if url.isFileURL {
                        store.handleIncomingFile(url: url)
                    }
                }
        }
    }

    private func checkForSharedFile() {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupId),
              let filename = defaults.string(forKey: "shared_filename"),
              let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupId) else { return }

        let fileURL = sharedURL.appendingPathComponent("shared_import.data")
        do {
            let data = try Data(contentsOf: fileURL)
            store.handleImportData(data: data, filename: filename)
            defaults.removeObject(forKey: "shared_filename")
            try? FileManager.default.removeItem(at: fileURL)
        } catch {
            print("Fehler beim Laden aus App Group: \(error)")
        }
    }
}

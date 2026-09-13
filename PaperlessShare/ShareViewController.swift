import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

@objc(ShareViewController)
class ShareViewController: UIViewController {

    let appGroupId = SharedConstants.appGroupId

    override func viewDidLoad() {
        super.viewDidLoad()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.handleShare() }
    }

    /// Übernimmt **alle** geteilten Dateien.
    ///
    /// Vorher nur den ersten Anhang — wer fünf PDFs teilte, bekam eines. Und jede Freigabe
    /// überschrieb dieselbe Datei `shared_import.data`: Teilte man zweimal, bevor die App sie
    /// abholte, war die erste weg. Jetzt liegt jede Datei unter eigenem Namen in `SharedImports/`
    /// (Datei + `.name` mit dem Dateinamen), und die App holt sie der Reihe nach ab.
    private func handleShare() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier("public.data") }
        guard !providers.isEmpty else {
            self.kill(String(localized: "share_no_data"))
            return
        }
        guard let inbox = importDirectory() else {
            self.kill("App Group nicht gefunden! Prüfe 'Signing & Capabilities'.")
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var saved = 0
        var lastError: String? = nil

        for provider in providers {
            group.enter()
            // Wir laden ALLES als "public.data"
            provider.loadItem(forTypeIdentifier: "public.data", options: nil) { (result, error) in
                defer { group.leave() }
                let outcome: String?
                if let error {
                    outcome = String(format: String(localized: "share_error_fmt"), error.localizedDescription)
                } else if let url = result as? URL {
                    // Kopieren statt einlesen: Eine Share-Extension hat wenig Speicher, und ein
                    // großes PDF komplett in den Speicher zu holen ließ sie abstürzen.
                    outcome = self.store(inbox: inbox, filename: url.lastPathComponent) { try FileManager.default.copyItem(at: url, to: $0) }
                } else if let data = result as? Data {
                    outcome = self.store(inbox: inbox, filename: "Import.pdf") { try data.write(to: $0, options: [.atomic, .completeFileProtectionUnlessOpen]) }
                } else if let image = result as? UIImage, let data = image.jpegData(compressionQuality: 0.8) {
                    outcome = self.store(inbox: inbox, filename: "Foto.jpg") { try data.write(to: $0, options: [.atomic, .completeFileProtectionUnlessOpen]) }
                } else {
                    outcome = String(localized: "share_empty_data")
                }
                lock.lock()
                if let outcome { lastError = outcome } else { saved += 1 }
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            if saved > 0 {
                self.openMainApp()
            } else {
                self.kill(lastError ?? String(localized: "share_empty_data"))
            }
        }
    }

    private func importDirectory() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else { return nil }
        let dir = container.appendingPathComponent("SharedImports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Legt eine Datei samt Namensdatei ab. Liefert `nil` bei Erfolg, sonst die Fehlermeldung.
    private func store(inbox: URL, filename: String, write: (URL) throws -> Void) -> String? {
        // Zeitstempel vorn: Die App holt die Dateien in der Reihenfolge ab, in der sie kamen.
        let id = String(format: "%.6f", Date().timeIntervalSince1970) + "-" + UUID().uuidString
        let fileURL = inbox.appendingPathComponent(id)
        do {
            try write(fileURL)
            try Data(filename.utf8).write(to: inbox.appendingPathComponent(id + ".name"), options: .atomic)
            return nil
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return String(format: String(localized: "share_save_error_fmt"), error.localizedDescription)
        }
    }
    
    private func openMainApp() {
        DispatchQueue.main.async {
            // Wir rufen einfach nur "check" auf, die App weiß dann, wo sie suchen muss.
            guard let url = URL(string: "\(SharedConstants.urlScheme)://check_shared") else {
                self.finish()
                return
            }

            // `extensionContext.open` klingt nach dem offiziellen Weg, ist unter iOS aber
            // ausdrücklich nur für Today-Erweiterungen vorgesehen: aus einem Share-Sheet
            // heraus liefert es immer `false` und öffnet nichts. Deshalb der Umweg über die
            // Responder-Kette — wir suchen die `UIApplication` und rufen die aktuelle,
            // nicht veraltete `open(_:options:completionHandler:)` auf.
            var responder: UIResponder? = self
            while let current = responder {
                if let app = current as? UIApplication {
                    app.open(url, options: [:]) { _ in self.finish() }
                    return
                }
                responder = current.next
            }

            // Kein `UIApplication` in der Kette: Datei liegt bereits in der App Group, die
            // App holt sie sich beim nächsten Start. Nur Bescheid geben, nicht als Fehler.
            self.showNoticeAndFinish(String(localized: "share_saved_open_app"))
        }
    }
    
    private func kill(_ msg: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Fehler", message: msg, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            })
            self.present(alert, animated: true)
        }
    }
    
    private func finish() {
        self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func showNoticeAndFinish(_ msg: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Paperless24", message: msg, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in self.finish() })
            self.present(alert, animated: true)
        }
    }
}

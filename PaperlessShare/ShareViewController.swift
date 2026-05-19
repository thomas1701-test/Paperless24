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

    private func handleShare() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem],
              let item = items.first,
              let attachments = item.attachments,
              let provider = attachments.first else {
            self.kill(String(localized: "share_no_data"))
            return
        }

        // Wir laden ALLES als "public.data"
        provider.loadItem(forTypeIdentifier: "public.data", options: nil) { (result, error) in
            if let error = error {
                self.kill(String(format: String(localized: "share_error_fmt"), error.localizedDescription))
                return
            }

            var sourceData: Data? = nil
            var filename = "Import.pdf"

            if let url = result as? URL {
                sourceData = try? Data(contentsOf: url)
                filename = url.lastPathComponent
            } else if let data = result as? Data {
                sourceData = data
            } else if let image = result as? UIImage {
                sourceData = image.jpegData(compressionQuality: 0.8)
                filename = "Foto.jpg"
            }

            if let validData = sourceData {
                self.saveToAppGroup(data: validData, filename: filename)
            } else {
                self.kill(String(localized: "share_empty_data"))
            }
        }
    }
    
    private func saveToAppGroup(data: Data, filename: String) {
        // 1. Zugriff auf den gemeinsamen Ordner
        guard let sharedURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            self.kill("App Group nicht gefunden! Prüfe 'Signing & Capabilities'.")
            return
        }
        
        let saveURL = sharedURL.appendingPathComponent("shared_import.data")
        
        do {
            // 2. Datei speichern (überschreibt alte)
            try data.write(to: saveURL)
            
            // 3. Metadaten in UserDefaults speichern (als Signal)
            if let sharedDefaults = UserDefaults(suiteName: appGroupId) {
                sharedDefaults.set(filename, forKey: "shared_filename")
                sharedDefaults.set(Date(), forKey: "shared_date") // Zeitstempel damit wir wissen, es ist neu
                sharedDefaults.synchronize()
            }
            
            // 4. App öffnen
            self.openMainApp()
            
        } catch {
            self.kill(String(format: String(localized: "share_save_error_fmt"), error.localizedDescription))
        }
    }
    
    private func openMainApp() {
        DispatchQueue.main.async {
            // Wir rufen einfach nur "check" auf, die App weiß dann, wo sie suchen muss
            let url = URL(string: "paperless24://check_shared")!
            
            var responder: UIResponder? = self
            var success = false
            while responder != nil {
                if let app = responder as? UIApplication {
                    app.open(url)
                    success = true
                    break
                }
                responder = responder?.next
            }
            
            if success {
                self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            } else {
                self.showErrorAndStay("Konnte App nicht öffnen. URL Scheme korrekt?")
            }
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
    
    private func showErrorAndStay(_ msg: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Diagnose", message: msg, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true)
        }
    }
}

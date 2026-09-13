import Foundation
import UIKit

/// Findet AirScan-fähige Netzwerkscanner (Bonjour `_uscan._tcp`) und steuert sie über
/// das eSCL-Protokoll. Best-effort: funktioniert nicht mit jedem Gerät.
final class AirScanService: NSObject, ObservableObject {
    @Published var scanners: [DiscoveredScanner] = []
    @Published var isDiscovering = false
    @Published var isScanning = false
    @Published var statusText = ""

    private var browser: NetServiceBrowser?
    private var resolving: [NetService] = []

    struct DiscoveredScanner: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let host: String
        let port: Int

        /// IPv6-Adressen gehören in eckige Klammern, sonst liest `URL` den Doppelpunkt als
        /// Trenner vor dem Port und die Adresse wird ungültig.
        var baseURL: URL? {
            let hostPart = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
            return URL(string: "http://\(hostPart):\(port)/eSCL")
        }
    }

    // MARK: - Discovery

    func startDiscovery() {
        scanners = []
        resolving = []
        isDiscovering = true
        let b = NetServiceBrowser()
        b.delegate = self
        b.searchForServices(ofType: "_uscan._tcp.", inDomain: "local.")
        browser = b
    }

    func stopDiscovery() {
        browser?.stop()
        browser = nil
        isDiscovering = false
    }

    // MARK: - Scan (eSCL)

    /// Startet einen Scan und liefert PDF-Daten (JPEG-Ergebnisse werden in PDF gewandelt).
    func scan(_ scanner: DiscoveredScanner) async -> Data? {
        guard let base = scanner.baseURL else { return nil }
        await setStatus("Scan wird gestartet …", scanning: true)

        let settings = """
        <?xml version="1.0" encoding="UTF-8"?>
        <scan:ScanSettings xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
          <pwg:Version>2.6</pwg:Version>
          <scan:Intent>Document</scan:Intent>
          <pwg:InputSource>Platen</pwg:InputSource>
          <scan:ColorMode>RGB24</scan:ColorMode>
          <scan:DocumentFormatExt>application/pdf</scan:DocumentFormatExt>
          <scan:XResolution>300</scan:XResolution>
          <scan:YResolution>300</scan:YResolution>
        </scan:ScanSettings>
        """

        var req = URLRequest(url: base.appendingPathComponent("ScanJobs"))
        req.httpMethod = "POST"
        req.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        req.httpBody = settings.data(using: .utf8)
        req.timeoutInterval = 30

        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse,
              (200...201).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location") else {
            await setStatus("Scanner antwortet nicht.", scanning: false)
            return nil
        }

        await setStatus("Seite wird übertragen …", scanning: true)
        let docURLString = location.hasSuffix("/") ? "\(location)NextDocument" : "\(location)/NextDocument"
        guard let docURL = URL(string: docURLString),
              let (data, dResp) = try? await URLSession.shared.data(from: docURL),
              let dHttp = dResp as? HTTPURLResponse, dHttp.statusCode == 200 else {
            await setStatus("Kein Dokument empfangen.", scanning: false)
            return nil
        }

        await setStatus("", scanning: false)
        // PDF direkt zurück, JPEG/PNG in PDF wandeln.
        if data.starts(with: [0x25, 0x50, 0x44, 0x46]) { return data } // %PDF
        if let image = UIImage(data: data) { return ScanPDF.make(from: [image]) }
        return data
    }


    @MainActor
    private func setStatus(_ text: String, scanning: Bool) {
        statusText = text
        isScanning = scanning
    }
}

// MARK: - Bonjour-Delegates

extension AirScanService: NetServiceBrowserDelegate, NetServiceDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        resolving.append(service)
        service.resolve(withTimeout: 5)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let host = sender.hostName else { return }
        let scanner = DiscoveredScanner(name: sender.name, host: host, port: sender.port)
        DispatchQueue.main.async {
            if !self.scanners.contains(where: { $0.host == scanner.host && $0.port == scanner.port }) {
                self.scanners.append(scanner)
            }
        }
        resolving.removeAll { $0 == sender }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        resolving.removeAll { $0 == sender }
    }
}

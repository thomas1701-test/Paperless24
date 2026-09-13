import SwiftUI

struct AuthImage: View {
    let docId: Int
    let urlString: String
    let token: String
    let contentMode: ContentMode

    @State private var image: UIImage? = nil

    var body: some View {
        Group {
            if let i = image {
                GeometryReader { g in
                    ZStack {
                        Color.white
                        Image(uiImage: i)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                            .frame(width: g.size.width, height: g.size.height)
                            .clipped()
                    }
                }
            } else {
                Rectangle().fill(Material.ultraThin)
                    .overlay(Image(systemName: "doc.text").foregroundColor(.gray))
            }
        }
        // Das fertige Bild blendet sich ein, statt den Platzhalter hart zu ersetzen.
        .animation(.easeOut(duration: 0.2), value: image != nil)
        // Die Platte nicht im Zeichnen lesen: Vorher las `getImage` bei jeder neu erscheinenden
        // Zelle Datei und JPEG synchron auf dem Main Thread — beim schnellen Scrollen spürbar.
        .task(id: docId) {
            guard image == nil else { return }
            if let cached = await ImageCache.shared.loadImage(for: docId) {
                image = cached
            } else {
                await download()
            }
        }
    }

    private func download() async {
        guard let url = URL(string: urlString) else { return }
        // Konto vor dem Warten festhalten: Der Bildcache folgt dem aktiven Konto, und nach
        // einem Wechsel landete die Vorschau sonst unter derselben ID im Cache des neuen.
        let account = ImageCache.shared.currentAccountId
        var req = URLRequest(url: url)
        req.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        // Derselbe Zugangsweg wie für alle anderen Anfragen. Vorher ging die Vorschau über
        // `URLSession.shared` ohne eigene Kopfzeilen und ohne Client-Zertifikat — hinter
        // Cloudflare Access oder einem mTLS-Proxy blieben alle Miniaturen leer.
        let server = Self.serverBase(of: urlString)
        PaperlessAPI.applyCustomHeaders(to: &req, server: server)
        let session = ClientCertSessionProvider.shared.session(for: server)
        guard let (data, response) = try? await session.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let img = UIImage(data: data) else { return }
        ImageCache.shared.saveImage(img, for: docId, ifAccount: account)
        withAnimation { image = img }
    }

    /// `https://host/pfad/api/documents/42/thumb/` → `https://host/pfad` — der Schlüssel, unter
    /// dem Kopfzeilen und Zertifikat hinterlegt sind (`PaperlessAPI.serverBase`).
    static func serverBase(of urlString: String) -> String {
        guard let range = urlString.range(of: "/api/", options: .backwards) else { return urlString }
        return String(urlString[..<range.lowerBound])
    }
}

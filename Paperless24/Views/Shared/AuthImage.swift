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
        .onAppear {
            if let cached = ImageCache.shared.getImage(for: docId) {
                image = cached
            } else {
                Task { await download() }
            }
        }
    }

    private func download() async {
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        req.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let img = UIImage(data: data) else { return }
        ImageCache.shared.saveImage(img, for: docId)
        withAnimation { image = img }
    }
}

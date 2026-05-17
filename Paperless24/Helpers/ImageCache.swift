import UIKit

class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    init() {
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = urls[0].appendingPathComponent("Thumbnails")
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func getImage(for id: Int) -> UIImage? {
        let key = NSString(string: "\(id)")
        if let cached = cache.object(forKey: key) { return cached }
        let fileURL = cacheDirectory.appendingPathComponent("\(id).jpg")
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            cache.setObject(image, forKey: key)
            return image
        }
        return nil
    }

    func getFilePath(for id: Int) -> URL {
        cacheDirectory.appendingPathComponent("\(id).jpg")
    }

    func saveImage(_ image: UIImage, for id: Int) {
        let key = NSString(string: "\(id)")
        cache.setObject(image, forKey: key)
        DispatchQueue.global(qos: .background).async {
            let fileURL = self.cacheDirectory.appendingPathComponent("\(id).jpg")
            if let data = image.jpegData(compressionQuality: 0.7) {
                try? data.write(to: fileURL)
            }
        }
    }

    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

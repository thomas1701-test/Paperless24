import SwiftUI
import PDFKit
import LocalAuthentication
import UniformTypeIdentifiers
import VisionKit
import Vision
import PhotosUI

// --- KONFIGURATION ---
let appVersion = "1.69.0 (High Performance)"

// MARK: - 1. IMAGE CACHE & UTILS
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
        if let cachedImage = cache.object(forKey: key) { return cachedImage }
        let fileURL = cacheDirectory.appendingPathComponent("\(id).jpg")
        if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
            cache.setObject(image, forKey: key)
            return image
        }
        return nil
    }
    
    func saveImage(_ image: UIImage, for id: Int) {
        let key = NSString(string: "\(id)")
        cache.setObject(image, forKey: key)
        DispatchQueue.global(qos: .background).async {
            let fileURL = self.cacheDirectory.appendingPathComponent("\(id).jpg")
            if let data = image.jpegData(compressionQuality: 0.7) { try? data.write(to: fileURL) }
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - 2. MODELLE
struct Tag: Identifiable, Codable, Hashable { let id: Int; let name: String; let color: String }
struct Correspondent: Identifiable, Codable, Hashable { let id: Int; let name: String }
struct DocumentType: Identifiable, Codable, Hashable { let id: Int; let name: String }
struct DocNote: Identifiable, Codable, Hashable { let id: Int; let note: String; let created: String; let user: Int? }
struct PaperlessDocument: Identifiable, Codable {
    let id: Int; let title: String; let content: String?
    let created: String; let added: String?
    let correspondent: Int?; let document_type: Int?; let archive_serial_number: Int?
    let tags: [Int]
}
struct PaperlessStatistics: Codable { let documents_total: Int?; let documents_inbox: Int?; let character_count: Int? }
struct PendingUpload: Identifiable, Codable {
    var id: UUID = UUID(); let data: Data; let filename: String; let title: String
    let created: Date; let correspondent: Int?; let documentType: Int?; let tags: [Int]
}
struct UploadContainer: Identifiable { let id = UUID(); let data: Data; let filename: String }

struct DocumentResponse: Codable { let results: [PaperlessDocument] }
struct TagResponse: Codable { let results: [Tag] }
struct CorrespondentResponse: Codable { let results: [Correspondent] }
struct DocTypeResponse: Codable { let results: [DocumentType] }

struct ChangelogEntry: Identifiable {
    let id = UUID(); let version: String; let date: String; let changes: [String]
}

let appChangelog = [
    ChangelogEntry(version: "1.69.0", date: "24.01.2026", changes: ["Performance: Download-Abbruch beim schnellen Scrollen (spart Daten & CPU)", "Performance: Weniger Schatten für flüssigeres Rendering"]),
    ChangelogEntry(version: "1.68.3", date: "24.01.2026", changes: ["Fix: SettingsView wiederhergestellt", "Fix: Compiler-Fehler behoben"]),
]

// MARK: - 3. DATA MANAGER
class DataManager: ObservableObject {
    @Published var documents: [PaperlessDocument] = []
    @Published var allTags: [Tag] = []
    @Published var allCorrespondents: [Correspondent] = []
    @Published var allDocTypes: [DocumentType] = []
    @Published var pendingUploads: [PendingUpload] = []
    
    @Published var isOffline: Bool = false
    @Published var isSyncing: Bool = false
    @Published var storageSize: String = "..."
    @Published var cachedCount: Int = 0
    @Published var uploadSuccessMessage: String? = nil
    
    @Published var isDownloadingAll: Bool = false
    @Published var downloadProgress: Double = 0.0
    @Published var downloadStatusText: String = ""
    
    @AppStorage("lastSyncDate") var lastSyncDate: Double = 0
    @AppStorage("serverUrl") var serverUrl = ""
    @AppStorage("username") var username = ""
    @AppStorage("password") var password = ""
    @AppStorage("isDemoMode") var isDemoMode = false
    
    init() { loadFromDisk(); calculateStorage() }
    
    func jsonRequest(_ url: URL, _ method: String, _ body: [String: Any], _ comp: @escaping (Int?) -> Void) {
        if isDemoMode { comp(nil); return }
        var req = URLRequest(url: url)
        req.httpMethod = method
        let auth = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""
        req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "GET" && method != "DELETE" {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        
        URLSession.shared.dataTask(with: req) { d, _, _ in
            var newId: Int? = nil
            if let d = d {
                if let json = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    newId = json["id"] as? Int
                }
            }
            DispatchQueue.main.async {
                comp(newId)
                self.sync()
            }
        }.resume()
    }
    
    func handleIncomingFile(url: URL) {
        let secured = url.startAccessingSecurityScopedResource()
        defer { if secured { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let filename = url.lastPathComponent
            addToQueue(data: data, filename: filename, title: filename.replacingOccurrences(of: ".pdf", with: ""), created: Date(), corr: nil, type: nil, tags: [])
            DispatchQueue.main.async {
                self.uploadSuccessMessage = "Datei importiert!"
                if !self.isDemoMode && !self.serverUrl.isEmpty { self.sync() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.uploadSuccessMessage = nil }
            }
        } catch { print("Import error: \(error)") }
    }
    
    func setupDemoData() {
        isDemoMode = true; serverUrl = "demo.local"; username="demo"; password="123"
        allTags=[Tag(id:1,name:"Rechnung",color:"#ff0000"), Tag(id:2,name:"Vertrag",color:"#0000ff"), Tag(id:3,name:"Steuer",color:"#00aa00")]
        allCorrespondents=[Correspondent(id:1,name:"Amazon"), Correspondent(id:2,name:"Telekom")]
        allDocTypes=[DocumentType(id:1,name:"Rechnung"), DocumentType(id:2,name:"Brief")]
        documents=[
            PaperlessDocument(id:1, title:"Rechnung MacBook Pro", content:"Apple Store...", created:"2026-01-20", added:"2026-01-20", correspondent:1, document_type:1, archive_serial_number:101, tags:[1, 3]),
            PaperlessDocument(id:2, title:"Kündigung Mobilfunk", content:"Hiermit kündige ich...", created:"2026-01-22", added:"2026-01-22", correspondent:2, document_type:2, archive_serial_number:102, tags:[2]),
            PaperlessDocument(id:3, title:"Stromrechnung", content:"Stadtwerke...", created:"2026-01-23", added:"2026-01-23", correspondent:nil, document_type:1, archive_serial_number:103, tags:[1,2,3])
        ]
        saveToDisk()
    }
    
    private func getDocURL(_ name: String) -> URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(name) }
    func getLocalFileUrl(for docId: Int) -> URL { getDocURL("doc_\(docId).pdf") }
    func fileExists(docId: Int) -> Bool { FileManager.default.fileExists(atPath: getLocalFileUrl(for: docId).path) }
    
    func calculateStorage() {
        DispatchQueue.global(qos: .background).async {
            var size: Int64 = 0; var count: Int = 0
            if let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                do {
                    let urls = try FileManager.default.contentsOfDirectory(at: docDir, includingPropertiesForKeys: [.fileSizeKey])
                    for url in urls {
                        if let v = try? url.resourceValues(forKeys: [.fileSizeKey]), let s = v.fileSize { size += Int64(s) }
                        if url.lastPathComponent.starts(with: "doc_") && url.pathExtension == "pdf" { count += 1 }
                    }
                } catch {}
            }
            let mb = Double(size) / 1024.0 / 1024.0
            DispatchQueue.main.async { self.storageSize = String(format: "%.2f MB", mb); self.cachedCount = count }
        }
    }
    
    func saveToDisk() {
        DispatchQueue.global(qos: .background).async {
            try? JSONEncoder().encode(self.documents).write(to: self.getDocURL("documents.json"))
            try? JSONEncoder().encode(self.allTags).write(to: self.getDocURL("tags.json"))
            try? JSONEncoder().encode(self.allCorrespondents).write(to: self.getDocURL("corrs.json"))
            try? JSONEncoder().encode(self.allDocTypes).write(to: self.getDocURL("types.json"))
            try? JSONEncoder().encode(self.pendingUploads).write(to: self.getDocURL("pending.json"))
            self.calculateStorage()
        }
    }
    
    func loadFromDisk() {
        if let d = try? Data(contentsOf: getDocURL("documents.json")) { documents = (try? JSONDecoder().decode([PaperlessDocument].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: getDocURL("tags.json")) { allTags = (try? JSONDecoder().decode([Tag].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: getDocURL("corrs.json")) { allCorrespondents = (try? JSONDecoder().decode([Correspondent].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: getDocURL("types.json")) { allDocTypes = (try? JSONDecoder().decode([DocumentType].self, from: d)) ?? [] }
        if let d = try? Data(contentsOf: getDocURL("pending.json")) { pendingUploads = (try? JSONDecoder().decode([PendingUpload].self, from: d)) ?? [] }
    }
    
    func rotatePDF(data: Data) -> Data? {
        guard let pdf = PDFDocument(data: data) else { return nil }
        for i in 0..<pdf.pageCount { if let page = pdf.page(at: i) { page.rotation = (page.rotation + 90) % 360 } }
        return pdf.dataRepresentation()
    }
    
    func startFullDownload() {
        guard !isDownloadingAll, !documents.isEmpty else { return }
        isDownloadingAll = true; downloadProgress = 0.0; downloadNextFile(index: 0)
    }
    
    func stopDownload() { isDownloadingAll = false; downloadStatusText = "Angehalten" }
    
    private func downloadNextFile(index: Int) {
        guard isDownloadingAll, index < documents.count else { isDownloadingAll = false; downloadStatusText = "Fertig!"; calculateStorage(); return }
        let doc = documents[index]; let total = Double(documents.count)
        DispatchQueue.main.async { self.downloadProgress = Double(index)/total; self.downloadStatusText = "Lade \(index+1) von \(Int(total))" }
        if fileExists(docId: doc.id) { downloadNextFile(index: index+1) }
        else {
            if let url = makeURL("documents/\(doc.id)/download/") {
                var req = URLRequest(url: url); let auth = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""; req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
                URLSession.shared.dataTask(with: req) { d, r, _ in
                    if let d=d, (r as? HTTPURLResponse)?.statusCode == 200 { try? d.write(to: self.getLocalFileUrl(for: doc.id)) }
                    self.downloadNextFile(index: index+1)
                }.resume()
            } else { downloadNextFile(index: index+1) }
        }
    }
    
    func sync() {
        if isDemoMode { return }
        guard !serverUrl.isEmpty else { return }
        isSyncing = true
        processQueue {
            let group = DispatchGroup(); var success = true
            group.enter(); self.fetch("documents/?page_size=10000&ordering=-created", DocumentResponse.self) { r in if let r=r{self.documents=r.results}else{success=false}; group.leave()}
            group.enter(); self.fetch("tags/?page_size=1000", TagResponse.self) { r in if let r=r{self.allTags=r.results}else{success=false}; group.leave()}
            group.enter(); self.fetch("correspondents/?page_size=1000", CorrespondentResponse.self) { r in if let r=r{self.allCorrespondents=r.results}else{success=false}; group.leave()}
            group.enter(); self.fetch("document_types/?page_size=1000", DocTypeResponse.self) { r in if let r=r{self.allDocTypes=r.results}else{success=false}; group.leave()}
            group.notify(queue: .main) { self.isSyncing = false; self.isOffline = !success; if success { self.lastSyncDate = Date().timeIntervalSince1970; self.saveToDisk() } }
        }
    }
    
    func processQueue(completion: @escaping () -> Void) {
        if isDemoMode { completion(); return }
        guard !pendingUploads.isEmpty else { completion(); return }
        let item = pendingUploads[0]
        uploadFile(item) { success in
            DispatchQueue.main.async {
                if success {
                    if !self.pendingUploads.isEmpty { self.pendingUploads.removeFirst(); self.saveToDisk() }
                    self.uploadSuccessMessage = "Dokument '\(item.title)' erfolgreich hochgeladen"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.uploadSuccessMessage = nil }
                    self.refreshListOnly()
                    self.processQueue(completion: completion)
                } else { completion() }
            }
        }
    }
    
    func refreshListOnly() {
        if isDemoMode { return }
        guard let url = makeURL("documents/?page_size=10000&ordering=-created") else { return }
        var req = URLRequest(url: url); let auth = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""; req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { d, _, _ in
            if let d = d, let r = try? JSONDecoder().decode(DocumentResponse.self, from: d) {
                DispatchQueue.main.async { self.documents = r.results; self.saveToDisk() }
            }
        }.resume()
    }
    
    func addToQueue(data: Data, filename: String, title: String, created: Date, corr: Int?, type: Int?, tags: [Int]) {
        let item = PendingUpload(data: data, filename: filename, title: title, created: created, correspondent: corr, documentType: type, tags: tags)
        DispatchQueue.main.async { self.pendingUploads.append(item); self.saveToDisk() }
    }
    
    func removePendingUpload(at offsets: IndexSet) {
        pendingUploads.remove(atOffsets: offsets)
        saveToDisk()
    }
    
    func makeURL(_ end: String) -> URL? {
        let clean = serverUrl.trimmingCharacters(in: .whitespacesAndNewlines); let prefix = clean.lowercased().hasPrefix("http") ? "" : "http://"
        return URL(string: "\(prefix)\(clean)/api/\(end)")
    }
    
    func fetch<T: Codable>(_ end: String, _ type: T.Type, completion: @escaping (T?) -> Void) {
        guard let url = makeURL(end) else { completion(nil); return }
        var req = URLRequest(url: url); let auth = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""; req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization"); req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { d, _, _ in if let d=d, let r=try? JSONDecoder().decode(type, from: d) { DispatchQueue.main.async { completion(r) } } else { DispatchQueue.main.async { completion(nil) } } }.resume()
    }
    
    func uploadFile(_ item: PendingUpload, completion: @escaping (Bool) -> Void) {
        guard let url = makeURL("documents/post_document/") else { completion(false); return }
        var req = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 180)
        req.httpMethod = "POST"
        let auth = "\(username):\(password)".data(using: .utf8)?.base64EncodedString() ?? ""
        req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func add(_ n: String, _ v: String) { body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(n)\"\r\n\r\n\(v)\r\n".data(using: .utf8)!) }
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"document\"; filename=\"\(item.filename)\"\r\n\r\n".data(using: .utf8)!); body.append(item.data); body.append("\r\n".data(using: .utf8)!)
        add("title", item.title); add("created", ISO8601DateFormatter().string(from: item.created))
        if let c = item.correspondent { add("correspondent", "\(c)") }; if let t = item.documentType { add("document_type", "\(t)") }
        for tag in item.tags { add("tags", "\(tag)") }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!); req.httpBody = body
        URLSession.shared.dataTask(with: req) { _, r, _ in
            let code = (r as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async { completion((200...299).contains(code)) }
        }.resume()
    }
}

// MARK: - 4. UI HELPER (OPTIMIERT)
struct AuthImage: View {
    let docId: Int
    let urlString: String
    let username: String
    let password: String
    
    // Performance: Wir merken uns den Task, um ihn abzubrechen
    @State private var image: UIImage? = nil
    @State private var task: URLSessionDataTask? = nil
    
    var body: some View {
        ZStack {
            if let i = image {
                Image(uiImage: i).resizable().aspectRatio(contentMode: .fill).frame(height: 180).clipped()
                    .transition(.opacity.animation(.easeInOut(duration: 0.2))) // Sanftes Einblenden
            } else {
                Rectangle().fill(Color(.secondarySystemBackground)).frame(height: 180)
                Image(systemName: "photo").foregroundColor(.gray.opacity(0.5))
            }
        }
        .onAppear {
            loadImage()
        }
        .onDisappear {
            // WICHTIG: Download abbrechen, wenn Bild aus dem Screen scrollt
            task?.cancel()
        }
    }
    
    func loadImage() {
        // 1. Cache Check
        if let cached = ImageCache.shared.getImage(for: docId) {
            self.image = cached
            return
        }
        
        // 2. Download
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        req.setValue("Basic " + "\(username):\(password)".data(using:.utf8)!.base64EncodedString(), forHTTPHeaderField:"Authorization")
        
        task = URLSession.shared.dataTask(with: req) { d, _, _ in
            if let d = d, let i = UIImage(data: d) {
                ImageCache.shared.saveImage(i, for: docId)
                DispatchQueue.main.async { self.image = i }
            }
        }
        task?.resume()
    }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data; func makeUIView(context: Context) -> PDFView { let p = PDFView(); p.autoScales = true; return p }; func updateUIView(_ u: PDFView, context: Context) { if u.document?.dataRepresentation() != data { u.document = PDFDocument(data: data) } }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]; func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }; func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}

struct DashboardItem: View {
    let title: String; let value: String; let icon: String; let color: Color
    var body: some View { VStack(alignment: .leading, spacing: 12) { HStack { Image(systemName: icon).font(.title2).foregroundColor(color); Spacer(); Text(value).font(.title2).bold().foregroundColor(.primary) }; Text(title).font(.subheadline).foregroundColor(.secondary) }.padding().background(Color(.secondarySystemGroupedBackground)).cornerRadius(16).shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1) }
}

struct DocumentCard: View {
    let doc: PaperlessDocument; let serverBase: String; let username: String; let password: String; let allTags: [Tag]; let allCorrespondents: [Correspondent]; let allDocTypes: [DocumentType]
    var isSelected: Bool = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    let prefix = serverBase.lowercased().hasPrefix("http") ? "" : "http://"
                    AuthImage(docId: doc.id, urlString: "\(prefix)\(serverBase)/api/documents/\(doc.id)/thumb/", username: username, password: password)
                    if !doc.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(doc.tags.prefix(2), id: \.self) { tagId in
                                if let tag = allTags.first(where: { $0.id == tagId }) {
                                    // PERFORMANCE: Shadow entfernt für schnelleres Scrollen
                                    Text(tag.name).font(.system(size: 9, weight: .bold)).foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 3).background(Color(hex: tag.color)).cornerRadius(6).lineLimit(1)
                                }
                            }
                            if doc.tags.count > 2 { Text("+\(doc.tags.count - 2)").font(.system(size: 9, weight: .bold)).foregroundColor(.white).padding(.horizontal, 4).padding(.vertical, 3).background(Color.gray.opacity(0.8)).cornerRadius(6) }
                        }.padding(6)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(doc.title).font(.headline).lineLimit(2)
                    HStack {
                        if let id = doc.correspondent, let name = allCorrespondents.first(where:{$0.id==id})?.name { Text(name).font(.caption).foregroundColor(.blue) }
                        Spacer()
                        if let id = doc.document_type, let name = allDocTypes.first(where:{$0.id==id})?.name { Text(name).font(.caption2).padding(4).background(Color.gray.opacity(0.1)).cornerRadius(4) }
                    }
                }.padding(12)
            }
            .background(Color(.secondarySystemGroupedBackground)).cornerRadius(12)
            // PERFORMANCE: Shadow reduziert
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3))
            .contentShape(Rectangle())
            
            if isSelected { Image(systemName: "checkmark.circle.fill").foregroundColor(.blue).background(Color.white.clipShape(Circle())).font(.title2).padding(8) }
        }
    }
}

struct DocumentRow: View {
    let doc: PaperlessDocument; let allTags: [Tag]; let allCorrespondents: [Correspondent]; let allDocTypes: [DocumentType]
    var body: some View {
        HStack {
            Image(systemName: "doc.text.fill").font(.largeTitle).foregroundColor(.blue).padding(.trailing, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(doc.title).font(.headline).lineLimit(1)
                HStack {
                    if let cid = doc.correspondent, let name = allCorrespondents.first(where: {$0.id == cid})?.name { Text(name).font(.caption).foregroundColor(.secondary) }
                    Text("•").font(.caption).foregroundColor(.secondary)
                    Text(doc.created).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            if !doc.tags.isEmpty {
                HStack(spacing: -4) {
                    ForEach(doc.tags.prefix(3), id: \.self) { tagId in
                        if let tag = allTags.first(where: { $0.id == tagId }) {
                            Circle().fill(Color(hex: tag.color)).frame(width: 10, height: 10).overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1))
                        }
                    }
                }
            }
        }.padding(.vertical, 4)
    }
}

struct ScannerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool; let onScan: (Data) -> Void
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController { let s = VNDocumentCameraViewController(); s.delegate = context.coordinator; return s }
    func updateUIViewController(_ u: VNDocumentCameraViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: ScannerView; init(parent: ScannerView) { self.parent = parent }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith s: VNDocumentCameraScan) {
            let r = UIGraphicsPDFRenderer(); let d = r.pdfData { ctx in for i in 0..<s.pageCount { let img = s.imageOfPage(at: i); let rect = CGRect(x:0,y:0,width:img.size.width,height:img.size.height); ctx.beginPage(withBounds: rect, pageInfo: [:]); img.draw(in: rect) } }; parent.onScan(d); parent.isPresented = false
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { parent.isPresented = false }
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool; let onScan: (Data) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(); config.filter = .images
        let picker = PHPickerViewController(configuration: config); picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ u: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker; init(parent: PhotoPicker) { self.parent = parent }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true) { self.parent.isPresented = false }
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { image, _ in
                if let uiImage = image as? UIImage {
                    let pdfRenderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: uiImage.size.width, height: uiImage.size.height))
                    let data = pdfRenderer.pdfData { ctx in ctx.beginPage(); uiImage.draw(at: .zero) }
                    DispatchQueue.main.async { self.parent.onScan(data) }
                }
            }
        }
    }
}

// MARK: - 5. VIEWS & UPLOAD
struct OfflineDocsView: View {
    let documents: [PaperlessDocument]; var body: some View { List(documents) { doc in VStack(alignment: .leading) { Text(doc.title).font(.headline); Text(doc.created).font(.caption) } }.navigationTitle("Cache") }
}
struct PendingQueueView: View {
    @ObservedObject var dataManager: DataManager
    var body: some View {
        List {
            ForEach(dataManager.pendingUploads) { item in HStack { Image(systemName: "doc"); Text(item.title) } }
                .onDelete(perform: dataManager.removePendingUpload)
        }
        .navigationTitle("Warteschlange")
    }
}

struct ChangelogView: View {
    var body: some View {
        List(appChangelog) { entry in
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text("v\(entry.version)").font(.headline); Spacer(); Text(entry.date).font(.caption).foregroundColor(.secondary) }
                ForEach(entry.changes, id: \.self) { change in Text("• \(change)").font(.subheadline) }
            }.padding(.vertical, 4)
        }.navigationTitle("Änderungsprotokoll")
    }
}

struct SettingsView: View {
    @ObservedObject var dataManager: DataManager
    @Binding var isPresented: Bool
    let onLogout: () -> Void
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @State private var stats: PaperlessStatistics? = nil
    
    func formatNumber(_ n: Int?) -> String { guard let n=n else {return "0"}; let f = NumberFormatter(); f.numberStyle = .decimal; return f.string(from: NSNumber(value: n)) ?? "\(n)" }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Dashboard").font(.headline)) { VStack(spacing: 12) { HStack(spacing: 12) { DashboardItem(title: "Posteingang", value: "\(stats?.documents_inbox ?? 0)", icon: "tray.full.fill", color: .pink); DashboardItem(title: "Dokumente", value: formatNumber(stats?.documents_total), icon: "doc.text.fill", color: .blue) }; HStack(spacing: 12) { DashboardItem(title: "Zeichen", value: formatNumber(stats?.character_count), icon: "text.alignleft", color: .purple); DashboardItem(title: "Letzte ASN", value: "\(dataManager.documents.compactMap{$0.archive_serial_number}.max() ?? 0)", icon: "number", color: .orange) } }.padding(.vertical, 8).listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                Section("Metadaten") { HStack{Image(systemName:"person.2.fill").foregroundColor(.indigo);Text("Korrespondenten");Spacer();Text("\(dataManager.allCorrespondents.count)")}; HStack{Image(systemName:"tag.fill").foregroundColor(.green);Text("Tags");Spacer();Text("\(dataManager.allTags.count)")}; HStack{Image(systemName:"doc.fill").foregroundColor(.teal);Text("Dokumententypen");Spacer();Text("\(dataManager.allDocTypes.count)")} }
                Section("Offline & Speicher") { HStack{Text("Belegt");Spacer();Text(dataManager.storageSize)}; HStack{Text("Verfügbar");Spacer();Text("\(dataManager.cachedCount) von \(dataManager.documents.count)").foregroundColor(dataManager.cachedCount==dataManager.documents.count ? .green : .orange)}; if dataManager.isDownloadingAll { VStack(alignment:.leading){Text("Lade...").bold();ProgressView(value: dataManager.downloadProgress);HStack{Text(dataManager.downloadStatusText).font(.caption).foregroundColor(.secondary);Spacer();Button("Stop"){dataManager.stopDownload()}.foregroundColor(.red)}} } else { Button(action:{dataManager.startFullDownload()}){Label("Alle Dateien herunterladen", systemImage:"arrow.down.circle.fill")} }; NavigationLink("Cache Index", destination: OfflineDocsView(documents: dataManager.documents)); NavigationLink("Warteschlange (\(dataManager.pendingUploads.count))", destination: PendingQueueView(dataManager: dataManager)) }
                Section {
                    NavigationLink(destination: ChangelogView()) { Label("Changelog", systemImage: "list.bullet.rectangle") }
                    HStack{Text("Server");Spacer();Text(dataManager.isDemoMode ? "Demo" : dataManager.serverUrl).foregroundColor(.secondary)}
                    Picker("Design", selection: $appearanceMode){Text("Auto").tag(0);Text("Hell").tag(1);Text("Dunkel").tag(2)}.pickerStyle(.segmented)
                    Button("Abmelden", role: .destructive){isPresented=false;onLogout()}
                    HStack{Spacer();Text("v\(appVersion)").font(.caption).foregroundColor(.gray);Spacer()}
                }
            }
            .navigationTitle("Statistiken")
            .toolbar{ToolbarItem(placement:.confirmationAction){Button("Fertig"){isPresented=false}}}
            .onAppear{
                dataManager.calculateStorage()
                if !dataManager.isDemoMode, let url = dataManager.makeURL("statistics/") {
                    var req=URLRequest(url:url)
                    req.setValue("Basic "+"\(dataManager.username):\(dataManager.password)".data(using:.utf8)!.base64EncodedString(), forHTTPHeaderField:"Authorization")
                    URLSession.shared.dataTask(with:req){d,_,_ in if let d=d{self.stats=try? JSONDecoder().decode(PaperlessStatistics.self,from:d)}}.resume()
                }
            }
        }
    }
}

struct UploadDocumentView: View {
    let container: UploadContainer
    let allTags: [Tag]; let allCorrespondents: [Correspondent]; let allDocTypes: [DocumentType]
    let onUpload: (Data, String, String, Date, Int?, Int?, [Int], @escaping ()->Void)->Void; let onCancel: ()->Void; let onCreateTag: (String, @escaping (Int)->Void)->Void; let onCreateCorr: (String, @escaping (Int)->Void)->Void; let onCreateType: (String, @escaping (Int)->Void)->Void
    
    @State private var modifiedData: Data? = nil
    var currentData: Data { modifiedData ?? container.data }
    
    @State private var title=""; @State private var date=Date(); @State private var corr:Int?; @State private var type:Int?; @State private var tags:Set<Int>=[]
    @State private var showTagAlert=false; @State private var newTag=""; @State private var showCorrAlert=false; @State private var newCorr=""; @State private var showTypeAlert=false; @State private var newType=""; @State private var isUploading=false
    @State private var isAnalyzing=false; @State private var analysisResult=""
    
    let rotator = DataManager()
    
    var body: some View {
        NavigationView {
            Form {
                Section("Vorschau") {
                    HStack(alignment: .top) {
                        Image(systemName: "doc.text.fill").font(.largeTitle).foregroundColor(.red)
                        VStack(alignment: .leading) {
                            Text(container.filename).font(.headline).lineLimit(1)
                            Text("\(ByteCountFormatter.string(fromByteCount: Int64(currentData.count), countStyle: .file))").font(.caption).foregroundColor(.gray)
                        }
                        Spacer()
                        Button(action: rotate) { VStack { Image(systemName: "arrow.clockwise"); Text("Drehen").font(.caption2) } }.buttonStyle(.bordered)
                    }
                    Button(action: runAIAnalysis) {
                        HStack { Spacer(); if isAnalyzing { ProgressView().padding(.trailing, 5) }; Image(systemName: "wand.and.stars"); Text(isAnalyzing ? "Analysiere..." : "Automatisch ausfüllen"); Spacer() }
                    }.buttonStyle(.borderedProminent).disabled(isAnalyzing).padding(.top, 5)
                    if !analysisResult.isEmpty { Text(analysisResult).font(.caption).foregroundColor(.purple).padding(4).background(Color.purple.opacity(0.1)).cornerRadius(4) }
                }
                Section("Metadaten") { TextField("Titel", text: $title); DatePicker("Datum", selection: $date, displayedComponents: .date) }
                
                Section(header: HStack{Text("Korrespondent");Spacer();Button{newCorr="";showCorrAlert=true}label:{Image(systemName:"plus.circle")}.buttonStyle(.borderless)}) {
                    Picker("Wählen", selection: $corr){Text("Keiner").tag(Int?.none);ForEach(allCorrespondents){c in Text(c.name).tag(c.id as Int?)}}
                }
                
                Section(header: HStack{Text("Typ");Spacer();Button{newType="";showTypeAlert=true}label:{Image(systemName:"plus.circle")}.buttonStyle(.borderless)}) {
                    Picker("Wählen", selection: $type){Text("Keiner").tag(Int?.none);ForEach(allDocTypes){t in Text(t.name).tag(t.id as Int?)}}
                }
                
                Section(header: HStack{Text("Tags");Spacer();Button{newTag="";showTagAlert=true}label:{Image(systemName:"plus.circle")}.buttonStyle(.borderless)}) {
                    List{ForEach(allTags){t in HStack{Text(t.name);Spacer();if tags.contains(t.id){Image(systemName:"checkmark")}}.contentShape(Rectangle()).onTapGesture{if tags.contains(t.id){tags.remove(t.id)}else{tags.insert(t.id)}}}}
                }
            }
            .navigationTitle("Upload").interactiveDismissDisabled(isUploading)
            .toolbar {
                ToolbarItem(placement:.cancellationAction){Button("Abbruch"){onCancel()}.disabled(isUploading)}
                ToolbarItem(placement:.confirmationAction){
                    if isUploading{ProgressView()}else{Button("Hochladen"){
                        isUploading=true
                        let finalTitle = title.isEmpty ? container.filename : title
                        onUpload(currentData, container.filename, finalTitle, date, corr, type, Array(tags)){ isUploading=false; onCancel() }
                    }}
                }
            }
            .alert("Neuer Tag", isPresented: $showTagAlert){
                TextField("Name", text: $newTag)
                Button("OK"){ onCreateTag(newTag) { id in self.tags.insert(id) } }
            }
            .alert("Neuer Korrespondent", isPresented: $showCorrAlert){
                TextField("Name", text: $newCorr)
                Button("OK"){ onCreateCorr(newCorr) { id in self.corr = id } }
            }
            .alert("Neuer Typ", isPresented: $showTypeAlert){
                TextField("Name", text: $newType)
                Button("OK"){ onCreateType(newType) { id in self.type = id } }
            }
            .onAppear { if title.isEmpty { title = container.filename } }
        }
    }
    
    func rotate() { if let newD = rotator.rotatePDF(data: currentData) { modifiedData = newD } }
    
    func runAIAnalysis() {
        guard let pdf = PDFDocument(data: currentData), let page = pdf.page(at: 0) else { return }
        isAnalyzing = true; analysisResult = "Analysiere Text..."
        let thumb = page.thumbnail(of: CGSize(width: 1000, height: 1000), for: .mediaBox)
        guard let cgImage = thumb.cgImage else { isAnalyzing = false; return }
        let request = VNRecognizeTextRequest { req, err in
            defer { DispatchQueue.main.async { self.isAnalyzing = false } }
            guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
            let fullText = obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
            DispatchQueue.main.async {
                var foundInfo = [String](); var titleParts = [String]()
                for c in allCorrespondents { if fullText.contains(c.name.lowercased()) { self.corr = c.id; foundInfo.append("Absender: \(c.name)"); titleParts.append(c.name); break } }
                for dt in allDocTypes { if fullText.contains(dt.name.lowercased()) { self.type = dt.id; foundInfo.append("Typ: \(dt.name)"); titleParts.append(dt.name); break } }
                var tagFound = false
                for t in allTags { if fullText.contains(t.name.lowercased()) { self.tags.insert(t.id); foundInfo.append("Tag: \(t.name)"); if !tagFound { titleParts.append(t.name); tagFound = true } } }
                
                if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
                    let matches = detector.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count))
                    if let match = matches.first, let detectedDate = match.date {
                        self.date = detectedDate
                        foundInfo.append("Datum: \(ISO8601DateFormatter().string(from: detectedDate).prefix(10))")
                    }
                }
                
                if !titleParts.isEmpty { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let dateStr = f.string(from: self.date); self.title = titleParts.joined(separator: " - ") + " - " + dateStr }
                self.analysisResult = foundInfo.isEmpty ? "Nichts gefunden." : "Gefunden: " + foundInfo.joined(separator: ", ")
            }
        }
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        DispatchQueue.global(qos: .userInitiated).async { try? handler.perform([request]) }
    }
}

// MARK: - 6. DOCUMENT DETAIL VIEW
struct DocumentDetailView: View {
    @ObservedObject var dataManager: DataManager
    let doc: PaperlessDocument; let onSave: (Int,String,Date,Int?,Int?,Int?,[Int])->Void; let onDelete: (Int)->Void
    @State private var mode: Int = 0; @State private var pdfData: Data? = nil; @State private var isLoaded = false; @State private var showShareSheet = false; @State private var showEdit = false
    
    var body: some View {
        VStack {
            Picker("Modus", selection: $mode) { Text("PDF").tag(0); Text("Text").tag(1) }.pickerStyle(.segmented).padding(.horizontal)
            if isLoaded {
                if mode == 0 { if let data = pdfData { PDFKitView(data: data) } else { Text("PDF konnte nicht geladen werden").foregroundColor(.gray) } }
                else { ScrollView { Text(doc.content ?? "Kein Text verfügbar.").padding().textSelection(.enabled) } }
            } else { ProgressView("Lade Dokument...") }
        }
        .navigationTitle(doc.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { showShareSheet = true }) { Image(systemName: "square.and.arrow.up") }
                    Button(action: { showEdit = true }) { Text("Edit") }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) { if let d = pdfData, let url = saveTempFile(data: d, name: doc.title) { ShareSheet(items: [url]) } else { Text("Daten nicht bereit") } }
        .sheet(isPresented: $showEdit) { EditDocumentView(document: .constant(doc), dataManager: dataManager, allTags: dataManager.allTags, allCorrespondents: dataManager.allCorrespondents, allDocTypes: dataManager.allDocTypes, onSave: onSave, onCreateTag: createTag, onCreateCorr: createCorr, onCreateType: createType, onLoadNotes: {_,_ in}, onAddNote: {_,_,_ in}, onDeleteNote: {_,_ in}, onDelete: onDelete) }
        .onAppear { loadContent() }
    }
    
    func createTag(_ name: String, _ comp: @escaping (Int)->Void) {
        if let url = dataManager.makeURL("tags/") {
            dataManager.jsonRequest(url, "POST", ["name": name, "color": "#ff0000", "matching_algorithm": 0, "is_insensitive": true]) { id in if let id = id { comp(id) } }
        }
    }
    func createCorr(_ name: String, _ comp: @escaping (Int)->Void) {
        if let url = dataManager.makeURL("correspondents/") {
            dataManager.jsonRequest(url, "POST", ["name": name, "matching_algorithm": 0, "is_insensitive": true]) { id in if let id = id { comp(id) } }
        }
    }
    func createType(_ name: String, _ comp: @escaping (Int)->Void) {
        if let url = dataManager.makeURL("document_types/") {
            dataManager.jsonRequest(url, "POST", ["name": name, "matching_algorithm": 0, "is_insensitive": true]) { id in if let id = id { comp(id) } }
        }
    }
    
    func loadContent(force: Bool = false) {
        if isLoaded && !force { return }
        if dataManager.fileExists(docId: doc.id) {
            if let d = try? Data(contentsOf: dataManager.getLocalFileUrl(for: doc.id)) { self.pdfData = d; self.isLoaded = true; return }
        }
        if !dataManager.isDemoMode, let url = dataManager.makeURL("documents/\(doc.id)/download/") {
            var req = URLRequest(url: url); let auth = "\(dataManager.username):\(dataManager.password)".data(using: .utf8)?.base64EncodedString() ?? ""; req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: req) { d, _, _ in DispatchQueue.main.async { if let d = d { self.pdfData = d; try? d.write(to: dataManager.getLocalFileUrl(for: doc.id)) }; self.isLoaded = true } }.resume()
        } else { self.isLoaded = true }
    }
    func saveTempFile(data: Data, name: String) -> URL? {
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(name.hasSuffix(".pdf") ? name : "\(name).pdf")
        try? data.write(to: temp); return temp
    }
}

// MARK: - 7. EDIT VIEW
struct EditDocumentView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var document: PaperlessDocument?; var dataManager: DataManager?
    let allTags: [Tag]; let allCorrespondents: [Correspondent]; let allDocTypes: [DocumentType]
    let onSave: (Int, String, Date, Int?, Int?, Int?, [Int]) -> Void; let onCreateTag: (String, @escaping (Int)->Void)->Void; let onCreateCorr: (String, @escaping (Int)->Void)->Void; let onCreateType: (String, @escaping (Int)->Void)->Void; let onLoadNotes: (Int, @escaping ([DocNote])->Void)->Void; let onAddNote: (Int, String, @escaping ()->Void)->Void; let onDeleteNote: (Int, @escaping ()->Void)->Void; let onDelete: (Int) -> Void
    @State private var title=""; @State private var date=Date(); @State private var corr:Int?; @State private var type:Int?; @State private var asn=""; @State private var tags:Set<Int>=[]; @State private var showDeleteConfirm = false
    @State private var isAnalyzing = false; @State private var analysisResult = ""
    @State private var showNewTagAlert = false; @State private var newTagName = ""
    @State private var showNewCorrAlert = false; @State private var newCorrName = ""
    @State private var showNewTypeAlert = false; @State private var newTypeName = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Aktionen") {
                    Button(action: runRetrofitAI) {
                        HStack { Spacer(); if isAnalyzing { ProgressView().padding(.trailing, 5) }; Image(systemName: "wand.and.stars"); Text(isAnalyzing ? "Analysiere..." : "Automatisch ausfüllen (Retrofit)"); Spacer() }
                    }.buttonStyle(.borderedProminent).disabled(isAnalyzing)
                    if !analysisResult.isEmpty { Text(analysisResult).font(.caption).foregroundColor(.purple) }
                }
                Section("Infos") { TextField("Titel", text: $title); DatePicker("Datum", selection: $date, displayedComponents: .date); TextField("ASN", text: $asn).keyboardType(.numberPad) }
                Section(header: HStack { Text("Korrespondent"); Spacer(); Button { newCorrName = ""; showNewCorrAlert = true } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless) }) {
                    Picker("Wählen", selection: $corr) { Text("-").tag(Int?.none); ForEach(allCorrespondents) { c in Text(c.name).tag(c.id as Int?) } }
                }
                Section(header: HStack { Text("Dokumententyp"); Spacer(); Button { newTypeName = ""; showNewTypeAlert = true } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless) }) {
                    Picker("Wählen", selection: $type) { Text("-").tag(Int?.none); ForEach(allDocTypes) { t in Text(t.name).tag(t.id as Int?) } }
                }
                Section(header: HStack { Text("Tags"); Spacer(); Button { newTagName = ""; showNewTagAlert = true } label: { Image(systemName: "plus.circle") }.buttonStyle(.borderless) }) {
                    ForEach(allTags) { t in HStack { Text(t.name); Spacer(); if tags.contains(t.id) { Image(systemName: "checkmark") } }.contentShape(Rectangle()).onTapGesture { if tags.contains(t.id) { tags.remove(t.id) } else { tags.insert(t.id) } } }
                }
                Section { Button(role: .destructive) { showDeleteConfirm = true } label: { Text("Löschen") } }
            }
            .navigationTitle("Bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbruch") { document = nil; dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Speichern") { if let d = document { onSave(d.id, title, date, corr, type, Int(asn), Array(tags)) }; document = nil; dismiss() } }
            }
            .alert("Löschen?", isPresented: $showDeleteConfirm) { Button("Löschen", role: .destructive) { if let d = document { onDelete(d.id) }; document = nil; dismiss() }; Button("Abbrechen", role: .cancel) {} }
            .alert("Neuer Tag", isPresented: $showNewTagAlert) { TextField("Name", text: $newTagName); Button("OK") { onCreateTag(newTagName) { id in self.tags.insert(id) } } }
            .alert("Neuer Korrespondent", isPresented: $showNewCorrAlert) { TextField("Name", text: $newCorrName); Button("OK") { onCreateCorr(newCorrName) { id in self.corr = id } } }
            .alert("Neuer Typ", isPresented: $showNewTypeAlert) { TextField("Name", text: $newTypeName); Button("OK") { onCreateType(newTypeName) { id in self.type = id } } }
            .onAppear {
                if let d = document {
                    title = d.title; tags = Set(d.tags); corr = d.correspondent; type = d.document_type
                    if let a = d.archive_serial_number { asn = "\(a)" }
                    if let dateFromDoc = ISO8601DateFormatter().date(from: d.created) { date = dateFromDoc }
                    else { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; if let d = f.date(from: String(d.created.prefix(10))) { date = d } }
                }
            }
        }
    }
    
    // FIX: Optional Chaining für DataManager
    func runRetrofitAI() {
        guard let doc = document, let dm = dataManager else { return }
        if !dm.fileExists(docId: doc.id) { self.analysisResult = "Datei nicht gefunden. Bitte erst herunterladen."; return }
        isAnalyzing = true; analysisResult = "Lese Datei..."
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: dm.getLocalFileUrl(for: doc.id)), let pdf = PDFDocument(data: data), let page = pdf.page(at: 0), let cgImage = page.thumbnail(of: CGSize(width: 1000, height: 1000), for: .mediaBox).cgImage else { DispatchQueue.main.async { self.isAnalyzing = false; self.analysisResult = "Fehler beim Lesen" }; return }
            let request = VNRecognizeTextRequest { req, err in
                defer { DispatchQueue.main.async { self.isAnalyzing = false } }
                guard let obs = req.results as? [VNRecognizedTextObservation] else { return }
                let fullText = obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
                DispatchQueue.main.async {
                    var foundInfo = [String](); var titleParts = [String]()
                    for c in allCorrespondents { if fullText.contains(c.name.lowercased()) { self.corr = c.id; foundInfo.append("Absender: \(c.name)"); titleParts.append(c.name); break } }
                    for dt in allDocTypes { if fullText.contains(dt.name.lowercased()) { self.type = dt.id; foundInfo.append("Typ: \(dt.name)"); titleParts.append(dt.name); break } }
                    var tagFound = false
                    for t in allTags { if fullText.contains(t.name.lowercased()) { self.tags.insert(t.id); foundInfo.append("Tag: \(t.name)"); if !tagFound { titleParts.append(t.name); tagFound = true } } }
                    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
                        let matches = detector.matches(in: fullText, options: [], range: NSRange(location: 0, length: fullText.utf16.count))
                        if let match = matches.first, let detectedDate = match.date { self.date = detectedDate; foundInfo.append("Datum: \(ISO8601DateFormatter().string(from: detectedDate).prefix(10))") }
                    }
                    if !titleParts.isEmpty { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; let dateStr = f.string(from: self.date); self.title = titleParts.joined(separator: " - ") + " - " + dateStr }
                    self.analysisResult = foundInfo.isEmpty ? "Nichts gefunden." : "Gefunden: " + foundInfo.joined(separator: ", ")
                }
            }
            request.recognitionLevel = .accurate; try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }
}

// MARK: - 8. MAIN DOC VIEW (BULK EDIT)
struct MainDocView: View {
    @ObservedObject var dataManager: DataManager; let onLogout: () -> Void; @AppStorage("sortOrder") private var sortOrder = "-created"
    @AppStorage("layoutStyle") private var layoutStyle = "grid"
    @State private var searchText = ""; @State private var filterTag: Int? = nil; @State private var filterCorr: Int? = nil; @State private var filterType: Int? = nil
    @State private var showSettings = false; @State private var showScanner = false; @State private var showFilePicker = false; @State private var showPhotoPicker = false
    @State private var uploadQueueItem: UploadContainer? = nil; @State private var documentToEdit: PaperlessDocument? = nil
    
    @State private var isSelectionMode = false
    @State private var selectedDocIDs = Set<Int>()
    @State private var showBulkTagSheet = false
    @State private var bulkTagMode = 0
    
    var filteredDocs: [PaperlessDocument] {
        let f = dataManager.documents.filter { doc in
            let match = searchText.isEmpty || doc.title.localizedCaseInsensitiveContains(searchText) || (doc.content?.localizedCaseInsensitiveContains(searchText) ?? false)
            return (filterTag==nil || doc.tags.contains(filterTag!)) && (filterCorr==nil || doc.correspondent==filterCorr) && (filterType==nil || doc.document_type==filterType) && match
        }
        switch sortOrder {
        case "created": return f.sorted{$0.created<$1.created}; case "-created": return f.sorted{$0.created>$1.created}
        case "added": return f.sorted{($0.added ?? "")<($1.added ?? "")}; case "-added": return f.sorted{($0.added ?? "")>($1.added ?? "")}
        case "title": return f.sorted{$0.title<$1.title}; case "-title": return f.sorted{$0.title>$1.title}
        default: return f.sorted{$0.created>$1.created}
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if dataManager.isOffline || !dataManager.pendingUploads.isEmpty { HStack{if dataManager.isOffline{Label("Offline",systemImage:"wifi.slash").foregroundColor(.red)};Spacer();if !dataManager.pendingUploads.isEmpty{Label("\(dataManager.pendingUploads.count) Wartend",systemImage:"clock").foregroundColor(.orange)}}.padding(8).background(Color(.systemGray6)) }
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 10) { filterBtn("tag", "Tags", $filterTag, dataManager.allTags.map{($0.id,$0.name)}); filterBtn("doc", "Typ", $filterType, dataManager.allDocTypes.map{($0.id,$0.name)}); filterBtn("person", "Absender", $filterCorr, dataManager.allCorrespondents.map{($0.id,$0.name)}); if filterTag != nil || filterType != nil || filterCorr != nil { Button{filterTag=nil;filterType=nil;filterCorr=nil}label:{Image(systemName:"xmark.circle").foregroundColor(.secondary)} } }.padding() }.background(Color(.systemBackground)); Divider()
                    
                    if layoutStyle == "grid" {
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                                ForEach(filteredDocs) { doc in
                                    if isSelectionMode {
                                        DocumentCard(doc: doc, serverBase: dataManager.serverUrl, username: dataManager.username, password: dataManager.password, allTags: dataManager.allTags, allCorrespondents: dataManager.allCorrespondents, allDocTypes: dataManager.allDocTypes, isSelected: selectedDocIDs.contains(doc.id))
                                            .onTapGesture {
                                                if selectedDocIDs.contains(doc.id) { selectedDocIDs.remove(doc.id) } else { selectedDocIDs.insert(doc.id) }
                                            }
                                    } else {
                                        // FIX: Klicksicherste Grid-Methode (Link um die Card)
                                        NavigationLink(destination: DocumentDetailView(dataManager: dataManager, doc: doc, onSave: updateDocument, onDelete: deleteDocument)) {
                                            DocumentCard(doc: doc, serverBase: dataManager.serverUrl, username: dataManager.username, password: dataManager.password, allTags: dataManager.allTags, allCorrespondents: dataManager.allCorrespondents, allDocTypes: dataManager.allDocTypes)
                                                .contentShape(Rectangle()) // Klicks auch auf leere Flächen
                                        }
                                        .buttonStyle(PlainButtonStyle()) // Verhindert das "Grid-Highlight-Chaos"
                                        .contextMenu { Button { documentToEdit = doc } label: { Label("Bearbeiten", systemImage: "pencil") } }
                                    }
                                }
                            }.padding()
                        }
                        .refreshable { if !dataManager.isDemoMode { dataManager.sync() } }
                    } else {
                        List {
                            ForEach(filteredDocs) { doc in
                                NavigationLink(destination: DocumentDetailView(dataManager: dataManager, doc: doc, onSave: updateDocument, onDelete: deleteDocument)) {
                                    DocumentRow(doc: doc, allTags: dataManager.allTags, allCorrespondents: dataManager.allCorrespondents, allDocTypes: dataManager.allDocTypes)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { deleteDocument(id: doc.id) } label: { Label("Löschen", systemImage: "trash") }
                                    Button { documentToEdit = doc } label: { Label("Edit", systemImage: "pencil") }.tint(.orange)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { if !dataManager.isDemoMode { dataManager.sync() } }
                    }
                }
                
                if isSelectionMode {
                    VStack { Divider(); HStack { Button(action: { showBulkTagSheet = true }) { VStack { Image(systemName: "tag"); Text("Tags") } }; Spacer(); Text("\(selectedDocIDs.count) ausgewählt").font(.headline); Spacer(); Button(role: .destructive, action: bulkDelete) { VStack { Image(systemName: "trash"); Text("Löschen") } }.disabled(selectedDocIDs.isEmpty) }.padding().background(Color(.systemBackground)) }.transition(.move(edge: .bottom))
                }
                
                if let msg = dataManager.uploadSuccessMessage { HStack { Image(systemName: "checkmark.circle.fill"); Text(msg).font(.subheadline).bold() }.padding().background(Color.green.opacity(0.9)).foregroundColor(.white).cornerRadius(20).padding(.bottom, isSelectionMode ? 80 : 20).transition(.move(edge: .bottom).combined(with: .opacity)).animation(.spring(), value: msg) }
            }
            .navigationTitle(dataManager.isDemoMode ? "Demo Modus" : "Bibliothek").searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { if !isSelectionMode { Menu { Button{showScanner=true}label:{Label("Scan", systemImage:"camera")}; Button{showPhotoPicker=true}label:{Label("Fotos", systemImage:"photo")}; Button{showFilePicker=true}label:{Label("Import", systemImage:"folder")} } label: { Image(systemName: "plus") } } }
                ToolbarItem(placement: .navigationBarTrailing) { HStack { if isSelectionMode { Button("Fertig") { isSelectionMode = false; selectedDocIDs.removeAll() } } else { Button(action: { layoutStyle = layoutStyle == "grid" ? "list" : "grid" }) { Image(systemName: layoutStyle == "grid" ? "list.bullet" : "square.grid.2x2") }; if layoutStyle == "grid" { Button(action: { isSelectionMode = true; selectedDocIDs.removeAll() }) { Text("Auswählen") } }; Menu{Picker("Sortierung", selection: $sortOrder){Text("Erstellt (Neu)").tag("-created");Text("Erstellt (Alt)").tag("created");Text("Upload (Neu)").tag("-added");Text("Upload (Alt)").tag("added");Text("Titel (A-Z)").tag("title");Text("Titel (Z-A)").tag("-title");Text("ASN (9-1)").tag("-asn");Text("ASN (1-9)").tag("asn")}}label:{Image(systemName: "arrow.up.arrow.down.circle")}; if dataManager.isSyncing{ProgressView().padding(.horizontal,5)}; Button{showSettings=true}label:{Image(systemName: "line.3.horizontal")} } } }
            }
            .sheet(isPresented: $showSettings) { SettingsView(dataManager: dataManager, isPresented: $showSettings, onLogout: onLogout) }
            .sheet(isPresented: $showBulkTagSheet) { NavigationView { List { Section { Picker("Aktion", selection: $bulkTagMode) { Text("Hinzufügen").tag(0); Text("Entfernen").tag(1) }.pickerStyle(.segmented) }; Section("Tags wählen") { ForEach(dataManager.allTags) { tag in Button(action: { applyBulkTag(tag.id, remove: bulkTagMode == 1) }) { HStack { Text(tag.name); Spacer(); Image(systemName: "chevron.right") } } } } }.navigationTitle("Tags bearbeiten").toolbar { Button("Schließen") { showBulkTagSheet = false } } } }
        }
        .navigationViewStyle(.stack)
        .fullScreenCover(isPresented: $showScanner) { ScannerView(isPresented: $showScanner) { d in self.uploadQueueItem = UploadContainer(data: d, filename: "Scan_\(Date().timeIntervalSince1970).pdf") } }
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.pdf, .image]) { r in if case .success(let u)=r { if u.startAccessingSecurityScopedResource(), let d=try? Data(contentsOf: u) { self.uploadQueueItem = UploadContainer(data: d, filename: u.lastPathComponent) }; u.stopAccessingSecurityScopedResource() } }
        .sheet(isPresented: $showPhotoPicker) { PhotoPicker(isPresented: $showPhotoPicker) { d in self.uploadQueueItem = UploadContainer(data: d, filename: "Photo_\(Date().timeIntervalSince1970).pdf") } }
        .sheet(item: $uploadQueueItem) { container in UploadDocumentView(container: container, allTags: dataManager.allTags, allCorrespondents: dataManager.allCorrespondents, allDocTypes: dataManager.allDocTypes, onUpload: { d, f, t, c, co, ty, ta, completion in if !dataManager.isDemoMode { dataManager.addToQueue(data: d, filename: f, title: t, created: c, corr: co, type: ty, tags: ta) }; completion(); if !dataManager.isDemoMode { DispatchQueue.global().async{dataManager.sync()} } }, onCancel: { uploadQueueItem = nil }, onCreateTag: createTag, onCreateCorr: createCorr, onCreateType: createType) }
        .sheet(item: $documentToEdit) { doc in EditDocumentView(document: $documentToEdit, dataManager: dataManager, allTags: dataManager.allTags, allCorrespondents: dataManager.allCorrespondents, allDocTypes: dataManager.allDocTypes, onSave: updateDocument, onCreateTag: createTag, onCreateCorr: createCorr, onCreateType: createType, onLoadNotes: fetchNotes, onAddNote: postNote, onDeleteNote: deleteNote, onDelete: deleteDocument) }
    }
    
    func bulkDelete() { for id in selectedDocIDs { deleteDocument(id: id) }; isSelectionMode = false; selectedDocIDs.removeAll() }
    func applyBulkTag(_ tagId: Int, remove: Bool) { for docId in selectedDocIDs { if let index = dataManager.documents.firstIndex(where: {$0.id == docId}) { var currentTags = dataManager.documents[index].tags; if remove { currentTags.removeAll(where: { $0 == tagId }) } else if !currentTags.contains(tagId) { currentTags.append(tagId) }; updateDocument(id: docId, title: dataManager.documents[index].title, date: ISO8601DateFormatter().date(from: dataManager.documents[index].created) ?? Date(), corr: dataManager.documents[index].correspondent, type: dataManager.documents[index].document_type, asn: dataManager.documents[index].archive_serial_number, tags: currentTags) } }; showBulkTagSheet = false; isSelectionMode = false }
    func filterBtn(_ icon:String,_ title:String,_ sel:Binding<Int?>,_ items:[(Int,String)])->some View{ Menu{Button("Alle"){sel.wrappedValue=nil};ForEach(items,id:\.0){i in Button(i.1){sel.wrappedValue=i.0}}}label:{HStack{Image(systemName:icon);Text(sel.wrappedValue==nil ? title:items.first(where:{$0.0==sel.wrappedValue})?.1 ?? title).lineLimit(1)}.padding(8).background(sel.wrappedValue==nil ? Color(.secondarySystemBackground):Color.blue).foregroundColor(sel.wrappedValue==nil ? .primary:.white).cornerRadius(10)} }
    
    // Wrapper
    func createTag(_ name: String, _ completion: @escaping (Int) -> Void) { if let url = dataManager.makeURL("tags/") { dataManager.jsonRequest(url, "POST", ["name": name, "color": "#ff0000", "matching_algorithm": 0, "is_insensitive": true]) { id in if let id = id { completion(id) } } } }
    func createCorr(_ name: String, _ completion: @escaping (Int) -> Void) { if let url = dataManager.makeURL("correspondents/") { dataManager.jsonRequest(url, "POST", ["name": name, "matching_algorithm": 0, "is_insensitive": true]) { id in if let id = id { completion(id) } } } }
    func createType(_ name: String, _ completion: @escaping (Int) -> Void) { if let url = dataManager.makeURL("document_types/") { dataManager.jsonRequest(url, "POST", ["name": name, "matching_algorithm": 0, "is_insensitive": true]) { id in if let id = id { completion(id) } } } }
    
    func updateDocument(id: Int, title: String, date: Date, corr: Int?, type: Int?, asn: Int?, tags: [Int]) { guard let url = dataManager.makeURL("documents/\(id)/") else { return }; let dateStr = ISO8601DateFormatter().string(from: date); var body: [String: Any] = ["title": title, "created": dateStr, "tags": tags]; if let c = corr { body["correspondent"] = c }; if let t = type { body["document_type"] = t }; if let a = asn { body["archive_serial_number"] = a }; dataManager.jsonRequest(url, "PATCH", body) { _ in } }
    func deleteDocument(id: Int) { guard let url = dataManager.makeURL("documents/\(id)/") else { return }; var req = URLRequest(url: url); req.httpMethod = "DELETE"; let auth = "\(dataManager.username):\(dataManager.password)".data(using: .utf8)?.base64EncodedString() ?? ""; req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization"); URLSession.shared.dataTask(with: req) { _, _, _ in DispatchQueue.main.async { if !dataManager.isDemoMode { dataManager.sync() } } }.resume() }
    func fetchNotes(_ id: Int, _ comp: @escaping ([DocNote]) -> Void) { if dataManager.isDemoMode { comp([]); return }; guard let url = dataManager.makeURL("documents/\(id)/notes/") else { return }; var req = URLRequest(url: url); let auth = "\(dataManager.username):\(dataManager.password)".data(using: .utf8)?.base64EncodedString() ?? ""; req.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization"); URLSession.shared.dataTask(with: req) { d, _, _ in if let d = d, let n = try? JSONDecoder().decode([DocNote].self, from: d) { DispatchQueue.main.async { comp(n) } } else { DispatchQueue.main.async { comp([]) } } }.resume() }
    func postNote(_ id: Int, _ txt: String, _ comp: @escaping () -> Void) { guard let url = dataManager.makeURL("documents/\(id)/notes/") else { return }; dataManager.jsonRequest(url, "POST", ["note": txt]) { _ in comp() } }
    func deleteNote(_ id: Int, _ comp: @escaping () -> Void) { comp() }
}

// MARK: - 9. ROOT VIEW
struct ContentView: View {
    @StateObject private var dataManager = DataManager()
    @AppStorage("useFaceID") private var useFaceID = false
    @AppStorage("appearanceMode") private var appearanceMode = 0
    @State private var appState: AppState = .welcome
    enum AppState { case loading, welcome, login, main }
    
    var body: some View {
        Group {
            switch appState {
            case .loading: Color.black.ignoresSafeArea()
            case .welcome: WelcomeView(dataManager: dataManager, onStart: checkLogin, onReset: resetApp)
            case .login: LoginView(dataManager: dataManager, useFaceID: $useFaceID, onConnect: { dataManager.isDemoMode = false; appState = .main; dataManager.sync() }, onDemo: { dataManager.setupDemoData(); appState = .main })
            case .main: MainDocView(dataManager: dataManager, onLogout: { resetApp() })
            }
        }
        .preferredColorScheme(appearanceMode == 1 ? .light : (appearanceMode == 2 ? .dark : nil))
        .onAppear {
            if !dataManager.serverUrl.isEmpty && !dataManager.username.isEmpty && !dataManager.password.isEmpty {
                checkLogin()
            }
        }
        .onOpenURL { url in
            if appState != .main {
                // Wenn wir noch nicht eingeloggt sind, kurz warten oder zum Login zwingen, aber hier vereinfacht:
                // Wir speichern es trotzdem in die Warteschlange
            }
            dataManager.handleIncomingFile(url: url)
        }
    }
    
    func checkLogin() {
        if !dataManager.serverUrl.isEmpty && !dataManager.username.isEmpty && !dataManager.password.isEmpty {
            if useFaceID { authenticate() } else { appState = .main; if !dataManager.isDemoMode { dataManager.sync() } }
        } else { appState = .login }
    }
    
    func resetApp() { dataManager.serverUrl = ""; dataManager.username = ""; dataManager.password = ""; dataManager.isDemoMode = false; useFaceID = false; appState = .welcome }
    
    func authenticate() {
        let context = LAContext(); var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Anmelden") { success, _ in
                DispatchQueue.main.async { if success { appState = .main; if !dataManager.isDemoMode { dataManager.sync() } } else { appState = .login } }
            }
        } else { appState = .main; if !dataManager.isDemoMode { dataManager.sync() } }
    }
}

// MARK: - 10. ENTRY VIEWS
struct WelcomeView: View {
    @ObservedObject var dataManager: DataManager; let onStart: () -> Void; let onReset: () -> Void
    var body: some View { VStack(spacing: 20) { Spacer(); Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 80)).foregroundColor(.blue); Text("Paperless TeDi").font(.system(size: 40, weight: .bold, design: .rounded)); Text("v\(appVersion)").font(.subheadline).foregroundColor(.gray); Button("Starten", action: onStart).buttonStyle(.borderedProminent).controlSize(.large); Button("Reset", action: onReset).tint(.red).padding(.top, 10); Spacer() } }
}
struct LoginView: View {
    @ObservedObject var dataManager: DataManager; @Binding var useFaceID: Bool; let onConnect: () -> Void; let onDemo: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Text("Setup").font(.largeTitle).bold()
            TextField("Server (z.B. 192.168.1.50:8000)", text: $dataManager.serverUrl).textFieldStyle(.roundedBorder).autocapitalization(.none).disableAutocorrection(true)
            TextField("User", text: $dataManager.username).textFieldStyle(.roundedBorder).autocapitalization(.none)
            SecureField("Passwort", text: $dataManager.password).textFieldStyle(.roundedBorder)
            Toggle("FaceID nutzen", isOn: $useFaceID)
            Button("Verbinden", action: onConnect).buttonStyle(.borderedProminent).padding(.top, 10)
            Divider().padding(.vertical)
            Button("Demo Modus testen", action: onDemo).foregroundColor(.orange)
        }.padding(40)
    }
}

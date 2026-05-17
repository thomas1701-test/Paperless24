import Foundation

struct PendingUpload: Identifiable, Codable {
    var id: UUID = UUID()
    let data: Data
    let filename: String
    let title: String
    let created: Date
    let correspondent: Int?
    let documentType: Int?
    let tags: [Int]
}

struct PendingEdit: Identifiable, Codable {
    var id: UUID = UUID()
    let docId: Int
    let title: String
    let created: String
    let correspondent: Int?
    let documentType: Int?
    let archiveSerialNumber: Int?
    let tags: [Int]
}

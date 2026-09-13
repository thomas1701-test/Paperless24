import Testing
import Foundation
@testable import Paperless24

/// Der Archivindex liegt binär auf der Platte (P3).
///
/// Bis 2.2.0 JSON: 512 Zahlen je Dokument als Text, bei 5.000 Dokumenten gut 50 MB — und beim
/// Vollaufbau nach jeder Seite komplett neu geschrieben.
struct ArchiveIndexTests {

    @Test func binaerformatRundlauf() {
        let entries: [Int: [Float]] = [
            1: [0.5, -0.25, 1],
            42: [0, 0.125, -1],
        ]
        let data = ArchiveIndex.encode(entries)
        #expect(data.count == 12 + 2 * (8 + 3 * 4))
        #expect(ArchiveIndex.decode(data) == entries)
    }

    @Test func beschaedigteDateiWirdAbgelehnt() {
        let data = ArchiveIndex.encode([7: [1, 2, 3]])
        #expect(ArchiveIndex.decode(data.dropLast(2)) == nil)
        #expect(ArchiveIndex.decode(Data()) == nil)
    }

    @Test func aehnlichkeit() {
        #expect(ArchiveIndex.cosine([1, 0], [1, 0]) == 1)
        #expect(ArchiveIndex.cosine([1, 0], [0, 1]) == 0)
        #expect(ArchiveIndex.cosine([1, 0], [1]) == -1)
    }
}

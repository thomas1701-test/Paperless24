import Testing
import Foundation
@testable import Paperless24

/// Geteilte Dateien überschreiben sich nicht mehr gegenseitig.
struct SharedImportsTests {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SharedImportsTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func zweiFreigabenKommenBeideAn() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(SharedImports.stage(Data("eins".utf8), filename: "a.pdf", in: dir))
        #expect(SharedImports.stage(Data("zwei".utf8), filename: "b.pdf", in: dir))

        let first = SharedImports.takeNext(in: dir)
        let second = SharedImports.takeNext(in: dir)
        #expect(first?.filename == "a.pdf")
        #expect(first?.data == Data("eins".utf8))
        #expect(second?.filename == "b.pdf")
        #expect(SharedImports.takeNext(in: dir) == nil)
    }
}

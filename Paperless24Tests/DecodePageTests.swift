import Testing
import Foundation
@testable import Paperless24

/// Dokumentseiten werden in einem Durchgang dekodiert (P6).
struct DecodePageTests {

    @Test func seiteMitWeiterUndGesamtzahl() throws {
        let json = #"{"count":312,"next":"https://x/api/documents/?page=2","previous":null,"results":[{"id":1,"title":"A","created":"2026-01-01","tags":[2,3],"content":"Text"},{"id":2,"title":"B","created":"2026-01-02","tags":[]}]}"#
        let page = try PaperlessAPI.decodePage(Data(json.utf8))
        #expect(page.documents.map(\.id) == [1, 2])
        #expect(page.documents.first?.tags == [2, 3])
        #expect(page.hasNext)
        #expect(page.totalCount == 312)
    }

    @Test func letzteSeiteUndKaputterEintrag() throws {
        // Ein Eintrag ohne `id` darf die übrigen nicht mitreißen.
        let json = #"{"count":2,"next":null,"results":[{"title":"ohne id"},{"id":9,"title":"C","created":"2026-01-03","tags":[]}]}"#
        let page = try PaperlessAPI.decodePage(Data(json.utf8))
        #expect(page.documents.map(\.id) == [9])
        #expect(!page.hasNext)
    }

    @Test func keinObjektIstEinFehler() {
        #expect(throws: APIError.self) { try PaperlessAPI.decodePage(Data("[]".utf8)) }
    }
}

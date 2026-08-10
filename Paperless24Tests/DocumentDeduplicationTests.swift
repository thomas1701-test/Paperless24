import Testing
import Foundation
@testable import Paperless24

/// SwiftUI identifiziert `ForEach`-Zeilen über die ID. Doppelte IDs führen dazu, dass
/// Tippen wirkungslos bleibt und Kontextmenüs an der falschen Zelle aufgehen.
/// Seit API-Version 9 liefert paperless-ngx `created` ohne Uhrzeit, wodurch Seitenabrufe
/// dasselbe Dokument mehrfach liefern können.
struct DocumentDeduplicationTests {

    private func doc(_ id: Int, created: String = "2026-07-28") -> Document {
        Document(id: id, title: "Doc \(id)", content: nil, created: created,
                 added: nil, correspondent: nil, documentType: nil,
                 archiveSerialNumber: nil, tags: [], notes: nil)
    }

    @Test func uniquedBehaeltErstesVorkommen() {
        let list = [doc(1), doc(2), doc(1), doc(3), doc(2)]
        #expect(list.uniquedByID().map(\.id) == [1, 2, 3])
    }

    @Test func uniquedLaesstSaubereListeUnveraendert() {
        let list = [doc(3), doc(1), doc(2)]
        #expect(list.uniquedByID().map(\.id) == [3, 1, 2])
    }

    @Test func appendUeberspringtBereitsVorhandeneIDs() {
        var list = [doc(1), doc(2)]
        // Überlappende zweite Seite, wie sie bei mehrdeutiger Sortierung entsteht.
        list.appendUniqueByID([doc(2), doc(3), doc(4)])
        #expect(list.map(\.id) == [1, 2, 3, 4])
    }

    @Test func appendEntferntAuchDublettenInnerhalbDerNeuenSeite() {
        var list = [doc(1)]
        list.appendUniqueByID([doc(2), doc(2), doc(3)])
        #expect(list.map(\.id) == [1, 2, 3])
    }

    @Test func appendMitLeererSeiteAendertNichts() {
        var list = [doc(1), doc(2)]
        list.appendUniqueByID([])
        #expect(list.map(\.id) == [1, 2])
    }
}

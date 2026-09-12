import Testing
import Foundation
@testable import Paperless24

struct SeriesDetectorTests {

    private let now = DateFormatting.parseAPIDate("2026-09-15")!

    private func doc(_ id: Int, _ created: String, corr: Int? = 1, type: Int? = 2) -> Document {
        let json = """
        {"id": \(id), "title": "Beleg \(id)", "created": "\(created)",
         "correspondent": \(corr.map(String.init) ?? "null"),
         "document_type": \(type.map(String.init) ?? "null"), "tags": []}
        """
        return try! JSONDecoder().decode(Document.self, from: Data(json.utf8))
    }

    private let names = [1: "Stadtwerke"]
    private let types = [2: "Rechnung"]

    // MARK: - Monatsrechnung

    @Test func zaehltMonateKorrekt() {
        #expect(SeriesDetector.monthsBetween("2026-01", "2026-04") == 3)
        #expect(SeriesDetector.monthsBetween("2025-11", "2026-02") == 3)
        #expect(SeriesDetector.monthsBetween("2026-05", "2026-05") == 0)
    }

    @Test func findetLueckenzwischenZweiMonaten() {
        let present: Set<String> = ["2026-01", "2026-02", "2026-05"]
        let missing = SeriesDetector.missingMonths(from: "2026-01", to: "2026-05", present: present)
        #expect(missing == ["2026-03", "2026-04"])
    }

    @Test func findetLueckeUeberJahreswechsel() {
        let present: Set<String> = ["2025-11", "2026-02"]
        let missing = SeriesDetector.missingMonths(from: "2025-11", to: "2026-02", present: present)
        #expect(missing == ["2025-12", "2026-01"])
    }

    // MARK: - Serien

    @Test func erkenntMonatlicheSerie() {
        let docs = (1...6).map { doc($0, String(format: "2026-%02d-05", $0)) }
        let series = SeriesDetector.detect(in: docs, names: names, typeNames: types, now: now)
        #expect(series.count == 1)
        #expect(series.first?.name == "Stadtwerke · Rechnung")
    }

    @Test func meldetFehlendenMonat() {
        // Januar bis Juni, aber der April fehlt.
        let months = [1, 2, 3, 5, 6, 7]
        let docs = months.enumerated().map { doc($0.offset + 1, String(format: "2026-%02d-05", $0.element)) }
        let series = SeriesDetector.detect(in: docs, names: names, typeNames: types, now: now)
        #expect(series.first?.missingMonths == ["2026-04"])
        #expect(series.first?.hasProblem == true)
    }

    @Test func meldetAusbleibendeFortsetzung() {
        // Serie endet im Mai, jetzt ist September — seit vier Monaten kommt nichts mehr.
        let docs = (1...5).map { doc($0, String(format: "2026-%02d-05", $0)) }
        let series = SeriesDetector.detect(in: docs, names: names, typeNames: types, now: now)
        #expect(series.first?.monthsSinceLast == 4)
        #expect(series.first?.hasProblem == true)
    }

    @Test func ignoriertZuWenigeBelege() {
        let docs = (1...3).map { doc($0, String(format: "2026-%02d-05", $0)) }
        #expect(SeriesDetector.detect(in: docs, names: names, typeNames: types, now: now).isEmpty)
    }

    @Test func ignoriertVerstreuteBelege() {
        // Fünf Belege über fünf Jahre sind keine monatliche Serie.
        let docs = [doc(1, "2021-03-05"), doc(2, "2022-07-05"), doc(3, "2023-01-05"),
                    doc(4, "2024-09-05"), doc(5, "2026-02-05")]
        #expect(SeriesDetector.detect(in: docs, names: names, typeNames: types, now: now).isEmpty)
    }

    @Test func ignoriertDokumenteOhneSender() {
        let docs = (1...6).map { doc($0, String(format: "2026-%02d-05", $0), corr: nil) }
        #expect(SeriesDetector.detect(in: docs, names: names, typeNames: types, now: now).isEmpty)
    }

    @Test func trenntSerienDesselbenSenders() {
        let rechnungen = (1...5).map { doc($0, String(format: "2026-%02d-05", $0), type: 2) }
        let auszuege = (6...10).map { doc($0, String(format: "2026-%02d-20", $0 - 5), type: 3) }
        let series = SeriesDetector.detect(in: rechnungen + auszuege, names: names,
                                           typeNames: types, now: now)
        #expect(series.count == 2)
    }
}

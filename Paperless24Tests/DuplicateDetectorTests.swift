import Testing
import Foundation
@testable import Paperless24

/// Die erste Dublettenprüfung fiel durch, weil Textähnlichkeit Serienbriefe nicht von
/// Dubletten trennt. Genau dieser Fall steht hier als Test.
struct DuplicateDetectorTests {

    private let rechnungJanuar = """
    Stadtwerke München. Rechnungsnummer: 2026-00123
    Abrechnungszeitraum Januar 2026. Rechnungsdatum 05.01.2026.
    Zu zahlender Betrag: 89,90 EUR. Zahlbar bis 20.01.2026.
    """

    private let rechnungFebruar = """
    Stadtwerke München. Rechnungsnummer: 2026-00456
    Abrechnungszeitraum Februar 2026. Rechnungsdatum 05.02.2026.
    Zu zahlender Betrag: 92,40 EUR. Zahlbar bis 20.02.2026.
    """

    // MARK: - Signatur

    @Test func liestBelegnummer() {
        let numbers = DuplicateDetector.referenceNumbers(in: rechnungJanuar)
        #expect(numbers.contains("2026-00123"))
    }

    @Test func ignoriertZahlenOhneSchluesselwort() {
        let numbers = DuplicateDetector.referenceNumbers(in: "Tel. 089 1234567, PLZ 80331")
        #expect(numbers.isEmpty)
    }

    @Test func liestBetragInCent() {
        #expect(DuplicateDetector.amounts(in: "Betrag: 89,90 EUR") == [8990])
        #expect(DuplicateDetector.amounts(in: "Total: 1.234,56 EUR") == [123456])
        #expect(DuplicateDetector.amounts(in: "Total: 1,234.56 USD") == [123456])
    }

    @Test func ignoriertZahlenOhneNachkommastellen() {
        // Rechnungsnummern und Jahreszahlen sind keine Beträge.
        #expect(DuplicateDetector.amounts(in: "Rechnung 2026 Nummer 4711").isEmpty)
    }

    // MARK: - Vergleich

    @Test func erkenntEchteDublette() {
        let candidate = DuplicateDetector.fingerprint(of: rechnungJanuar)
        let known = [(documentId: 1, fingerprint: DuplicateDetector.fingerprint(of: rechnungJanuar))]
        let matches = DuplicateDetector.matches(for: candidate, in: known)
        #expect(matches.count == 1)
        #expect(matches.first?.confidence == 1.0)
    }

    @Test func haeltSerienbriefeAuseinander() {
        // Der Fall, an dem die erste Fassung gescheitert ist: gleicher Absender, gleiches
        // Layout, fast gleicher Text — aber zwei verschiedene Rechnungen.
        let candidate = DuplicateDetector.fingerprint(of: rechnungFebruar)
        let known = [(documentId: 1, fingerprint: DuplicateDetector.fingerprint(of: rechnungJanuar))]
        #expect(DuplicateDetector.matches(for: candidate, in: known).isEmpty)
    }

    @Test func verlangtZweiMerkmale() {
        // Nur die Kundennummer stimmt überein — das tut sie auf jedem Brief des Absenders.
        let a = DuplicateDetector.fingerprint(of: "Kundennummer: 55501234. Betrag: 10,00 EUR. 01.03.2026")
        let b = DuplicateDetector.fingerprint(of: "Kundennummer: 55501234. Betrag: 77,50 EUR. 09.07.2026")
        #expect(DuplicateDetector.matches(for: a, in: [(documentId: 2, fingerprint: b)]).isEmpty)
    }

    @Test func leereSignaturTrifftNie() {
        let empty = DuplicateDetector.fingerprint(of: "Ein Brief ohne Zahlen.")
        let known = [(documentId: 1, fingerprint: DuplicateDetector.fingerprint(of: rechnungJanuar))]
        #expect(DuplicateDetector.matches(for: empty, in: known).isEmpty)
    }

    @Test func nenntDenGrund() {
        let candidate = DuplicateDetector.fingerprint(of: rechnungJanuar)
        let known = [(documentId: 1, fingerprint: DuplicateDetector.fingerprint(of: rechnungJanuar))]
        let reason = DuplicateDetector.matches(for: candidate, in: known).first?.reason ?? ""
        #expect(reason.contains("Belegnummer"))
        #expect(reason.contains("Betrag"))
    }
}

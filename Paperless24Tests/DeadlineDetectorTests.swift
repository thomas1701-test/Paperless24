import Testing
import Foundation
@testable import Paperless24

/// Der erste Fristen-Radar wurde verworfen, weil er „mittelgut" funktionierte. Genau das
/// prüfen diese Tests: Ein Treffer muss belegt sein, und alles Unbelegte muss durchfallen.
/// Die Fälle sind so formuliert, wie die Texte in echten Dokumenten stehen.
struct DeadlineDetectorTests {

    /// Fester Bezugspunkt, damit „in der Zukunft" reproduzierbar bleibt.
    private let now = DateFormatting.parseAPIDate("2026-09-01")!

    private func day(_ iso: String) -> Date { DateFormatting.parseAPIDate(iso)! }

    // MARK: - Erkennen

    @Test func erkenntZahlungsziel() {
        let text = "Rechnungsbetrag 249,90 EUR. Der Betrag ist zahlbar bis zum 30.09.2026 ohne Abzug."
        let deadline = DeadlineDetector.primaryDeadline(in: text, documentId: 1, now: now)
        #expect(deadline?.kind == .payment)
        #expect(deadline?.date == day("2026-09-30"))
    }

    @Test func erkenntKuendigungsfrist() {
        let text = "Die Kündigungsfrist endet am 15.11.2026. Danach verlängert sich der Vertrag."
        let deadline = DeadlineDetector.primaryDeadline(in: text, documentId: 2, now: now)
        #expect(deadline?.kind == .cancellation)
        #expect(deadline?.date == day("2026-11-15"))
    }

    @Test func erkenntGarantieMitAusgeschriebenemMonat() {
        let text = "Ihre Garantie endet am 3. Dezember 2027."
        let deadline = DeadlineDetector.primaryDeadline(in: text, documentId: 3, now: now)
        #expect(deadline?.kind == .warranty)
        #expect(deadline?.date == day("2027-12-03"))
    }

    @Test func erkenntIsoDatum() {
        let text = "Gültig bis 2027-01-31, danach ist eine Verlängerung nötig."
        let deadline = DeadlineDetector.primaryDeadline(in: text, documentId: 4, now: now)
        #expect(deadline?.kind == .expiry)
        #expect(deadline?.date == day("2027-01-31"))
    }

    @Test func erkenntZweistelligesJahr() {
        let text = "Zahlungsziel: 10.10.26"
        let deadline = DeadlineDetector.primaryDeadline(in: text, documentId: 5, now: now)
        #expect(deadline?.date == day("2026-10-10"))
    }

    // MARK: - Nicht erkennen (der wichtigere Teil)

    @Test func ignoriertDatumOhneSchluesselwort() {
        // Ein Rechnungsdatum ist keine Frist. Genau diese Verwechslung hat den ersten
        // Fristen-Radar unbrauchbar gemacht.
        let text = "Rechnungsdatum 01.09.2026, Lieferdatum 05.09.2026, Kundennummer 4711."
        #expect(DeadlineDetector.detect(in: text, documentId: 6, now: now).isEmpty)
    }

    @Test func ignoriertMehrdeutigenTrefferAlsVorschlag() {
        // „bitte bis" ist zu schwach für einen automatischen Vorschlag, taucht aber in der
        // vollständigen Liste auf.
        let text = "Bitte bis 20.09.2026 zurücksenden."
        #expect(DeadlineDetector.primaryDeadline(in: text, documentId: 7, now: now) == nil)
        #expect(!DeadlineDetector.detect(in: text, documentId: 7, now: now).isEmpty)
    }

    @Test func ignoriertUngueltigesDatum() {
        let text = "Zahlbar bis 31.02.2027."
        #expect(DeadlineDetector.detect(in: text, documentId: 8, now: now).isEmpty)
    }

    @Test func ignoriertLangeVergangenheit() {
        let text = "Zahlbar bis 30.09.2019."
        #expect(DeadlineDetector.detect(in: text, documentId: 9, now: now).isEmpty)
    }

    @Test func behaeltKuerzlichUeberfaellige() {
        // Eine Rechnung, die vorgestern fällig war, ist der interessanteste Fall überhaupt.
        let text = "Zahlbar bis 28.08.2026."
        let deadline = DeadlineDetector.primaryDeadline(in: text, documentId: 10, now: now)
        #expect(deadline != nil)
        #expect(deadline?.isOverdue == true)
    }

    @Test func ignoriertZahlenkolonnen() {
        let text = "Kundennummer 123.456.789, Rechnung 2026.09.4711, Betrag 1.234,56 EUR"
        #expect(DeadlineDetector.detect(in: text, documentId: 11, now: now).isEmpty)
    }

    @Test func ignoriertSchluesselwortWeitEntfernt() {
        // Das Schlüsselwort steht zwei Sätze vor dem Datum und gehört nicht dazu.
        let filler = String(repeating: "Weiterer Text ohne Bedeutung. ", count: 8)
        let text = "Zahlungsziel steht im Vertrag. \(filler) Erstellt am 10.10.2026."
        #expect(DeadlineDetector.detect(in: text, documentId: 12, now: now).isEmpty)
    }

    // MARK: - Auswahl bei mehreren Treffern

    @Test func waehltJeArtDieFruehereFrist() {
        let text = "Zahlbar bis 30.11.2026. Abweichend hiervon zahlbar bis 15.10.2026."
        let deadlines = DeadlineDetector.detect(in: text, documentId: 13, now: now)
        #expect(deadlines.count == 1)
        #expect(deadlines.first?.date == day("2026-10-15"))
    }

    @Test func trenntZahlungUndKuendigung() {
        let text = "Zahlbar bis 30.09.2026. Die Kündigungsfrist läuft bis zum 31.12.2026."
        let kinds = Set(DeadlineDetector.detect(in: text, documentId: 14, now: now).map(\.kind))
        #expect(kinds == [.payment, .cancellation])
    }

    @Test func liefertBelegstelleMit() {
        let text = "Der offene Betrag ist zahlbar bis zum 30.09.2026 auf das unten genannte Konto."
        let deadline = DeadlineDetector.primaryDeadline(in: text, documentId: 15, now: now)
        #expect(deadline?.evidence.contains("zahlbar bis") == true)
    }

    // MARK: - Vorlaufzeiten

    @Test func kuendigungHatLaengerenVorlauf() {
        #expect(Deadline.Kind.cancellation.reminderLeadDays > Deadline.Kind.payment.reminderLeadDays)
    }
}

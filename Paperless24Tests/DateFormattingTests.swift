import Testing
import Foundation
@testable import Paperless24

/// Deckt das Datumsformat der API ab.
///
/// Hintergrund: Der Bearbeiten-Dialog hat `created` mit einem Formatter gelesen, der
/// Millisekunden erzwingt. Der scheitert an `2026-08-10T00:00:00+02:00` und erst recht am
/// reinen Datum, das paperless-ngx ab API-Version 9 liefert — das Feld blieb dann auf „heute"
/// stehen und „Speichern" überschrieb das echte Erstelldatum.
struct DateFormattingTests {

    // MARK: - Lesen

    @Test("Zeitstempel mit Millisekunden")
    func parsesFractionalSeconds() throws {
        let date = try #require(DateFormatting.parseAPIDate("2026-08-10T12:30:00.123Z"))
        let parts = Calendar(identifier: .iso8601).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: date
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 10)
        #expect(parts.hour == 12)
    }

    @Test("Zeitstempel ohne Millisekunden — das übliche Format von ngx 2.x")
    func parsesInternetDateTimeWithoutFraction() throws {
        let date = try #require(DateFormatting.parseAPIDate("2026-08-10T00:00:00+02:00"))
        let parts = Calendar(identifier: .iso8601).dateComponents(
            in: TimeZone(secondsFromGMT: 2 * 3600)!, from: date
        )
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 10)
    }

    @Test("Reines Datum — das Format ab API-Version 9")
    func parsesDateOnly() throws {
        let date = try #require(DateFormatting.parseAPIDate("2026-08-10"))
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        #expect(parts.year == 2026)
        #expect(parts.month == 8)
        #expect(parts.day == 10)
    }

    @Test("Leerer oder unbrauchbarer Wert liefert nil")
    func rejectsGarbage() {
        #expect(DateFormatting.parseAPIDate("") == nil)
        #expect(DateFormatting.parseAPIDate("keinDatum") == nil)
    }

    // MARK: - Schreiben

    @Test("Formatiert in lokaler Zeit, ohne Sprung über die Tagesgrenze")
    func formatsInLocalTime() {
        // Mitternacht lokaler Zeit ist der Grenzfall: als UTC-Zeitstempel geschrieben, wäre
        // östlich von Greenwich der Vortag herausgekommen.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 10
        comps.hour = 0; comps.minute = 0
        let midnight = Calendar.current.date(from: comps)!

        #expect(DateFormatting.apiDate(midnight) == "2026-08-10")
    }

    @Test("Auch spät am Abend bleibt es derselbe Tag")
    func formatsLateEvening() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 8; comps.day = 10
        comps.hour = 23; comps.minute = 59
        let lateEvening = Calendar.current.date(from: comps)!

        #expect(DateFormatting.apiDate(lateEvening) == "2026-08-10")
    }

    // MARK: - Zusammenspiel

    @Test("Lesen und Zurückschreiben verändert das Datum nicht")
    func roundTripKeepsTheDay() throws {
        for raw in ["2026-08-10", "2026-08-10T00:00:00+02:00", "2026-08-10T12:30:00.123+02:00"] {
            let parsed = try #require(DateFormatting.parseAPIDate(raw), "\(raw) nicht lesbar")
            #expect(DateFormatting.apiDate(parsed) == "2026-08-10", "Rundlauf für \(raw)")
        }
    }

    @Test("Document.dateObject nutzt dieselbe Kette")
    func documentUsesSameParsing() throws {
        let doc = Document(
            id: 1, title: "Test", content: nil, created: "2026-08-10",
            added: nil, correspondent: nil, documentType: nil,
            archiveSerialNumber: nil, tags: [], notes: nil
        )
        let date = try #require(doc.dateObject)
        #expect(DateFormatting.apiDate(date) == "2026-08-10")
    }
}

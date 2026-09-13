import Testing
import Foundation
@testable import Paperless24

struct MultipartFilenameTests {
    @Test(arguments: [
        ("Rechnung \"Mai\".pdf", "Rechnung _Mai_.pdf"),
        ("zeile\r\numbruch.pdf", "zeile  umbruch.pdf"),
        ("normal.pdf", "normal.pdf"),
        ("", "Import.pdf"),
    ])
    func maskiert(raw: String, expected: String) {
        #expect(PaperlessAPI.multipartFilename(raw) == expected)
    }
}

struct UnreadableDateTests {
    /// Unlesbares Ausgangsdatum: „heute" aus dem Aufrufer ist keine Änderung.
    @Test func keinStillesHeute() {
        let doc = Document(id: 1, title: "X", content: nil, created: "", added: nil,
                           correspondent: nil, documentType: nil, archiveSerialNumber: nil,
                           tags: [], notes: nil)
        let changed = PendingEdit.changedFields(
            from: doc, title: "X", created: DateFormatting.apiDate(Date()), correspondent: nil,
            documentType: nil, archiveSerialNumber: nil, tags: [9], customFields: []
        )
        #expect(changed == [PendingEdit.Field.tags])
    }
}

@MainActor
struct TagHierarchyTests {
    private func tag(_ id: Int, _ name: String, parent: Int?) -> Paperless24.Tag {
        try! JSONDecoder().decode(Paperless24.Tag.self, from: Data(#"{"id":\#(id),"name":"\#(name)","parent":\#(parent.map(String.init) ?? "null")}"#.utf8))
    }

    @Test func baumMitVerwaistenUndZyklus() {
        let store = AppStore()
        store.allTags = [
            tag(1, "B-Wurzel", parent: nil), tag(2, "A-Wurzel", parent: nil),
            tag(3, "Kind", parent: 1), tag(4, "Waise", parent: 99),
            tag(5, "Zyklus1", parent: 6), tag(6, "Zyklus2", parent: 5),
        ]
        let flat = store.hierarchicalTags()
        #expect(flat.prefix(3).map(\.tag.id) == [2, 1, 3])
        #expect(flat.first { $0.tag.id == 3 }?.depth == 1)
        // Nichts geht verloren, nichts doppelt.
        #expect(Set(flat.map(\.tag.id)) == [1, 2, 3, 4, 5, 6])
        #expect(flat.count == 6)
    }
}

struct ReminderAlarmTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    @Test func vorlaufUmNeunUhr() {
        let alarm = RemindersService.alarmDate(dueDate: date(30, 0), leadDays: 3, now: date(12, 15), calendar: calendar)
        #expect(alarm == date(27, 9))
    }

    /// Nachmittags angelegt, Vorlauf schon erreicht: nicht 9 Uhr am selben Morgen, sondern gleich.
    @Test func nieInDerVergangenheit() {
        let now = date(12, 15)
        let alarm = RemindersService.alarmDate(dueDate: date(13, 0), leadDays: 3, now: now, calendar: calendar)
        #expect(alarm > now)
        #expect(alarm <= calendar.date(byAdding: .minute, value: 5, to: now)!)
    }
}

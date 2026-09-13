import Foundation
import EventKit

/// Legt Erinnerungen für bestätigte Fristen an.
///
/// Erinnerungen statt Kalendereinträge: Eine Frist ist eine Aufgabe („bis zum 30.09. bezahlen"),
/// kein Termin. In der Erinnerungen-App lässt sie sich abhaken, sie erscheint in „Heute" und
/// wandert nicht aus dem Blick, wenn der Tag vorbei ist. Die Berechtigung dafür ist in der
/// Info.plist schon beschrieben (`NSRemindersFullAccessUsageDescription`).
enum RemindersService {

    /// Wann die Erinnerung weckt: `leadDays` vor der Frist um 9 Uhr — aber nie in der Vergangenheit.
    ///
    /// Vorher wurde erst auf „frühestens in 5 Minuten" angehoben und *danach* auf 9 Uhr gesetzt.
    /// Nachmittags angelegt, landete der Alarm damit wieder auf 9 Uhr am selben Morgen — in der
    /// Vergangenheit, und er feuerte sofort oder gar nicht.
    static func alarmDate(dueDate: Date, leadDays: Int, now: Date = Date(),
                          calendar: Calendar = .current) -> Date {
        let lead = calendar.date(byAdding: .day, value: -leadDays, to: dueDate) ?? dueDate
        let atNine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: lead) ?? lead
        let earliest = calendar.date(byAdding: .minute, value: 5, to: now) ?? now
        return max(atNine, earliest)
    }

    private static let store = EKEventStore()

    enum Failure: LocalizedError {
        case denied
        case noList
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .denied:   return "Kein Zugriff auf Erinnerungen. In den iOS-Einstellungen erlauben."
            case .noList:   return "Keine Erinnerungsliste gefunden."
            case .saveFailed(let m): return "Erinnerung konnte nicht gespeichert werden: \(m)"
            }
        }
    }

    static func requestAccess() async -> Bool {
        if #available(iOS 17, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        }
        return await withCheckedContinuation { continuation in
            store.requestAccess(to: .reminder) { granted, _ in continuation.resume(returning: granted) }
        }
    }

    /// Erinnerung mit Fälligkeit anlegen. Der Vorlauf richtet sich nach der Art der Frist.
    static func addReminder(title: String, dueDate: Date, notes: String?,
                            leadDays: Int) async throws {
        guard await requestAccess() else { throw Failure.denied }
        guard let list = store.defaultCalendarForNewReminders() else { throw Failure.noList }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = notes

        let calendar = Calendar.current
        reminder.dueDateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate)

        // Die Erinnerung meldet sich mit Vorlauf: Eine Kündigungsfrist, von der man am
        // Stichtag erfährt, ist verstrichen.
        reminder.addAlarm(EKAlarm(absoluteDate: alarmDate(dueDate: dueDate, leadDays: leadDays)))

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw Failure.saveFailed(error.localizedDescription)
        }
    }
}

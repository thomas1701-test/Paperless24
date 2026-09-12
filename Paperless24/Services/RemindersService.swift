import Foundation
import EventKit

/// Legt Erinnerungen für bestätigte Fristen an.
///
/// Erinnerungen statt Kalendereinträge: Eine Frist ist eine Aufgabe („bis zum 30.09. bezahlen"),
/// kein Termin. In der Erinnerungen-App lässt sie sich abhaken, sie erscheint in „Heute" und
/// wandert nicht aus dem Blick, wenn der Tag vorbei ist. Die Berechtigung dafür ist in der
/// Info.plist schon beschrieben (`NSRemindersFullAccessUsageDescription`).
enum RemindersService {
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
        let alarmDate = calendar.date(byAdding: .day, value: -leadDays, to: dueDate) ?? dueDate
        // Nicht in der Vergangenheit wecken — sonst feuert der Alarm sofort oder gar nicht.
        let fireDate = max(alarmDate, calendar.date(byAdding: .minute, value: 5, to: Date()) ?? Date())
        reminder.addAlarm(EKAlarm(absoluteDate: calendar.date(
            bySettingHour: 9, minute: 0, second: 0, of: fireDate
        ) ?? fireDate))

        do {
            try store.save(reminder, commit: true)
        } catch {
            throw Failure.saveFailed(error.localizedDescription)
        }
    }
}

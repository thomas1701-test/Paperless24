import Foundation
import EventKit

/// Legt Erinnerungen für erkannte Fristen an.
enum EventKitService {
    static func addReminder(title: String, due: Date, notes: String?) async -> Bool {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else { return false }

        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = store.defaultCalendarForNewReminders()
        reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
        reminder.addAlarm(EKAlarm(absoluteDate: Calendar.current.startOfDay(for: due)))
        do {
            try store.save(reminder, commit: true)
            return true
        } catch {
            return false
        }
    }
}

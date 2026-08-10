import Foundation

/// Entscheidet, OB nach einer App-Store-Bewertung gefragt wird.
/// Reine, ohne StoreKit testbare Gating-Logik; State liegt lokal in UserDefaults.
/// Der eigentliche `requestReview`-Aufruf passiert in der View-Schicht (RootTabView).
/// `@MainActor`-isoliert wie `AppStore` — alle Aufrufe erfolgen aus dem UI-Fluss;
/// schützt das `didAttemptThisSession`-Flag vor Datenrennen.
@MainActor
final class ReviewRequestService {
    static let shared = ReviewRequestService()

    // Justierbare Schwellen
    private let minLaunchDays = 3
    /// Apple deckelt selbst auf 3 Dialoge / 365 Tage. Unser eigener Cooldown muss
    /// deshalb nicht strenger sein als ~1/3 Jahr; 35 Tage lassen den System-Deckel
    /// die Obergrenze setzen, statt sie zusätzlich zu unterbieten.
    private let minDaysBetweenPrompts = 35
    /// Mindestens so viele positive Momente, bevor überhaupt gefragt wird.
    /// Verhindert, dass ein brandneuer Nutzer nach dem allerersten Upload gefragt wird.
    private let minPositiveEvents = 3

    private let defaults: UserDefaults
    private var didAttemptThisSession = false

    // Intern (nicht private), damit Tests den persistierten Zustand direkt seeden können.
    enum Key {
        static let launchDays = "review.launchDays"
        static let lastPromptDate = "review.lastPromptDate"
        static let lastPromptVersion = "review.lastPromptVersion"
        static let positiveEvents = "review.positiveEvents"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Beim App-Start aufrufen: hält den heutigen Tag (yyyy-MM-dd) fest (dedupe).
    func registerLaunch(today: Date = Date()) {
        let key = Self.dayString(today)
        var days = defaults.stringArray(forKey: Key.launchDays) ?? []
        guard !days.contains(key) else { return }
        days.append(key)
        // Nur die jüngsten `minLaunchDays` behalten — für das Gating zählt nur,
        // ob die Schwelle erreicht ist; verhindert unbegrenztes Wachstum.
        if days.count > minLaunchDays { days = Array(days.suffix(minLaunchDays)) }
        defaults.set(days, forKey: Key.launchDays)
    }

    /// Zählt einen positiven Moment (Upload fertig, Bearbeitung gespeichert, …).
    /// Getrennt von `shouldRequestReview`, damit auch Events zählen, die das
    /// Gating gerade blockiert — der Zähler wächst über Sessions hinweg weiter.
    func registerPositiveEvent() {
        defaults.set(positiveEventCount + 1, forKey: Key.positiveEvents)
    }

    var positiveEventCount: Int { defaults.integer(forKey: Key.positiveEvents) }

    /// Reine Gating-Funktion — alle Regeln müssen erfüllt sein.
    func shouldRequestReview(now: Date = Date(),
                             version: String = AppConstants.appVersion) -> Bool {
        if didAttemptThisSession { return false }

        let days = defaults.stringArray(forKey: Key.launchDays) ?? []
        if days.count < minLaunchDays { return false }

        if positiveEventCount < minPositiveEvents { return false }

        if let last = defaults.object(forKey: Key.lastPromptDate) as? Date {
            let elapsedDays = now.timeIntervalSince(last) / 86_400
            if elapsedDays < Double(minDaysBetweenPrompts) { return false }
        }

        if defaults.string(forKey: Key.lastPromptVersion) == version { return false }

        return true
    }

    /// Nach einem ausgelösten Dialog aufrufen: markiert Versuch (Session + persistiert).
    func recordPrompt(now: Date = Date(),
                      version: String = AppConstants.appVersion) {
        didAttemptThisSession = true
        defaults.set(now, forKey: Key.lastPromptDate)
        defaults.set(version, forKey: Key.lastPromptVersion)
    }

    func appStoreWriteReviewURL() -> URL {
        URL(string: "https://apps.apple.com/app/id\(AppConstants.appStoreId)?action=write-review")!
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

    private static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }
}

import Testing
import Foundation
@testable import Paperless24

@MainActor
struct ReviewRequestServiceTests {

    /// Frische UserDefaults-Suite je Test, damit nichts überspringt.
    private func makeService() -> (ReviewRequestService, UserDefaults) {
        let suite = "review.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (ReviewRequestService(defaults: defaults), defaults)
    }

    @Test func neuerNutzerWirdNichtGefragt() {
        let (svc, _) = makeService()
        svc.registerLaunch(today: Date())
        #expect(svc.shouldRequestReview(now: Date(), version: "1.8.1") == false)
    }

    @Test func dreiStarttageNeueVersionLoest() {
        let (svc, _) = makeService()
        let cal = Calendar.current
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == true)
    }

    @Test func gleicherTagZaehltNurEinmal() {
        let (svc, _) = makeService()
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: base)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == false)
    }

    @Test func cooldownBlockiert() {
        let (svc, defaults) = makeService()
        let cal = Calendar.current
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        // Direkt seeden (nicht via recordPrompt, das das Session-Flag setzen würde):
        // vor 10 Tagen gefragt, andere Version -> Cooldown greift isoliert.
        defaults.set(cal.date(byAdding: .day, value: -10, to: base)!,
                     forKey: ReviewRequestService.Key.lastPromptDate)
        defaults.set("1.0.0", forKey: ReviewRequestService.Key.lastPromptVersion)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == false)
    }

    @Test func gleicheVersionNurEinmal() {
        let (svc, defaults) = makeService()
        let cal = Calendar.current
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        // Cooldown lange her (200 Tage), aber gleiche Version -> Versions-Sperre greift isoliert.
        defaults.set(cal.date(byAdding: .day, value: -200, to: base)!,
                     forKey: ReviewRequestService.Key.lastPromptDate)
        defaults.set("1.8.1", forKey: ReviewRequestService.Key.lastPromptVersion)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == false)
    }

    @Test func keinErneutesFragenNachPrompt() {
        let (svc, _) = makeService()
        let cal = Calendar.current
        let base = Date()
        svc.registerLaunch(today: base)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == true)
        // Nach dem Prompt: nicht mehr (Session-Flag + Versions-Sperre).
        svc.recordPrompt(now: base, version: "1.8.1")
        #expect(svc.shouldRequestReview(now: base, version: "1.8.1") == false)
    }

    @Test func cooldownGrenzwert() {
        let cal = Calendar.current
        let base = Date()

        // Klar jenseits des Cooldowns (121 Tage) -> erlaubt.
        // (-121 statt exakt -120, damit DST-bedingte Sekunden-Differenzen den
        // Test nicht am Knife-Edge der Float-Division flaky machen.)
        let (svc1, defaults1) = makeService()
        svc1.registerLaunch(today: base)
        svc1.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc1.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        defaults1.set(cal.date(byAdding: .day, value: -121, to: base)!,
                      forKey: ReviewRequestService.Key.lastPromptDate)
        defaults1.set("1.0.0", forKey: ReviewRequestService.Key.lastPromptVersion)
        #expect(svc1.shouldRequestReview(now: base, version: "1.8.1") == true)

        // 119 Tage her -> blockiert.
        let (svc2, defaults2) = makeService()
        svc2.registerLaunch(today: base)
        svc2.registerLaunch(today: cal.date(byAdding: .day, value: -1, to: base)!)
        svc2.registerLaunch(today: cal.date(byAdding: .day, value: -2, to: base)!)
        defaults2.set(cal.date(byAdding: .day, value: -119, to: base)!,
                      forKey: ReviewRequestService.Key.lastPromptDate)
        defaults2.set("1.0.0", forKey: ReviewRequestService.Key.lastPromptVersion)
        #expect(svc2.shouldRequestReview(now: base, version: "1.8.1") == false)
    }

    @Test func schreibBewertungsURLKorrekt() {
        let (svc, _) = makeService()
        #expect(svc.appStoreWriteReviewURL().absoluteString
            == "https://apps.apple.com/app/id6770317210?action=write-review")
    }
}

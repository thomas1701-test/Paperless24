import Testing
import Foundation
@testable import Paperless24

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

    @Test func schreibBewertungsURLKorrekt() {
        let (svc, _) = makeService()
        #expect(svc.appStoreWriteReviewURL().absoluteString
            == "https://apps.apple.com/app/id6770317210?action=write-review")
    }
}

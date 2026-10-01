import Testing
import Foundation
@testable import LorisLabsKit

@MainActor
struct SmartReviewPromptManagerTests {

    private final class TestClock: @unchecked Sendable {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private func makeManager(
        config: SmartReviewPromptManager.Configuration = .init(),
        version: String = "1.0",
        clock: TestClock? = nil
    ) -> (SmartReviewPromptManager, UserDefaults) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let mgr = SmartReviewPromptManager(
            configuration: config,
            userDefaults: defaults,
            appVersion: version,
            bundleIdentifier: "com.test.app",
            now: { clock?.date ?? Date() }
        )
        return (mgr, defaults)
    }

    @Test func freshlyInstalledAppShouldNotPrompt() {
        let (mgr, _) = makeManager()
        #expect(!mgr.shouldPromptNow)
    }

    @Test func belowLaunchThresholdShouldNotPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0, minimumActiveDays: 1))
        for _ in 0..<3 { mgr.recordLaunch() }
        for _ in 0..<3 { mgr.recordSuccessMoment() }
        #expect(!mgr.shouldPromptNow)
    }

    @Test func belowSuccessMomentThresholdShouldNotPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0, minimumActiveDays: 1))
        for _ in 0..<5 { mgr.recordLaunch() }
        for _ in 0..<2 { mgr.recordSuccessMoment() }
        #expect(!mgr.shouldPromptNow)
    }

    @Test func pastErrorDoesNotFilterReviews() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0, errorBlackoutDays: 7, minimumActiveDays: 1))
        for _ in 0..<5 { mgr.recordLaunch() }
        for _ in 0..<3 { mgr.recordSuccessMoment() }
        mgr.recordError()
        #expect(mgr.shouldPromptNow)
    }

    @Test func activeFreeTrialDoesNotFilterReviews() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0, minimumActiveDays: 1))
        for _ in 0..<5 { mgr.recordLaunch() }
        for _ in 0..<3 { mgr.recordSuccessMoment() }
        mgr.recordTrialState(.trialActive)
        #expect(mgr.shouldPromptNow)
    }

    @Test func paidProUserMeetsCriteriaShouldPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0, minimumActiveDays: 1))
        for _ in 0..<5 { mgr.recordLaunch() }
        for _ in 0..<3 { mgr.recordSuccessMoment() }
        mgr.recordTrialState(.proPaid)
        #expect(mgr.shouldPromptNow)
    }

    @Test func freeUserMeetsCriteriaShouldPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0, minimumActiveDays: 1))
        for _ in 0..<5 { mgr.recordLaunch() }
        for _ in 0..<3 { mgr.recordSuccessMoment() }
        mgr.recordTrialState(.free)
        #expect(mgr.shouldPromptNow)
    }

    @Test func resetWipesAllState() {
        let (mgr, _) = makeManager()
        for _ in 0..<10 { mgr.recordLaunch() }
        for _ in 0..<10 { mgr.recordSuccessMoment() }
        mgr.recordError()
        mgr.resetAllState()
        #expect(!mgr.shouldPromptNow) // back to fresh-install state
    }

    @Test func repeatedSuccessesOnOneDayCountAsOneActiveDay() {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (mgr, _) = makeManager(
            config: .init(
                minimumSuccessMoments: 3,
                minimumDaysSinceInstall: 0,
                cooldownDays: 120,
                minimumActiveDays: 3
            ),
            clock: clock
        )
        for _ in 0..<5 { mgr.recordSuccessMoment() }
        #expect(!mgr.shouldPromptNow)

        clock.date.addTimeInterval(86_400)
        mgr.recordSuccessMoment()
        #expect(!mgr.shouldPromptNow)

        clock.date.addTimeInterval(86_400)
        mgr.recordSuccessMoment()
        #expect(mgr.shouldPromptNow)
    }

    @Test func cooldownUsesAttemptSemanticsAndInjectedClock() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TestClock(start)
        let (mgr, defaults) = makeManager(
            config: .init(
                minimumSuccessMoments: 1,
                minimumDaysSinceInstall: 0,
                cooldownDays: 120,
                minimumActiveDays: 1
            ),
            version: "2.0",
            clock: clock
        )
        mgr.recordSuccessMoment()
        defaults.set(start, forKey: "lorislabskit.review.lastPromptDate")
        defaults.set("1.0", forKey: "lorislabskit.review.promptedForVersion")

        clock.date = start.addingTimeInterval(119 * 86_400)
        #expect(!mgr.shouldPromptNow)
        clock.date = start.addingTimeInterval(120 * 86_400)
        #expect(mgr.shouldPromptNow)
    }

    @Test func interactionInProgressAlwaysBlocksAnEligibleAttempt() {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (mgr, _) = makeManager(
            config: .init(
                minimumSuccessMoments: 1,
                minimumDaysSinceInstall: 0,
                minimumActiveDays: 1
            ),
            clock: clock
        )
        mgr.recordSuccessMoment()
        #expect(mgr.shouldPromptNow)
        mgr.interactionInProgress = true
        #expect(!mgr.shouldPromptNow)
    }
}

@Suite struct LorisLabsAppTests {
    @Test func portfolioContainsLiveApps() {
        #expect(LorisLabsApp.portfolio.contains { $0.name == "Lumen for Frigate" })
        #expect(LorisLabsApp.portfolio.contains { $0.name == "Clasp" })
    }

    @Test func othersThanFiltersCurrentApp() {
        let others = LorisLabsApp.othersThan("com.lorislab.claspapp")
        #expect(!others.contains { $0.name == "Clasp" })
        #expect(others.count == LorisLabsApp.portfolio.count - 1)
    }

    @Test func appStoreURLsAreWellFormed() {
        for app in LorisLabsApp.portfolio {
            #expect(app.appStoreURL.absoluteString.hasPrefix("https://apps.apple.com/"))
            #expect(app.itmsURL.absoluteString.hasPrefix("itms-apps://"))
        }
    }
}

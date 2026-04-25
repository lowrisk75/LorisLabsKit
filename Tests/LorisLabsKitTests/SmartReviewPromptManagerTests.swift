import Testing
import Foundation
@testable import LorisLabsKit

@MainActor
struct SmartReviewPromptManagerTests {

    private func makeManager(
        config: SmartReviewPromptManager.Configuration = .init(),
        version: String = "1.0"
    ) -> (SmartReviewPromptManager, UserDefaults) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let mgr = SmartReviewPromptManager(
            configuration: config,
            userDefaults: defaults,
            appVersion: version,
            bundleIdentifier: "com.test.app"
        )
        return (mgr, defaults)
    }

    @Test func freshlyInstalledAppShouldNotPrompt() {
        let (mgr, _) = makeManager()
        #expect(!mgr.shouldPromptNow)
    }

    @Test func belowLaunchThresholdShouldNotPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0))
        for _ in 0..<3 { mgr.recordLaunch() }
        for _ in 0..<3 { mgr.recordSuccessMoment() }
        #expect(!mgr.shouldPromptNow)
    }

    @Test func belowSuccessMomentThresholdShouldNotPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0))
        for _ in 0..<5 { mgr.recordLaunch() }
        for _ in 0..<2 { mgr.recordSuccessMoment() }
        #expect(!mgr.shouldPromptNow)
    }

    @Test func recentErrorBlocksPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0, errorBlackoutDays: 7))
        for _ in 0..<5 { mgr.recordLaunch() }
        for _ in 0..<3 { mgr.recordSuccessMoment() }
        mgr.recordError()
        #expect(!mgr.shouldPromptNow)
    }

    @Test func activeFreeTrialBlocksPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0))
        for _ in 0..<5 { mgr.recordLaunch() }
        for _ in 0..<3 { mgr.recordSuccessMoment() }
        mgr.recordTrialState(.trialActive)
        #expect(!mgr.shouldPromptNow)
    }

    @Test func paidProUserMeetsCriteriaShouldPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0))
        for _ in 0..<5 { mgr.recordLaunch() }
        for _ in 0..<3 { mgr.recordSuccessMoment() }
        mgr.recordTrialState(.proPaid)
        #expect(mgr.shouldPromptNow)
    }

    @Test func freeUserMeetsCriteriaShouldPrompt() {
        let (mgr, _) = makeManager(config: .init(minimumLaunches: 5, minimumSuccessMoments: 3, minimumDaysSinceInstall: 0))
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

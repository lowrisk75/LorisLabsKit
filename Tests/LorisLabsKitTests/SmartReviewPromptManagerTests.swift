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
        clock: TestClock? = nil,
        enforceSessionTiming: Bool = false
    ) -> (SmartReviewPromptManager, UserDefaults) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        var resolved = config
        if !enforceSessionTiming {
            resolved.minimumSessionDuration = 0
            resolved.minimumCompletionDelay = 0
        }
        let mgr = SmartReviewPromptManager(
            configuration: resolved,
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
        mgr.recordCompletedAction()
        #expect(!mgr.shouldPromptNow)
        clock.date = start.addingTimeInterval(120 * 86_400)
        mgr.recordCompletedAction()
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

    @Test func launchAloneNeverPromptsEvenWithEligiblePersistedHistory() {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let (first, defaults) = makeManager(config: .init(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1), clock: clock)
        first.recordSuccessMoment()
        #expect(first.shouldPromptNow)
        let next = SmartReviewPromptManager(configuration: .init(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1, minimumSessionDuration: 0, minimumCompletionDelay: 0), userDefaults: defaults, bundleIdentifier: "com.test.app", now: { clock.date })
        for _ in 0..<50 { next.recordLaunch() }
        #expect(!next.shouldPromptNow)
        #expect(!next.attemptReview { Issue.record("A launch must never display a prompt") })
        next.recordSuccessMoment()
        #expect(next.shouldPromptNow)
    }

    @Test func startupAndCompletionDelaysBothApply() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TestClock(start)
        let (manager, _) = makeManager(config: .init(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1), clock: clock, enforceSessionTiming: true)
        manager.recordSuccessMoment()
        clock.date = start.addingTimeInterval(119)
        #expect(!manager.shouldPromptNow)
        clock.date = start.addingTimeInterval(120)
        manager.recordSuccessMoment()
        #expect(!manager.shouldPromptNow)
        clock.date = start.addingTimeInterval(122)
        #expect(manager.shouldPromptNow)
    }

    @Test func attemptsPersistBeforeCallbackAndAcrossNewVersionsAndLaunches() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TestClock(start)
        let config = SmartReviewPromptManager.Configuration(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1, minimumSessionDuration: 0, minimumCompletionDelay: 0)
        let (first, defaults) = makeManager(config: config, clock: clock)
        first.recordSuccessMoment()
        var requests = 0
        let attempted = first.attemptReview {
            requests += 1
            #expect(!first.shouldPromptNow)
            #expect(!first.attemptReview { requests += 1 })
        }
        #expect(attempted)
        #expect(requests == 1)
        clock.date = start.addingTimeInterval(119 * 86_400)
        let next = SmartReviewPromptManager(configuration: config, userDefaults: defaults, appVersion: "2.0", bundleIdentifier: "com.test.app", now: { clock.date })
        next.recordSuccessMoment()
        #expect(!next.shouldPromptNow)
        clock.date = start.addingTimeInterval(120 * 86_400)
        next.recordCompletedAction()
        #expect(next.shouldPromptNow)
    }
    @Test func relaunchAndVersionChangeRequireNewCompletionAndPersistCooldown() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TestClock(start)
        let config = SmartReviewPromptManager.Configuration(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1, minimumSessionDuration: 0, minimumCompletionDelay: 0)
        let (first, defaults) = makeManager(config: config, clock: clock)
        first.recordCompletedAction()
        var requests = 0
        #expect(first.attemptIfAppropriate(isSceneActive: true) { requests += 1 })
        #expect(!first.attemptIfAppropriate(isSceneActive: true) { requests += 1 })
        let next = SmartReviewPromptManager(configuration: config, userDefaults: defaults,
            appVersion: "2.0", bundleIdentifier: "com.test.app", now: { clock.date })
        clock.date = start.addingTimeInterval(119 * 86_400)
        next.recordCompletedAction()
        #expect(!next.shouldPromptNow)
        clock.date = start.addingTimeInterval(120 * 86_400)
        #expect(!next.shouldPromptNow, "A stale action cannot qualify a later launch")
        next.recordCompletedAction()
        #expect(next.attemptIfAppropriate(isSceneActive: true) { requests += 1 })
        #expect(requests == 2)
    }

    @Test func sameVersionStaysSuppressedEvenAfterCooldown() {
        let clock = TestClock(Date(timeIntervalSince1970: 1_700_000_000))
        let config = SmartReviewPromptManager.Configuration(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1, minimumSessionDuration: 0, minimumCompletionDelay: 0)
        let (first, defaults) = makeManager(config: config, clock: clock)
        first.recordCompletedAction()
        #expect(first.attemptIfAppropriate(isSceneActive: true) {})
        clock.date.addTimeInterval(121 * 86_400)
        let relaunched = SmartReviewPromptManager(configuration: config, userDefaults: defaults,
            appVersion: "1.0", bundleIdentifier: "com.test.app", now: { clock.date })
        relaunched.recordCompletedAction()
        #expect(!relaunched.shouldPromptNow)
    }

    @Test func firstFourteenDaysAndThreeActiveDaysAreRequired() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let clock = TestClock(start)
        let (manager, _) = makeManager(clock: clock)
        for _ in 0..<5 { manager.recordCompletedAction() }
        clock.date.addTimeInterval(86_400); manager.recordCompletedAction()
        clock.date = start.addingTimeInterval(14 * 86_400 - 1); manager.recordCompletedAction()
        #expect(!manager.shouldPromptNow)
        clock.date.addTimeInterval(1)
        #expect(manager.shouldPromptNow)
        clock.date = start.addingTimeInterval(-1)
        #expect(!manager.shouldPromptNow, "Clock rollback must fail closed")
    }

    @Test func anotherManagerAndInactiveSceneCannotDuplicateAnAttempt() {
        let config = SmartReviewPromptManager.Configuration(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1, minimumSessionDuration: 0, minimumCompletionDelay: 0)
        let (first, defaults) = makeManager(config: config)
        let second = SmartReviewPromptManager(configuration: config, userDefaults: defaults,
            appVersion: "1.0", bundleIdentifier: "com.test.app")
        first.recordCompletedAction(); second.recordCompletedAction()
        #expect(!first.attemptIfAppropriate(isSceneActive: false) {})
        #expect(first.attemptIfAppropriate(isSceneActive: true) {})
        #expect(!second.attemptIfAppropriate(isSceneActive: true) {})
    }

    @Test func cancelledPauseDoesNotRequestOrConsumeCooldown() async throws {
        let config = SmartReviewPromptManager.Configuration(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1, minimumSessionDuration: 0, minimumCompletionDelay: 0)
        let (manager, defaults) = makeManager(config: config)
        manager.recordCompletedAction()
        var requests = 0
        let task = Task { await manager.requestAfterPause(delay: .milliseconds(100), isSceneActive: { true }, isIdle: { true }) { requests += 1 } }
        try await Task.sleep(for: .milliseconds(5)); task.cancel(); await task.value
        #expect(requests == 0)
        #expect(defaults.object(forKey: "lorislabskit.review.lastPromptDate") == nil)
        #expect(manager.shouldPromptNow)
    }

    @Test func modalOpenedDuringPauseDoesNotConsumeAttempt() async throws {
        let config = SmartReviewPromptManager.Configuration(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1, minimumSessionDuration: 0, minimumCompletionDelay: 0)
        let (manager, defaults) = makeManager(config: config)
        manager.recordCompletedAction()
        var modalVisible = false, requests = 0
        let task = Task { await manager.requestAfterPause(delay: .milliseconds(30), isSceneActive: { true }, isIdle: { !modalVisible }) { requests += 1 } }
        try await Task.sleep(for: .milliseconds(5)); modalVisible = true
        await task.value
        #expect(requests == 0)
        #expect(defaults.object(forKey: "lorislabskit.review.lastPromptDate") == nil)
        modalVisible = false
        await manager.requestAfterPause(delay: .milliseconds(1), isSceneActive: { true }, isIdle: { !modalVisible }) { requests += 1 }
        #expect(requests == 1)
    }

    @Test func activityAndInteractionAreRecheckedAfterPause() async throws {
        let config = SmartReviewPromptManager.Configuration(minimumSuccessMoments: 1, minimumDaysSinceInstall: 0, minimumActiveDays: 1, minimumSessionDuration: 0, minimumCompletionDelay: 0)
        let (manager, _) = makeManager(config: config)
        manager.recordCompletedAction()
        var active = true, idle = true, requests = 0
        let task = Task { await manager.requestAfterPause(delay: .milliseconds(30), isSceneActive: { active }, isIdle: { idle }) { requests += 1 } }
        try await Task.sleep(for: .milliseconds(5)); active = false; idle = false
        await task.value
        #expect(requests == 0)
        #expect(manager.shouldPromptNow)
        active = true; idle = true
        await manager.requestAfterPause(delay: .milliseconds(1), isSceneActive: { active }, isIdle: { idle }) { requests += 1 }
        #expect(requests == 1)
        #expect(!manager.shouldPromptNow)
    }

}

@Suite struct LorisLabsAppTests {
    @Test func portfolioContainsLiveApps() {
        #expect(LorisLabsApp.portfolio.contains { $0.name == "Lumen for Frigate" })
        #expect(LorisLabsApp.portfolio.contains { $0.ascAppId == "6759068382" })
    }

    @Test func othersThanFiltersCurrentApp() {
        let others = LorisLabsApp.othersThan("com.lorislab.claspapp")
        #expect(!others.contains { $0.ascAppId == "6759068382" })
        #expect(others.count == LorisLabsApp.portfolio.count - 1)
    }

    @Test func appStoreURLsAreWellFormed() {
        for app in LorisLabsApp.portfolio {
            #expect(app.appStoreURL.absoluteString.hasPrefix("https://apps.apple.com/"))
            #expect(app.itmsURL.absoluteString.hasPrefix("itms-apps://"))
        }
    }
}

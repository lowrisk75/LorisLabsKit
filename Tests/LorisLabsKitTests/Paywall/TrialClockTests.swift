import Foundation
import LorisSecurityTesting
import Testing
@testable import LorisLabsKit

/// Clock tampering and the single trial engine. Synthetic keychain: no writes
/// to the user's real keychain.
@Suite struct TrialClockTests {
    private let day: TimeInterval = 86_400
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func trial(days: Double = 7, backend: InMemoryLegacyKeychainBackend = InMemoryLegacyKeychainBackend()) -> LorisTrialService {
        LorisTrialService(duration: days * day, keychain: LorisKeychain(service: "com.lorislab.tests.trialclock", backend: backend))
    }

    @Test func rollingTheClockBackDoesNotRevive_anExpiredTrial() {
        let t = trial()
        t.startIfNeeded(now: start)
        #expect(t.hasExpired(now: start.addingTimeInterval(8 * day)))

        let rolledBack = start.addingTimeInterval(-day)
        #expect(!t.isActive(now: rolledBack))
        #expect(t.hasExpired(now: rolledBack))
        #expect(t.daysRemaining(now: rolledBack) == 0)
    }

    @Test func rollingTheClockBackDoesNotAddDays() {
        let t = trial()
        t.startIfNeeded(now: start)
        #expect(t.daysRemaining(now: start.addingTimeInterval(5 * day)) == 2)
        #expect(t.daysRemaining(now: start.addingTimeInterval(1 * day)) == 2)
    }

    /// A trial stored by an older build has no high-water mark: a clock set
    /// before the start date must still not grant more than the full duration.
    @Test func clockBeforeStartNeverExceedsTheFullDuration() throws {
        let backend = InMemoryLegacyKeychainBackend()
        let keychain = LorisKeychain(service: "com.lorislab.tests.trialclock", backend: backend)
        try keychain.save(String(start.timeIntervalSince1970), forKey: "loris.paywall.trial.start")
        let t = LorisTrialService(duration: 7 * day, keychain: keychain)

        #expect(t.daysRemaining(now: start.addingTimeInterval(-10 * day)) == 7)
    }

    @Test func normalForwardTimeIsUnchanged() {
        let t = trial(days: 3)
        t.startIfNeeded(now: start)
        #expect(t.isActive(now: start))
        #expect(t.daysRemaining(now: start) == 3)
        #expect(t.isActive(now: start.addingTimeInterval(3 * day - 1)))
        #expect(t.hasExpired(now: start.addingTimeInterval(3 * day + 1)))
    }

    @Test func resetClearsTheHighWaterMarkToo() {
        let t = trial()
        t.startIfNeeded(now: start)
        _ = t.isActive(now: start.addingTimeInterval(30 * day))
        t.reset()
        let restart = start.addingTimeInterval(day)
        #expect(t.startIfNeeded(now: restart))
        #expect(t.daysRemaining(now: restart) == 7)
    }

    // MARK: TrialManager runs on the same engine

    /// `TrialManager` stored whole seconds under `<bundleId>.trial` / `started-at`.
    /// Backed by `LorisTrialService`, it must keep reading that item.
    @available(*, deprecated)
    @Test @MainActor func trialManagerKeepsItsExistingStoredStart() throws {
        let backend = InMemoryLegacyKeychainBackend()
        let keychain = LorisKeychain(service: "com.test.app.trial", backend: backend)
        let stored = Date().addingTimeInterval(-2 * day)
        try keychain.save(String(Int64(stored.timeIntervalSince1970)), forKey: "started-at")

        let manager = TrialManager(days: 7, keychain: keychain)

        #expect(manager.startedAt.map { Int64($0.timeIntervalSince1970) } == Int64(stored.timeIntervalSince1970))
        #expect(manager.isActive)
        #expect(manager.daysLeft == 5)
    }

    @available(*, deprecated)
    @Test @MainActor func trialManagerStartsOnFirstLaunchAndResets() {
        let backend = InMemoryLegacyKeychainBackend()
        let keychain = LorisKeychain(service: "com.test.app.trial", backend: backend)

        let manager = TrialManager(days: 7, keychain: keychain)
        #expect(manager.startedAt != nil)
        #expect(manager.isActive)
        #expect(!manager.hasExpired)

        manager.reset()
        #expect(manager.startedAt == nil)
        #expect(!manager.isActive)
    }
}

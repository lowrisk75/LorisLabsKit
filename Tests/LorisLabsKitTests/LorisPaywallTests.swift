import Foundation
import Testing
@testable import LorisLabsKit

struct EntitlementStateTests {
    @Test func trialUnlocksFeaturesButIsNotAPurchase() {
        let trial = EntitlementState.trial(daysRemaining: 3)
        #expect(trial.isPro)
        #expect(!trial.isPaid)
    }

    @Test func lifetimeAndSubscriptionAreBothPaid() {
        #expect(EntitlementState.lifetime.isPaid)
        #expect(EntitlementState.subscribed(expiration: Date()).isPaid)
    }

    @Test func noneUnlocksNothing() {
        #expect(!EntitlementState.none.isPro)
        #expect(!EntitlementState.none.isPaid)
    }
}

struct RenewalStatusTests {
    @Test func healthyStatesNeedNoAttention() {
        #expect(!RenewalStatus.notSubscribed.needsAttention)
        #expect(!RenewalStatus.active(expiration: Date()).needsAttention)
    }

    @Test func failingRenewalsAreFlagged() {
        #expect(RenewalStatus.inBillingRetry.needsAttention)
        #expect(RenewalStatus.inGracePeriod(until: Date()).needsAttention)
        #expect(RenewalStatus.expiringSoon(expiration: Date()).needsAttention)
        #expect(RenewalStatus.revoked.needsAttention)
        #expect(RenewalStatus.expired.needsAttention)
    }
}

struct LorisTrialServiceTests {
    /// Each test gets its own keychain service so runs stay independent.
    private func makeTrial(days: Double, suffix: String = UUID().uuidString) -> LorisTrialService {
        LorisTrialService(
            duration: days * 86_400,
            keychainService: "com.lorislab.tests.trial.\(suffix)"
        )
    }

    @Test func trialStartsOnceAndIsNotRegranted() {
        let trial = makeTrial(days: 7)
        defer { trial.reset() }

        #expect(!trial.hasStarted)
        #expect(trial.startIfNeeded())
        #expect(trial.hasStarted)
        // The whole point of moving off UserDefaults: no second trial.
        #expect(!trial.startIfNeeded())
    }

    @Test func remainingDaysCountDownAndFloorAtZero() {
        let trial = makeTrial(days: 7)
        defer { trial.reset() }

        let start = Date()
        trial.startIfNeeded(now: start)

        #expect(trial.isActive(now: start))
        #expect(trial.daysRemaining(now: start) == 7)
        #expect(trial.daysRemaining(now: start.addingTimeInterval(5 * 86_400)) == 2)
        #expect(trial.daysRemaining(now: start.addingTimeInterval(30 * 86_400)) == 0)
    }

    @Test func trialExpiresAfterItsDuration() {
        let trial = makeTrial(days: 3)
        defer { trial.reset() }

        let start = Date()
        trial.startIfNeeded(now: start)
        let afterExpiry = start.addingTimeInterval(3 * 86_400 + 1)

        #expect(!trial.isActive(now: afterExpiry))
        #expect(trial.hasExpired(now: afterExpiry))
    }

    @Test func anUnstartedTrialHasNotExpired() {
        let trial = makeTrial(days: 7)
        defer { trial.reset() }

        #expect(!trial.hasExpired())
        #expect(!trial.isActive())
        #expect(trial.daysRemaining() == 0)
    }
}

import Foundation
import OSLog

/// Portfolio-generic trial clock (ported from Throttle's TrialService).
/// State lives in Keychain so re-installing the app doesn't reset the clock —
/// only a deliberate Keychain wipe (or a new machine) gives a fresh trial.
///
/// Now a thin front for `LorisTrialService`, the single trial engine: same
/// keychain item as before (`<bundleId>.trial` / `started-at`), so running
/// trials carry over, and the same clock-rollback guard.
///
/// Typical activation rule in an app:
///   `isPro = licenseValid || storeKitEntitlement || trial.isActive`
@available(*, deprecated, message: "Use LorisTrialService (or PaywallConfiguration.trialDuration with LorisPaywallStore).")
@MainActor
public final class TrialManager {
    private let logger: Logger
    private let trial: LorisTrialService

    public private(set) var startedAt: Date?

    /// - Parameters:
    ///   - bundleId: keychain namespace, e.g. "com.lorislab.claspapp" — each app gets its own clock
    ///   - days: trial length (default 7)
    public convenience init(bundleId: String, days: Int = 7) {
        self.init(days: days, keychain: LorisKeychain(service: "\(bundleId).trial"), logSubsystem: bundleId)
    }

    init(days: Int, keychain: LorisKeychain, logSubsystem: String = "com.lorislab.kit") {
        self.logger = Logger(subsystem: logSubsystem, category: "Trial")
        self.trial = LorisTrialService(duration: TimeInterval(days) * 24 * 3600, keychain: keychain, startKey: "started-at", storesWholeSeconds: true)
        if trial.startIfNeeded() {
            logger.info("Trial started")
        }
        self.startedAt = trial.startDate
    }

    /// True while inside the trial window.
    public var isActive: Bool { trial.isActive() }

    /// Days remaining (0 once expired) — for countdown banners.
    public var daysLeft: Int { trial.daysRemaining() }

    /// True iff the trial has started AND is now expired (distinct banner copy).
    public var hasExpired: Bool { trial.hasExpired() }

    /// Reset trial state (dev tooling / tests only — never expose in UI).
    public func reset() {
        trial.reset()
        startedAt = nil
    }
}

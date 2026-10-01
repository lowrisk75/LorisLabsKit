import Foundation
import StoreKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Tracks meaningful use and attempts the native StoreKit review prompt at an idle moment.
/// Payment status, satisfaction and past errors never select users for reviews.
/// StoreKit decides whether to show the prompt; no callback proves display or a submitted review.
///
/// Default experiment: fourteen days of use, five completions on three distinct days,
/// one attempt per session/version and a 120-day cooldown. These thresholds are tunable,
/// not a measured guarantee of review conversion. Help remains independently accessible.
///
/// Usage:
/// ```swift
/// // 1. Create one shared instance
/// let reviewManager = SmartReviewPromptManager(bundleIdentifier: Bundle.main.bundleIdentifier!)
///
/// // 2. Inject as @Environment in your @main App
/// .environment(reviewManager)
///
/// // 3. Track signals as they happen
/// reviewManager.recordLaunch()                  // call once per cold start
/// reviewManager.recordSuccessMoment()           // user did something successful
/// reviewManager.recordError()                   // app showed an error
/// reviewManager.recordTrialState(.proPaid)      // user is on paid Pro (or .free / .trialActive)
///
/// // 4. Trigger from a "moment of success" view
/// @Environment(\.requestReview) private var requestReview
/// @Environment(SmartReviewPromptManager.self) private var reviewManager
/// // After user views a captured event:
/// .task { reviewManager.requestIfAppropriate(via: requestReview) }
/// ```
@MainActor
@Observable
public final class SmartReviewPromptManager {

    // MARK: - Configuration

    /// Tunable thresholds. Defaults are sensible for a typical premium-utility app.
    public struct Configuration: Sendable {
        public var minimumLaunches: Int
        public var minimumSuccessMoments: Int
        public var minimumDaysSinceInstall: Int
        public var cooldownDays: Int
        /// Legacy compatibility setting; does not affect eligibility.
        public var errorBlackoutDays: Int
        public var minimumActiveDays: Int
        /// Legacy compatibility setting; does not affect eligibility.
        public var requireNonTrialUser: Bool

        public init(
            minimumLaunches: Int = 0,
            minimumSuccessMoments: Int = 5,
            minimumDaysSinceInstall: Int = 14,
            cooldownDays: Int = 120,
            errorBlackoutDays: Int = 0,
            requireNonTrialUser: Bool = false,
            minimumActiveDays: Int = 3
        ) {
            self.minimumLaunches = minimumLaunches
            self.minimumSuccessMoments = minimumSuccessMoments
            self.minimumDaysSinceInstall = minimumDaysSinceInstall
            self.cooldownDays = cooldownDays
            self.errorBlackoutDays = errorBlackoutDays
            self.requireNonTrialUser = requireNonTrialUser
            self.minimumActiveDays = minimumActiveDays
        }
    }

    /// Compatibility signal only. Payment state never determines review eligibility.
    public enum TrialState: Sendable {
        case free
        case trialActive
        case proPaid
    }

    // MARK: - Storage keys

    private enum Key {
        static let activeDays = "lorislabskit.review.activeDays"
        static let installDate = "lorislabskit.review.installDate"
        static let totalLaunches = "lorislabskit.review.totalLaunches"
        static let totalSuccessMoments = "lorislabskit.review.totalSuccessMoments"
        static let lastErrorDate = "lorislabskit.review.lastErrorDate"
        // Keep the persisted values stable while naming the semantics honestly:
        // StoreKit does not reveal whether the prompt was displayed.
        static let lastAttemptDate = "lorislabskit.review.lastPromptDate"
        static let attemptedForVersion = "lorislabskit.review.promptedForVersion"
    }

    // MARK: - Stored state

    private let userDefaults: UserDefaults
    private let appVersion: String
    private let now: @MainActor @Sendable () -> Date
    public let configuration: Configuration
    public var interactionInProgress = false
    private var attemptedThisSession = false
    public private(set) var trialState: TrialState = .free

    // MARK: - Init

    public init(
        configuration: Configuration = Configuration(),
        userDefaults: UserDefaults = .standard,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0",
        bundleIdentifier: String,
        now: @escaping @MainActor @Sendable () -> Date = { Date() }
    ) {
        precondition(!bundleIdentifier.isEmpty, "bundleIdentifier must not be empty")
        self.configuration = configuration
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        self.now = now
        if userDefaults.object(forKey: Key.installDate) == nil {
            userDefaults.set(now(), forKey: Key.installDate)
        }
    }

    // MARK: - Recording signals

    public func recordLaunch() {
        let n = userDefaults.integer(forKey: Key.totalLaunches) + 1
        userDefaults.set(n, forKey: Key.totalLaunches)
    }

    public func recordSuccessMoment() {
        let n = userDefaults.integer(forKey: Key.totalSuccessMoments) + 1
        userDefaults.set(n, forKey: Key.totalSuccessMoments)
        var days = Set(userDefaults.stringArray(forKey: Key.activeDays) ?? [])
        days.insert(String(Int(now().timeIntervalSince1970 / 86_400)))
        userDefaults.set(Array(days.sorted().suffix(max(3, configuration.minimumActiveDays))), forKey: Key.activeDays)
    }

    public func recordError() {
        userDefaults.set(now(), forKey: Key.lastErrorDate)
    }

    public func recordTrialState(_ state: TrialState) {
        trialState = state
    }

    // MARK: - Decision

    /// True when ALL of the following are met:
    /// - At least `minimumLaunches` launches recorded
    /// - At least `minimumSuccessMoments` success moments recorded
    /// - At least `minimumDaysSinceInstall` days since first install
    /// - No interaction currently in progress
    /// - No prompt in the last `cooldownDays` days
    /// - No previous attempt for this app version
    /// Payment status and past errors do not affect eligibility.
    public var shouldPromptNow: Bool {
        let currentDate = now()
        guard !interactionInProgress, !attemptedThisSession else { return false }
        guard (userDefaults.stringArray(forKey: Key.activeDays) ?? []).count >= configuration.minimumActiveDays else { return false }
        let launches = userDefaults.integer(forKey: Key.totalLaunches)
        guard launches >= configuration.minimumLaunches else { return false }

        let successes = userDefaults.integer(forKey: Key.totalSuccessMoments)
        guard successes >= configuration.minimumSuccessMoments else { return false }

        if let installDate = userDefaults.object(forKey: Key.installDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: installDate, to: currentDate).day ?? 0
            guard days >= configuration.minimumDaysSinceInstall else { return false }
        }

        if let lastAttempt = userDefaults.object(forKey: Key.lastAttemptDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: lastAttempt, to: currentDate).day ?? 0
            if days < configuration.cooldownDays { return false }
        }

        if let lastVersion = userDefaults.string(forKey: Key.attemptedForVersion), lastVersion == appVersion {
            return false
        }


        return true
    }

    // MARK: - Triggering

    // RequestReviewAction / SKStoreReviewController are unavailable on tvOS
    // (no App Store review prompts on Apple TV), so both entry points are gated.
    #if !os(tvOS) && !os(watchOS)
    /// Asks SwiftUI's `RequestReviewAction` to show the prompt — but only if criteria are met.
    /// Records the attempt so future calls obey the cooldown. StoreKit may show nothing.
    public func requestIfAppropriate(via action: RequestReviewAction) {
        guard shouldPromptNow else { return }
        action()
        recordPromptAttempted()
    }
    #endif

    #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
    /// Use this when called from a non-SwiftUI context (e.g. UIKit).
    public func requestIfAppropriate(in scene: UIWindowScene) {
        guard shouldPromptNow else { return }
        SKStoreReviewController.requestReview(in: scene)
        recordPromptAttempted()
    }
    #endif

    private func recordPromptAttempted() {
        attemptedThisSession = true
        userDefaults.set(now(), forKey: Key.lastAttemptDate)
        userDefaults.set(appVersion, forKey: Key.attemptedForVersion)
    }

    // MARK: - Debug / testing helpers

    public var debugDescription: String {
        let launches = userDefaults.integer(forKey: Key.totalLaunches)
        let successes = userDefaults.integer(forKey: Key.totalSuccessMoments)
        let installDate = userDefaults.object(forKey: Key.installDate) as? Date
        let lastError = userDefaults.object(forKey: Key.lastErrorDate) as? Date
        let lastAttempt = userDefaults.object(forKey: Key.lastAttemptDate) as? Date
        let attemptedVersion = userDefaults.string(forKey: Key.attemptedForVersion) ?? "—"
        return """
        SmartReviewPromptManager(
          launches: \(launches) / \(configuration.minimumLaunches),
          successes: \(successes) / \(configuration.minimumSuccessMoments),
          installDate: \(installDate.map(String.init(describing:)) ?? "nil"),
          lastError: \(lastError.map(String.init(describing:)) ?? "nil"),
          lastAttempt: \(lastAttempt.map(String.init(describing:)) ?? "nil"),
          attemptedForVersion: \(attemptedVersion),
          currentVersion: \(appVersion),
          trialState: \(trialState),
          shouldPromptNow: \(shouldPromptNow)
        )
        """
    }

    /// FOR TESTS ONLY. Wipes all stored signals.
    public func resetAllState() {
        attemptedThisSession = false
        for key in [
            Key.installDate, Key.activeDays, Key.totalLaunches, Key.totalSuccessMoments,
            Key.lastErrorDate, Key.lastAttemptDate, Key.attemptedForVersion
        ] {
            userDefaults.removeObject(forKey: key)
        }
        userDefaults.set(now(), forKey: Key.installDate)
    }
}

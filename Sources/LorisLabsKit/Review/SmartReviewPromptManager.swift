import Foundation
import StoreKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Smart review prompt manager that tracks launches, success moments, and errors,
/// then prompts via `SKStoreReviewController` / `RequestReviewAction` only when
/// the user is in a positive emotional state and Apple's per-year cap is not yet hit.
///
/// Apple-enforced rules (you don't have to handle, the system does):
/// - Max 3 prompts per user per 365 days
/// - Prompts shown only on devices with App Store access
/// - User dismissal counts as a presentation
///
/// Best practices this manager enforces (you DO need to track these):
/// - Don't prompt before N launches AND N success moments
/// - Don't prompt within X days of an error
/// - Don't prompt within Y days of the last prompt (this manager's cooldown, on top of Apple's cap)
/// - Don't prompt while the user is in a free trial (their judgment is biased by price)
/// - Don't prompt before Z days since install
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
        public var errorBlackoutDays: Int
        public var requireNonTrialUser: Bool

        public init(
            minimumLaunches: Int = 5,
            minimumSuccessMoments: Int = 3,
            minimumDaysSinceInstall: Int = 7,
            cooldownDays: Int = 60,
            errorBlackoutDays: Int = 7,
            requireNonTrialUser: Bool = true
        ) {
            self.minimumLaunches = minimumLaunches
            self.minimumSuccessMoments = minimumSuccessMoments
            self.minimumDaysSinceInstall = minimumDaysSinceInstall
            self.cooldownDays = cooldownDays
            self.errorBlackoutDays = errorBlackoutDays
            self.requireNonTrialUser = requireNonTrialUser
        }
    }

    /// Trial / paid state. The manager refuses to prompt during an active trial because
    /// the user's judgment is biased by the price they haven't yet paid.
    public enum TrialState: Sendable {
        case free
        case trialActive
        case proPaid
    }

    // MARK: - Storage keys

    private enum Key {
        static let installDate = "lorislabskit.review.installDate"
        static let totalLaunches = "lorislabskit.review.totalLaunches"
        static let totalSuccessMoments = "lorislabskit.review.totalSuccessMoments"
        static let lastErrorDate = "lorislabskit.review.lastErrorDate"
        static let lastPromptDate = "lorislabskit.review.lastPromptDate"
        static let promptedForVersion = "lorislabskit.review.promptedForVersion"
    }

    // MARK: - Stored state

    private let userDefaults: UserDefaults
    private let appVersion: String
    public let configuration: Configuration
    public private(set) var trialState: TrialState = .free

    // MARK: - Init

    public init(
        configuration: Configuration = Configuration(),
        userDefaults: UserDefaults = .standard,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0",
        bundleIdentifier: String
    ) {
        self.configuration = configuration
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        if userDefaults.object(forKey: Key.installDate) == nil {
            userDefaults.set(Date(), forKey: Key.installDate)
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
    }

    public func recordError() {
        userDefaults.set(Date(), forKey: Key.lastErrorDate)
    }

    public func recordTrialState(_ state: TrialState) {
        trialState = state
    }

    // MARK: - Decision

    /// True when ALL of the following are met:
    /// - At least `minimumLaunches` launches recorded
    /// - At least `minimumSuccessMoments` success moments recorded
    /// - At least `minimumDaysSinceInstall` days since first install
    /// - No error in the last `errorBlackoutDays` days
    /// - No prompt in the last `cooldownDays` days
    /// - Not already prompted this app version
    /// - User is not currently on free trial (if `requireNonTrialUser`)
    public var shouldPromptNow: Bool {
        let launches = userDefaults.integer(forKey: Key.totalLaunches)
        guard launches >= configuration.minimumLaunches else { return false }

        let successes = userDefaults.integer(forKey: Key.totalSuccessMoments)
        guard successes >= configuration.minimumSuccessMoments else { return false }

        if let installDate = userDefaults.object(forKey: Key.installDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
            guard days >= configuration.minimumDaysSinceInstall else { return false }
        }

        if let lastError = userDefaults.object(forKey: Key.lastErrorDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: lastError, to: Date()).day ?? 0
            if days < configuration.errorBlackoutDays { return false }
        }

        if let lastPrompt = userDefaults.object(forKey: Key.lastPromptDate) as? Date {
            let days = Calendar.current.dateComponents([.day], from: lastPrompt, to: Date()).day ?? 0
            if days < configuration.cooldownDays { return false }
        }

        if let lastVersion = userDefaults.string(forKey: Key.promptedForVersion), lastVersion == appVersion {
            return false
        }

        if configuration.requireNonTrialUser, trialState == .trialActive {
            return false
        }

        return true
    }

    // MARK: - Triggering

    /// Asks SwiftUI's `RequestReviewAction` to show the prompt — but only if criteria are met.
    /// Records the prompt so future calls obey the cooldown.
    public func requestIfAppropriate(via action: RequestReviewAction) {
        guard shouldPromptNow else { return }
        action()
        recordPromptShown()
    }

    #if canImport(UIKit) && !os(watchOS)
    /// Use this when called from a non-SwiftUI context (e.g. UIKit).
    public func requestIfAppropriate(in scene: UIWindowScene) {
        guard shouldPromptNow else { return }
        SKStoreReviewController.requestReview(in: scene)
        recordPromptShown()
    }
    #endif

    private func recordPromptShown() {
        userDefaults.set(Date(), forKey: Key.lastPromptDate)
        userDefaults.set(appVersion, forKey: Key.promptedForVersion)
    }

    // MARK: - Debug / testing helpers

    public var debugDescription: String {
        let launches = userDefaults.integer(forKey: Key.totalLaunches)
        let successes = userDefaults.integer(forKey: Key.totalSuccessMoments)
        let installDate = userDefaults.object(forKey: Key.installDate) as? Date
        let lastError = userDefaults.object(forKey: Key.lastErrorDate) as? Date
        let lastPrompt = userDefaults.object(forKey: Key.lastPromptDate) as? Date
        let promptedVersion = userDefaults.string(forKey: Key.promptedForVersion) ?? "—"
        return """
        SmartReviewPromptManager(
          launches: \(launches) / \(configuration.minimumLaunches),
          successes: \(successes) / \(configuration.minimumSuccessMoments),
          installDate: \(installDate.map(String.init(describing:)) ?? "nil"),
          lastError: \(lastError.map(String.init(describing:)) ?? "nil"),
          lastPrompt: \(lastPrompt.map(String.init(describing:)) ?? "nil"),
          promptedForVersion: \(promptedVersion),
          currentVersion: \(appVersion),
          trialState: \(trialState),
          shouldPromptNow: \(shouldPromptNow)
        )
        """
    }

    /// FOR TESTS ONLY. Wipes all stored signals.
    public func resetAllState() {
        for key in [
            Key.installDate, Key.totalLaunches, Key.totalSuccessMoments,
            Key.lastErrorDate, Key.lastPromptDate, Key.promptedForVersion
        ] {
            userDefaults.removeObject(forKey: key)
        }
        userDefaults.set(Date(), forKey: Key.installDate)
    }
}

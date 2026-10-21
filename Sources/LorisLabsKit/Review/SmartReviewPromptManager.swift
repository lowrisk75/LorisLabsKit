import Foundation
import StoreKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Tracks meaningful use and attempts the native StoreKit review prompt at an idle moment.
/// Payment status, satisfaction and past errors never select users for reviews.
/// StoreKit decides whether to show the prompt; no callback proves display or a submitted review.
///
/// Default experiment: fourteen days of use, five completions on three distinct days,
/// a completion in this session after two minutes of use, one attempt per
/// session/version and a 120-day cooldown. These thresholds are tunable,
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
        /// Suppress automatic requests while the app is starting up.
        public var minimumSessionDuration: TimeInterval
        /// Leave time for the completed action to finish rendering.
        public var minimumCompletionDelay: TimeInterval
        /// Legacy compatibility setting; does not affect eligibility.
        public var requireNonTrialUser: Bool

        public init(
            minimumLaunches: Int = 0,
            minimumSuccessMoments: Int = 5,
            minimumDaysSinceInstall: Int = 14,
            cooldownDays: Int = 120,
            errorBlackoutDays: Int = 0,
            requireNonTrialUser: Bool = false,
            minimumActiveDays: Int = 3,
            minimumSessionDuration: TimeInterval = 120,
            minimumCompletionDelay: TimeInterval = 2
        ) {
            self.minimumLaunches = minimumLaunches
            self.minimumSuccessMoments = minimumSuccessMoments
            self.minimumDaysSinceInstall = minimumDaysSinceInstall
            self.cooldownDays = cooldownDays
            self.errorBlackoutDays = errorBlackoutDays
            self.requireNonTrialUser = requireNonTrialUser
            self.minimumActiveDays = minimumActiveDays
            self.minimumSessionDuration = minimumSessionDuration
            self.minimumCompletionDelay = minimumCompletionDelay
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
    /// Changes only after a completed action, never on launch or navigation.
    public private(set) var completionToken: UUID?
    private var lastCompletionAt: Date?
    private let sessionStartedAt: Date
    public private(set) var trialState: TrialState = .free

    // MARK: - Init

    public init(
        configuration: Configuration = Configuration(),
        userDefaults: UserDefaults = .standard,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0",
        bundleIdentifier: String,
        previousAttempt: ReviewAttempt? = nil,
        now: @escaping @MainActor @Sendable () -> Date = { Date() }
    ) {
        precondition(!bundleIdentifier.isEmpty, "bundleIdentifier must not be empty")
        self.configuration = configuration
        self.userDefaults = userDefaults
        self.appVersion = appVersion
        self.now = now
        self.sessionStartedAt = now()
        if let previousAttempt, userDefaults.object(forKey: Key.lastAttemptDate) == nil {
            userDefaults.set(previousAttempt.date, forKey: Key.lastAttemptDate)
            userDefaults.set(previousAttempt.version, forKey: Key.attemptedForVersion)
        }
        if userDefaults.object(forKey: Key.installDate) == nil {
            userDefaults.set(now(), forKey: Key.installDate)
        }
    }

    // MARK: - Recording signals

    /// Records usage only. A launch never grants a review opportunity or shows UI.
    public func recordLaunch() {
        let n = min(userDefaults.integer(forKey: Key.totalLaunches), 999_999) + 1
        userDefaults.set(n, forKey: Key.totalLaunches)
    }

    /// Call after a user-initiated task actually completes, never from startup/onAppear.
    /// Call once after a real task completes. Do not call from onAppear, launch, purchase or a rating button.
    public func recordCompletedAction() {
        lastCompletionAt = now()
        completionToken = UUID()
        let n = min(userDefaults.integer(forKey: Key.totalSuccessMoments), 999_999) + 1
        userDefaults.set(n, forKey: Key.totalSuccessMoments)
        var days = Set(userDefaults.stringArray(forKey: Key.activeDays) ?? [])
        days.insert(String(Int(now().timeIntervalSince1970 / 86_400)))
        userDefaults.set(Array(days.sorted().suffix(max(3, configuration.minimumActiveDays))), forKey: Key.activeDays)
    }

    /// Source-compatible alias. The completion describes use, never the person's satisfaction.
    public func recordSuccessMoment() { recordCompletedAction() }

    public func recordError() {
        userDefaults.set(now(), forKey: Key.lastErrorDate)
    }

    public func recordTrialState(_ state: TrialState) {
        trialState = state
    }

    /// Drop only the transient opportunity, retaining the persistent engagement history.
    public func cancelPendingReview() {
        lastCompletionAt = nil
        completionToken = nil
    }

    // MARK: - Decision

    /// True when ALL of the following are met:
    /// - At least `minimumLaunches` launches recorded
    /// - At least `minimumSuccessMoments` success moments recorded
    /// - At least `minimumDaysSinceInstall` days since first install
    /// - A completed action in this session within the last five minutes
    /// - At least `minimumActiveDays` distinct days of completed actions
    /// - No interaction currently in progress
    /// - No prompt in the last `cooldownDays` days
    /// - No previous attempt for this app version
    /// Payment status and past errors do not affect eligibility.
    public var shouldPromptNow: Bool {
        let date = now()
        guard let completion = lastCompletionAt, date >= completion,
              date.timeIntervalSince(completion) >= max(0, configuration.minimumCompletionDelay),
              date.timeIntervalSince(sessionStartedAt) >= max(0, configuration.minimumSessionDuration),
              date.timeIntervalSince(completion) <= 300,
              let install = userDefaults.object(forKey: Key.installDate) as? Date else { return false }
        var policy = ReviewPolicy()
        policy.minimumDays = max(0, configuration.minimumDaysSinceInstall)
        policy.minimumCompletions = max(1, configuration.minimumSuccessMoments)
        policy.minimumActiveDays = max(1, configuration.minimumActiveDays)
        policy.cooldownDays = max(0, configuration.cooldownDays)
        let state = ReviewEngagement(firstUse: install,
            completions: userDefaults.integer(forKey: Key.totalSuccessMoments),
            activeDays: Set(userDefaults.stringArray(forKey: Key.activeDays) ?? []),
            lastAttemptAt: userDefaults.object(forKey: Key.lastAttemptDate) as? Date,
            lastAttemptVersion: userDefaults.string(forKey: Key.attemptedForVersion))
        return userDefaults.integer(forKey: Key.totalLaunches) >= configuration.minimumLaunches
            && policy.isEligible(state, version: appVersion, now: date,
                interactionInProgress: interactionInProgress, attemptedThisSession: attemptedThisSession,
                completedThisSession: true)
    }

    /// The attempt is persisted BEFORE invoking StoreKit, including if StoreKit displays nothing.
    @discardableResult
    func attemptIfAppropriate(isSceneActive: Bool, request: () -> Void) -> Bool {
        guard isSceneActive, shouldPromptNow else { return false }
        recordPromptAttempted()
        request()
        return true
    }

    /// Shared cancellation/recheck path for native UI and deterministic tests.
    func requestAfterPause(delay: Duration = .seconds(2), isSceneActive: () -> Bool,
                           isIdle: () -> Bool, request: () -> Void) async {
        guard let completion = lastCompletionAt, isSceneActive(), isIdle() else { return }
        let date = now()
        let remaining = max(configuration.minimumSessionDuration - date.timeIntervalSince(sessionStartedAt),
                            configuration.minimumCompletionDelay - date.timeIntervalSince(completion), 0)
        do { try await Task.sleep(for: max(delay, .seconds(remaining))) } catch { return }
        guard !Task.isCancelled, isIdle() else { return }
        attemptIfAppropriate(isSceneActive: isSceneActive(), request: request)
    }

    // MARK: - Triggering

    // RequestReviewAction / SKStoreReviewController are unavailable on tvOS
    // (no App Store review prompts on Apple TV), so both entry points are gated.
    #if !os(tvOS) && !os(watchOS)
    /// Asks SwiftUI's `RequestReviewAction` to show the prompt — but only if criteria are met.
    /// Records the attempt so future calls obey the cooldown. StoreKit may show nothing.
    public func requestIfAppropriate(via action: RequestReviewAction) {
        #if canImport(UIKit)
        let active = UIApplication.shared.applicationState == .active
        #elseif canImport(AppKit)
        let active = NSApplication.shared.isActive
        #else
        let active = false
        #endif
        attemptIfAppropriate(isSceneActive: active) { action() }
    }
    #endif

    #if canImport(UIKit) && !os(watchOS) && !os(tvOS)
    /// Use this when called from a non-SwiftUI context (e.g. UIKit).
    public func requestIfAppropriate(in scene: UIWindowScene) {
        attemptIfAppropriate(isSceneActive: scene.activationState == .foregroundActive) {
            AppStore.requestReview(in: scene)
        }
    }
    #endif

    /// Shared decision path; tests inject a closure without displaying StoreKit UI.
    @discardableResult
    func attemptReview(_ request: () -> Void) -> Bool {
        attemptIfAppropriate(isSceneActive: true, request: request)
    }

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
        cancelPendingReview()
        for key in [
            Key.installDate, Key.activeDays, Key.totalLaunches, Key.totalSuccessMoments,
            Key.lastErrorDate, Key.lastAttemptDate, Key.attemptedForVersion
        ] {
            userDefaults.removeObject(forKey: key)
        }
        userDefaults.set(now(), forKey: Key.installDate)
    }
}

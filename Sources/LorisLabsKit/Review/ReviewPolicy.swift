import Foundation

/// Engagement policy only: never reads satisfaction, payment, support history or diagnostics.
public struct ReviewPolicy: Sendable {
    public var minimumDays = 14
    public var minimumCompletions = 5
    public var minimumActiveDays = 3
    public var cooldownDays = 120
    public init() {}

    public func isEligible(_ state: ReviewEngagement, version: String, now: Date,
                           interactionInProgress: Bool, attemptedThisSession: Bool) -> Bool {
        guard !interactionInProgress, !attemptedThisSession,
              now >= state.firstUse, now.timeIntervalSince(state.firstUse) >= Double(minimumDays) * 86_400,
              state.completions >= minimumCompletions, state.activeDays.count >= minimumActiveDays,
              state.lastAttemptVersion != version else { return false }
        if let last = state.lastAttemptAt {
            guard now.timeIntervalSince(last) >= Double(cooldownDays) * 86_400 else { return false }
        }
        return true
    }
}

public struct ReviewEngagement: Codable, Sendable {
    public var firstUse: Date
    public private(set) var completions = 0
    public private(set) var activeDays: Set<String> = []
    public private(set) var lastAttemptAt: Date?
    public private(set) var lastAttemptVersion: String?
    public init(firstUse: Date) { self.firstUse = firstUse }

    public mutating func recordCompletion(at date: Date) {
        completions = min(completions + 1, 1_000_000)
        let day = Int(date.timeIntervalSince1970 / 86_400)
        activeDays.insert(String(day))
        // Only three distinct days are needed. No long-term usage history is retained.
        if activeDays.count > 3 { activeDays = Set(activeDays.sorted().suffix(3)) }
    }
    /// StoreKit doesn't reveal whether its prompt appeared or a review was written.
    public mutating func recordAttempt(version: String, at date: Date) {
        lastAttemptAt = date; lastAttemptVersion = version
    }
}

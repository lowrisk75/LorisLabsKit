import XCTest
@testable import LorisLabsKit
final class ReviewPolicyTests: XCTestCase {
    func testDistinctDaysAndCooldownAndInteraction() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var state = ReviewEngagement(firstUse: start)
        let policy = ReviewPolicy()
        for _ in 0..<5 { state.recordCompletion(at: start) }
        let now = start.addingTimeInterval(20 * 86_400)
        XCTAssertFalse(policy.isEligible(state, version: "1", now: now, interactionInProgress: false, attemptedThisSession: false))
        state.recordCompletion(at: start.addingTimeInterval(86_400))
        state.recordCompletion(at: start.addingTimeInterval(2 * 86_400))
        XCTAssertTrue(policy.isEligible(state, version: "1", now: now, interactionInProgress: false, attemptedThisSession: false))
        XCTAssertFalse(policy.isEligible(state, version: "1", now: now, interactionInProgress: true, attemptedThisSession: false))
        state.recordAttempt(version: "1", at: now)
        XCTAssertFalse(policy.isEligible(state, version: "2", now: now.addingTimeInterval(119 * 86_400), interactionInProgress: false, attemptedThisSession: false))
        XCTAssertTrue(policy.isEligible(state, version: "2", now: now.addingTimeInterval(120 * 86_400), interactionInProgress: false, attemptedThisSession: false))
        XCTAssertFalse(policy.isEligible(state, version: "1", now: now.addingTimeInterval(121 * 86_400), interactionInProgress: false, attemptedThisSession: false))
    }
}

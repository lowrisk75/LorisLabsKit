import XCTest
@testable import LorisSync

/// Covers the incremental-sync additions: change tokens, deletion propagation,
/// expired-token recovery, and the token store.
///
/// Before these, `LorisSync` could only re-download everything on every sync —
/// correct for one small profile, unusable for the apps that actually need to
/// sync (seven need push, four need change tokens).
final class IncrementalSyncTests: XCTestCase {

    private func record(_ id: String, _ text: String = "x") -> SyncRecord {
        SyncRecord(id: id, type: "Item", blob: Data(text.utf8), modifiedAt: Date())
    }

    // MARK: - Change tokens

    func testFirstFetchReturnsEverythingAndAToken() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("a"), record("b")])

        let changes = try await db.fetchChanges(type: "Item", since: nil)

        XCTAssertEqual(changes.changed.map(\.id), ["a", "b"])
        XCTAssertNotNil(changes.token, "a first fetch must hand back a token to resume from")
        XCTAssertFalse(changes.wasReset, "a first fetch is not a reset")
    }

    func testSecondFetchReturnsOnlyWhatChanged() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("a"), record("b")])
        let first = try await db.fetchChanges(type: "Item", since: nil)

        try await db.save([record("c")])
        let second = try await db.fetchChanges(type: "Item", since: first.token)

        XCTAssertEqual(second.changed.map(\.id), ["c"],
                       "the whole point: unchanged records must not come back")
    }

    func testNothingChangedYieldsAnEmptyDelta() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("a")])
        let first = try await db.fetchChanges(type: "Item", since: nil)

        let second = try await db.fetchChanges(type: "Item", since: first.token)

        XCTAssertTrue(second.changed.isEmpty)
        XCTAssertNotNil(second.token)
    }

    // MARK: - Deletions

    func testDeletionsPropagate() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("a"), record("b")])
        let first = try await db.fetchChanges(type: "Item", since: nil)

        try await db.delete(ids: ["a"], type: "Item")
        let second = try await db.fetchChanges(type: "Item", since: first.token)

        XCTAssertEqual(second.deletedIDs, ["a"],
                       "without deleted ids a record resurrects on the next upload")
        XCTAssertFalse(second.changed.contains { $0.id == "a" })
    }

    // MARK: - Expired token

    func testExpiredTokenForcesFlaggedFullSnapshot() async throws {
        let db = MockCloudDatabase()
        await db.seed([record("a"), record("b")])
        let first = try await db.fetchChanges(type: "Item", since: nil)

        await db.expireAllTokens()
        let after = try await db.fetchChanges(type: "Item", since: first.token)

        XCTAssertTrue(after.wasReset,
                      "callers must know this is a snapshot, not a delta")
        XCTAssertEqual(after.changed.map(\.id), ["a", "b"],
                       "an expired token must return everything, never a partial answer")
    }

    // MARK: - Subscriptions

    func testSubscriptionRegistrationIsIdempotent() async throws {
        let db = MockCloudDatabase()

        try await db.registerChangeSubscription(id: "zone-changes")
        try await db.registerChangeSubscription(id: "zone-changes")

        let ids = await db.registeredSubscriptionIDs
        XCTAssertEqual(ids, ["zone-changes"],
                       "registering at every launch must stay safe")
    }

    // MARK: - Account gating

    func testUnavailableAccountThrowsRatherThanReturningEmpty() async {
        let db = MockCloudDatabase()
        await db.setStatus(.noAccount)

        do {
            _ = try await db.fetchChanges(type: "Item", since: nil)
            XCTFail("an unusable account must throw, not look like an empty zone")
        } catch {
            XCTAssertEqual(error as? SyncError, .accountUnavailable)
        }
    }

    // MARK: - Token store

    func testTokenStoreRoundTripsAndClears() {
        let suite = "lorissync.tests.\(UUID().uuidString)"
        let store = UserDefaultsChangeTokenStore(suiteName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        XCTAssertNil(store.token(for: "zone"))

        store.setToken(Data([1, 2, 3]), for: "zone")
        XCTAssertEqual(store.token(for: "zone"), Data([1, 2, 3]))

        store.setToken(nil, for: "zone")
        XCTAssertNil(store.token(for: "zone"), "clearing must force a full resync")
    }

    func testTokensAreNamespacedPerKey() {
        let suite = "lorissync.tests.\(UUID().uuidString)"
        let store = UserDefaultsChangeTokenStore(suiteName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        store.setToken(Data([1]), for: "profiles")
        store.setToken(Data([2]), for: "alarms")

        XCTAssertEqual(store.token(for: "profiles"), Data([1]))
        XCTAssertEqual(store.token(for: "alarms"), Data([2]))
    }
}

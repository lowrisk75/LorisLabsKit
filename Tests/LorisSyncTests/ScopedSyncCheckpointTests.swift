import Foundation
import Testing
@testable import LorisSync

private enum ScopeFixtureError: Error { case unexpected }
private actor ScopedProvider: IncrementalCloudDatabase {
    private var calls = 0
    let token: Data?
    let cancel: Bool
    init(token: Data? = Data([1, 2, 3]), cancel: Bool = false) { self.token = token; self.cancel = cancel }
    func accountStatus() async -> SyncAccountStatus { .available }
    func save(_ records: [SyncRecord]) async throws { throw ScopeFixtureError.unexpected }
    func delete(ids: [String], type: String) async throws { throw ScopeFixtureError.unexpected }
    func fetchAll(type: String) async throws -> [SyncRecord] { throw ScopeFixtureError.unexpected }
    func registerChangeSubscription(id: String) async throws {}
    func fetchChanges(type: String, since token: Data?) async throws -> ZoneChanges {
        calls += 1
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        return ZoneChanges(token: self.token)
    }
    func count() -> Int { calls }
}

@Suite("Scoped checkpoint envelopes and fetch boundary, synthetic bytes")
struct ScopedSyncCheckpointTests {
    let scope = SyncOutboxScope(accountID: "fixture-account", namespace: "provider/container/private/owner/zone")
    @Test func encodedRoundTripRetainsExactTokenAndBindings() throws {
        let checkpoint = try ScopedSyncCheckpoint(scope: scope, recordType: "Profile", token: Data([1, 2, 255]))
        let restored = try ScopedSyncCheckpoint(restoring: checkpoint.encoded(), expectedScope: scope, recordType: "Profile")
        #expect(try restored.token(expectedScope: scope, recordType: "Profile") == Data([1, 2, 255]))
    }
    @Test func mismatchedScopeAndTypeAreRejectedWithoutRebinding() throws {
        let checkpoint = try ScopedSyncCheckpoint(scope: scope, recordType: "Profile", token: Data([1]))
        let bytes = try checkpoint.encoded()
        for other in [SyncOutboxScope(accountID: "other", namespace: scope.namespace),
                      SyncOutboxScope(accountID: scope.accountID, namespace: "other-zone")] {
            #expect(throws: CloudSyncCheckpointError.scopeMismatch) {
                try ScopedSyncCheckpoint(restoring: bytes, expectedScope: other, recordType: "Profile")
            }
            #expect(throws: CloudSyncCheckpointError.scopeMismatch) {
                try checkpoint.token(expectedScope: other, recordType: "Profile")
            }
        }
        #expect(throws: CloudSyncCheckpointError.scopeMismatch) {
            try checkpoint.token(expectedScope: scope, recordType: "Other")
        }
        #expect(try checkpoint.encoded() == bytes)
    }
    @Test func canonicalEquivalentScopeIsNotTheSameByteIdentity() throws {
        let a = SyncOutboxScope(accountID: "\u{00E9}", namespace: "zone")
        let b = SyncOutboxScope(accountID: "e\u{0301}", namespace: "zone")
        let checkpoint = try ScopedSyncCheckpoint(scope: a, recordType: "Item", token: Data([1]))
        #expect(throws: CloudSyncCheckpointError.scopeMismatch) {
            try ScopedSyncCheckpoint(restoring: checkpoint.encoded(), expectedScope: b, recordType: "Item")
        }
    }
    @Test func mismatchFailsBeforeAnyProviderCall() async throws {
        let provider = ScopedProvider()
        let checkpoint = try ScopedSyncCheckpoint(scope: scope, recordType: "Profile", token: Data([1]))
        await #expect(throws: CloudSyncCheckpointError.scopeMismatch) {
            try await provider.fetchScopedChanges(type: "Other", since: checkpoint, scope: scope)
        }
        #expect(await provider.count() == 0)
    }
    @Test(arguments: ["Profile", "Sealed"])
    func successfulFetchBindsReturnedCheckpoint(type: String) async throws {
        let provider = ScopedProvider()
        let first = try await provider.fetchScopedChanges(type: type, since: nil, scope: scope)
        #expect(try first.checkpoint.token(expectedScope: scope, recordType: type) == Data([1, 2, 3]))
        _ = try await provider.fetchScopedChanges(type: type, since: first.checkpoint, scope: scope)
        #expect(await provider.count() == 2)
    }
    @Test func missingTokenAndCancellationNeverReleaseAResult() async {
        let missing = ScopedProvider(token: nil)
        await #expect(throws: CloudSyncReadError.invalidCheckpoint) {
            try await missing.fetchScopedChanges(type: "Item", since: nil, scope: scope)
        }
        let task = Task {
            try await ScopedProvider(cancel: true).fetchScopedChanges(type: "Item", since: nil, scope: scope)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }
    @Test func malformedVersionAndCapacityNeverResetCheckpoint() throws {
        #expect(throws: CloudSyncReadError.invalidCheckpoint) {
            try ScopedSyncCheckpoint(restoring: Data("bad-json".utf8), expectedScope: scope, recordType: "Item")
        }
        #expect(throws: CloudSyncCheckpointError.capacityExceeded) {
            try ScopedSyncCheckpoint(restoring: Data(repeating: 0, count: 257), expectedScope: scope,
                                     recordType: "Item", maximumEncodedBytes: 256)
        }
        #expect(throws: CloudSyncReadError.invalidCheckpoint) {
            try ScopedSyncCheckpoint(scope: scope, recordType: "Item", token: Data())
        }
        let checkpoint = try ScopedSyncCheckpoint(scope: scope, recordType: "Item", token: Data([1]))
        var object = try #require(try JSONSerialization.jsonObject(with: checkpoint.encoded()) as? [String: Any])
        object["version"] = 2
        #expect(throws: CloudSyncReadError.invalidCheckpoint) {
            try ScopedSyncCheckpoint(restoring: JSONSerialization.data(withJSONObject: object),
                                     expectedScope: scope, recordType: "Item")
        }
        #expect(throws: CloudSyncCheckpointError.invalidLimits) {
            try ScopedSyncCheckpoint(scope: scope, recordType: "Item", token: Data([1]), maximumEncodedBytes: 0)
        }
    }
    @Test func diagnosticsRedactScopeAndToken() throws {
        let checkpoint = try ScopedSyncCheckpoint(scope: scope, recordType: "Profile", token: Data("fixture-secret".utf8))
        let description = String(reflecting: checkpoint)
        #expect(!description.contains("fixture-secret"))
        #expect(!description.contains(scope.accountID))
        #expect(!description.contains(scope.namespace))
    }
}

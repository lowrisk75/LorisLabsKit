import Foundation
import Testing
@testable import LorisSync

private actor PolicyEffects {
    private var effects = 0
    func lookup(_ id: String) -> String { effects += 1; return id }
    func remove(_ ids: [String]) { effects += 1 }
    func count() -> Int { effects }
}

@Suite("Physical data deletion policy, no provider")
struct SyncDeletionPolicyTests {
    @Test func defaultPolicyStopsBeforeLookupOrMutation() async {
        let effects = PolicyEffects()
        await #expect(throws: CloudSyncDeletionError.physicalDeletionDisabled) {
            try await SyncDeletionPreflight.perform(
                ids: ["a"], type: "Fixture", lookup: { await effects.lookup($0) },
                matchesIdentity: { $0 == $1 }, recordType: { _ in "Fixture" },
                remove: { await effects.remove($0) })
        }
        #expect(await effects.count() == 0)
    }
    @Test func explicitDisabledPolicyStopsBeforeLookupOrMutation() async {
        let effects = PolicyEffects()
        await #expect(throws: CloudSyncDeletionError.physicalDeletionDisabled) {
            try await SyncDeletionPreflight.perform(
                ids: ["a"], type: "Fixture", policy: .disabled,
                lookup: { await effects.lookup($0) }, matchesIdentity: { $0 == $1 },
                recordType: { _ in "Fixture" }, remove: { await effects.remove($0) })
        }
        #expect(await effects.count() == 0)
    }
    @Test func disabledEmptyDeletionRemainsNoOp() async throws {
        let effects = PolicyEffects()
        try await SyncDeletionPreflight.perform(
            ids: [String](), type: "Fixture", lookup: { await effects.lookup($0) },
            matchesIdentity: { $0 == $1 }, recordType: { _ in "Fixture" },
            remove: { await effects.remove($0) })
        #expect(await effects.count() == 0)
    }
}

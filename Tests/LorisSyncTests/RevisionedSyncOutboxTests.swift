import Foundation
import Testing
@testable import LorisSync

@Suite("Revision outbox invariants, synthetic payloads")
struct RevisionedSyncOutboxTests {
    let scope = SyncOutboxScope(accountID: "fixture-account-a", namespace: "fixture-provider/private/owner/zone")
    let key = SyncOutboxKey(recordType: "Profile", recordID: "fixture-id")

    @Test func exactAckIsIdempotentAndDoesNotResetRevision() throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        #expect(try journal.enqueue(.save(Data([1])), for: key, scope: scope) == 1)
        let session = try journal.beginSession(for: scope)
        let first = try #require(try journal.pending(using: session).first)
        #expect(try journal.acknowledge(first.receipt, using: session))
        #expect(try !journal.acknowledge(first.receipt, using: session))
        #expect(journal.pendingCount == 0)
        #expect(try journal.enqueue(.save(Data([2])), for: key, scope: scope) == 2)
    }

    @Test(arguments: [false, true])
    func staleAckNeverDeletesReplacement(deleteFirst: Bool) throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(deleteFirst ? .delete : .save(Data([1])), for: key, scope: scope)
        let session = try journal.beginSession(for: scope)
        let old = try #require(try journal.pending(using: session).first)
        let replacement: SyncOutboxOperation = deleteFirst ? .save(Data([2])) : .delete
        try journal.enqueue(replacement, for: key, scope: scope)
        #expect(try !journal.acknowledge(old.receipt, using: session))
        let current = try #require(try journal.pending(using: session).first)
        #expect(current.operation == replacement)
        #expect(current.receipt.revision == 2)
        #expect(current.receipt.mutationID != old.receipt.mutationID)
    }

    @Test func scopeMismatchCannotRebindOrEraseIntent() throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.delete, for: key, scope: scope)
        let before = try journal.encoded()
        let other = SyncOutboxScope(accountID: "fixture-account-b", namespace: scope.namespace)
        #expect(throws: SyncOutboxError.scopeMismatch) { try journal.beginSession(for: other) }
        #expect(throws: SyncOutboxError.scopeMismatch) { try journal.enqueue(.delete, for: key, scope: other) }
        #expect(throws: SyncOutboxError.scopeMismatch) {
            try RevisionedSyncOutbox(restoring: before, expectedScope: other)
        }
        #expect(try journal.encoded() == before)
    }

    @Test func namespaceAlsoBindsTheJournal() throws {
        let journal = try RevisionedSyncOutbox(scope: scope)
        let other = SyncOutboxScope(accountID: scope.accountID, namespace: "fixture-different-owner/zone")
        #expect(throws: SyncOutboxError.scopeMismatch) {
            try RevisionedSyncOutbox(restoring: journal.encoded(), expectedScope: other)
        }
    }

    @Test func suspensionRetainsIntentAndInvalidatesCallbacks() throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.delete, for: key, scope: scope)
        let oldSession = try journal.beginSession(for: scope)
        let old = try #require(try journal.pending(using: oldSession).first)
        journal.suspend()
        #expect(journal.pendingCount == 1)
        #expect(throws: SyncOutboxError.inactiveSession) { try journal.pending(using: oldSession) }
        let current = try journal.beginSession(for: scope)
        #expect(throws: SyncOutboxError.invalidReceipt) {
            try journal.acknowledge(old.receipt, using: current)
        }
        #expect(journal.pendingCount == 1)
    }

    @Test func ownerRestartBeginsNewSessionBeforeTransport() throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.save(Data([1])), for: key, scope: scope)
        let oldSession = try journal.beginSession(for: scope)
        let old = try #require(try journal.pending(using: oldSession).first)
        var recovered = try RevisionedSyncOutbox(restoring: journal.encoded(), expectedScope: scope)
        let newSession = try recovered.beginSession(for: scope) // Required lifecycle contract.
        #expect(throws: SyncOutboxError.inactiveSession) { try recovered.pending(using: oldSession) }
        #expect(throws: SyncOutboxError.invalidReceipt) {
            try recovered.acknowledge(old.receipt, using: newSession)
        }
        let current = try #require(try recovered.pending(using: newSession).first)
        #expect(current.receipt.mutationID == old.receipt.mutationID)
        #expect(try recovered.acknowledge(current.receipt, using: newSession))
    }

    @Test func sameOwnerTransactionReloadRetainsRuntimeToken() throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.delete, for: key, scope: scope)
        let session = try journal.beginSession(for: scope)
        let delivery = try #require(try journal.pending(using: session).first)
        var reload = try RevisionedSyncOutbox(restoring: journal.encoded(), expectedScope: scope)
        #expect(try reload.acknowledge(delivery.receipt, using: session))
    }

    @Test func independentJournalReceiptIsRejectedEvenForSameScopeAndKey() throws {
        var first = try RevisionedSyncOutbox(scope: scope)
        var second = try RevisionedSyncOutbox(scope: scope)
        try first.enqueue(.delete, for: key, scope: scope)
        try second.enqueue(.delete, for: key, scope: scope)
        let a = try first.beginSession(for: scope)
        let b = try second.beginSession(for: scope)
        let receipt = try #require(try second.pending(using: b).first).receipt
        #expect(throws: SyncOutboxError.invalidReceipt) { try first.acknowledge(receipt, using: a) }
        #expect(throws: SyncOutboxError.inactiveSession) { try first.pending(using: b) }
        #expect(first.pendingCount == 1)
    }

    @Test func typesDistinguishIdenticalRecordNamesAndEmptySaveIsNotDelete() throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.save(Data()), for: key, scope: scope)
        try journal.enqueue(.delete, for: .init(recordType: "Other", recordID: key.recordID), scope: scope)
        let session = try journal.beginSession(for: scope)
        let pending = try journal.pending(using: session)
        #expect(pending.count == 2)
        #expect(pending[0].operation == .save(Data()))
        #expect(pending[1].operation == .delete)
    }

    @Test func capacityFailureIsAtomicAndReplacementAtCapacityWorks() throws {
        let limits = SyncOutboxLimits(maximumPendingMutations: 1, maximumPayloadBytes: 8)
        var journal = try RevisionedSyncOutbox(scope: scope, limits: limits)
        try journal.enqueue(.save(Data([1])), for: key, scope: scope)
        let before = try journal.encoded()
        #expect(throws: SyncOutboxError.capacityExceeded) {
            try journal.enqueue(.delete, for: .init(recordType: "Other", recordID: "2"), scope: scope)
        }
        #expect(try journal.encoded() == before)
        #expect(try journal.enqueue(.delete, for: key, scope: scope) == 2)
    }

    @Test func payloadAndEncodedLimitsNeverPartiallyAdvanceState() throws {
        var limited = try RevisionedSyncOutbox(
            scope: scope, limits: .init(maximumPayloadBytes: 2))
        let before = try limited.encoded()
        #expect(throws: SyncOutboxError.capacityExceeded) {
            try limited.enqueue(.save(Data([1, 2, 3])), for: key, scope: scope)
        }
        #expect(try limited.encoded() == before)
        var sample = try RevisionedSyncOutbox(scope: scope)
        try sample.enqueue(.save(Data(repeating: 7, count: 32)), for: key, scope: scope)
        let cap = try sample.encoded().count - 1
        var encodedLimited = try RevisionedSyncOutbox(
            scope: scope, limits: .init(maximumEncodedBytes: cap))
        let empty = try encodedLimited.encoded()
        #expect(throws: SyncOutboxError.capacityExceeded) {
            try encodedLimited.enqueue(.save(Data(repeating: 7, count: 32)), for: key, scope: scope)
        }
        #expect(try encodedLimited.encoded() == empty)
    }

    @Test func invalidIdentifiersAndLimitsAreRefused() throws {
        for account in ["", " ", "bad\naccount"] {
            #expect(throws: SyncOutboxError.invalidIdentifier) {
                try RevisionedSyncOutbox(scope: .init(accountID: account, namespace: "fixture"))
            }
        }
        #expect(throws: SyncOutboxError.invalidLimits) {
            try RevisionedSyncOutbox(scope: scope, limits: .init(maximumPendingMutations: 0))
        }
        var journal = try RevisionedSyncOutbox(scope: scope, limits: .init(maximumIdentifierBytes: 64))
        #expect(throws: SyncOutboxError.invalidIdentifier) {
            try journal.enqueue(.delete, for: .init(recordType: "T", recordID: String(repeating: "é", count: 33)),
                                scope: scope)
        }
        #expect(journal.pendingCount == 0)
    }

    @Test func oversizedOrMalformedStateIsNeverSilentlyReset() throws {
        #expect(throws: SyncOutboxError.capacityExceeded) {
            try RevisionedSyncOutbox(restoring: Data(repeating: 0, count: 1_025), expectedScope: scope,
                                     limits: .init(maximumEncodedBytes: 1_024))
        }
        #expect(throws: SyncOutboxError.invalidState) {
            try RevisionedSyncOutbox(restoring: Data("not-json".utf8), expectedScope: scope)
        }
    }

    @Test func unsupportedSnapshotVersionIsNotAdopted() throws {
        let journal = try RevisionedSyncOutbox(scope: scope)
        var object = try json(journal)
        object["version"] = 2
        #expect(throws: SyncOutboxError.unsupportedVersion) {
            try restore(object)
        }
    }

    @Test(arguments: 0..<7)
    func malformedMutationInvariantsAreRejected(variant: Int) throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.delete, for: key, scope: scope)
        try journal.enqueue(.save(Data([1])), for: .init(recordType: "Other", recordID: "2"), scope: scope)
        var object = try json(journal)
        var rows = try #require(object["mutations"] as? [[String: Any]])
        switch variant {
        case 0: rows[1]["key"] = rows[0]["key"]
        case 1: rows[1]["revision"] = rows[0]["revision"]
        case 2: rows[1]["mutationID"] = rows[0]["mutationID"]
        case 3: rows[0]["kind"] = "unsupported"
        case 4: rows[0]["payload"] = "AQ=="
        case 5: rows[0]["revision"] = 0
        default: rows[0]["revision"] = 999
        }
        object["mutations"] = rows
        #expect(throws: SyncOutboxError.invalidState) { try restore(object) }
    }

    @Test func revisionExhaustionDoesNotWrapOrMutate() throws {
        var object = try json(RevisionedSyncOutbox(scope: scope))
        object["lastRevision"] = NSNumber(value: UInt64.max)
        var journal = try restore(object)
        let before = try journal.encoded()
        #expect(throws: SyncOutboxError.revisionExhausted) {
            try journal.enqueue(.delete, for: key, scope: scope)
        }
        #expect(try journal.encoded() == before)
    }

    @Test func pendingIsRevisionOrderedAndBounded() throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.delete, for: key, scope: scope)
        try journal.enqueue(.delete, for: .init(recordType: "Other", recordID: "2"), scope: scope)
        try journal.enqueue(.save(Data([3])), for: key, scope: scope)
        let session = try journal.beginSession(for: scope)
        #expect(try journal.pending(using: session, limit: 1).map(\.receipt.revision) == [2])
        #expect(throws: SyncOutboxError.invalidLimit) { try journal.pending(using: session, limit: 0) }
    }

    @Test func descriptionsRedactScopeKeysAndPayload() throws {
        var journal = try RevisionedSyncOutbox(scope: scope)
        let operation = SyncOutboxOperation.save(Data("fixture-sensitive-marker".utf8))
        try journal.enqueue(operation, for: key, scope: scope)
        let session = try journal.beginSession(for: scope)
        let delivery = try #require(try journal.pending(using: session).first)
        let descriptions = [String(reflecting: scope), String(reflecting: key),
                            String(reflecting: journal), String(reflecting: operation),
                            String(reflecting: session), String(reflecting: delivery),
                            String(reflecting: delivery.receipt)]
        for value in descriptions {
            #expect(!value.contains(scope.accountID))
            #expect(!value.contains(key.recordID))
            #expect(!value.contains("fixture-sensitive-marker"))
        }
    }

    @Test func profileAndPresealedPayloadShapesRoundTripWithoutDomainRewriting() throws {
        let profile = Data(#"{"id":"profile","label":"fixture"}"#.utf8)
        let presealedShape = Data([0xA1, 0xF2, 0x00, 0x7E]) // Synthetic, not encryption proof.
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.save(profile), for: key, scope: scope)
        try journal.enqueue(.save(presealedShape), for: .init(recordType: "Sealed", recordID: "2"), scope: scope)
        let session = try journal.beginSession(for: scope)
        let restored = try RevisionedSyncOutbox(restoring: journal.encoded(), expectedScope: scope)
        #expect(try restored.pending(using: session).map(\.operation) == [.save(profile), .save(presealedShape)])
    }

    @Test(arguments: [false, true])
    func opaqueKeyIdentityUsesExactUTF8(typeVariant: Bool) throws {
        let composed = "\u{00E9}"
        let decomposed = "e\u{0301}"
        let a = SyncOutboxKey(recordType: typeVariant ? composed : "T", recordID: typeVariant ? "id" : composed)
        let b = SyncOutboxKey(recordType: typeVariant ? decomposed : "T", recordID: typeVariant ? "id" : decomposed)
        #expect(a != b)
        #expect(Set([a, b]).count == 2)
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.delete, for: a, scope: scope)
        try journal.enqueue(.save(Data([2])), for: b, scope: scope)
        #expect(journal.pendingCount == 2)
        let session = try journal.beginSession(for: scope)
        var restored = try RevisionedSyncOutbox(restoring: journal.encoded(), expectedScope: scope)
        let rows = try restored.pending(using: session)
        #expect(rows.count == 2)
        let first = try #require(rows.first)
        #expect(Array(first.receipt.key.recordType.utf8) == Array(a.recordType.utf8))
        #expect(Array(first.receipt.key.recordID.utf8) == Array(a.recordID.utf8))
        #expect(try restored.acknowledge(first.receipt, using: session))
        #expect(restored.pendingCount == 1)
        #expect(try restored.pending(using: session).first?.receipt.key == b)
    }

    @Test(arguments: [false, true])
    func opaqueScopeIdentityUsesExactUTF8(namespaceVariant: Bool) throws {
        let a = SyncOutboxScope(accountID: namespaceVariant ? "account" : "\u{00E9}",
                                namespace: namespaceVariant ? "\u{00E9}" : "zone")
        let b = SyncOutboxScope(accountID: namespaceVariant ? "account" : "e\u{0301}",
                                namespace: namespaceVariant ? "e\u{0301}" : "zone")
        #expect(a != b)
        #expect(Set([a, b]).count == 2)
        var journal = try RevisionedSyncOutbox(scope: a)
        let before = try journal.encoded()
        #expect(throws: SyncOutboxError.scopeMismatch) { try journal.beginSession(for: b) }
        #expect(throws: SyncOutboxError.scopeMismatch) { try journal.enqueue(.delete, for: key, scope: b) }
        #expect(throws: SyncOutboxError.scopeMismatch) {
            try RevisionedSyncOutbox(restoring: before, expectedScope: b)
        }
        #expect(try journal.encoded() == before)
    }

    @Test func inactiveCapacityReservesSessionAndRejectsLegacyFullState() throws {
        let payload = Data(repeating: 7, count: 128)
        var sample = try RevisionedSyncOutbox(scope: scope)
        try sample.enqueue(.save(payload), for: key, scope: scope)
        let offlineBytes = try sample.encoded()
        let limits = SyncOutboxLimits(maximumEncodedBytes: offlineBytes.count)
        var limited = try RevisionedSyncOutbox(scope: scope, limits: limits)
        let before = try limited.encoded()
        #expect(throws: SyncOutboxError.capacityExceeded) {
            try limited.enqueue(.save(payload), for: key, scope: scope)
        }
        #expect(try limited.encoded() == before)
        #expect(throws: SyncOutboxError.capacityExceeded) {
            try RevisionedSyncOutbox(restoring: offlineBytes, expectedScope: scope, limits: limits)
        }
    }

    @Test func reservedExactCapacitySurvivesSuspendRestoreAndActivation() throws {
        let payload = Data(repeating: 7, count: 128)
        var sample = try RevisionedSyncOutbox(scope: scope)
        try sample.enqueue(.save(payload), for: key, scope: scope)
        _ = try sample.beginSession(for: scope)
        let cap = try sample.encoded().count
        let limits = SyncOutboxLimits(maximumEncodedBytes: cap)
        var journal = try RevisionedSyncOutbox(scope: scope, limits: limits)
        try journal.enqueue(.save(payload), for: key, scope: scope)
        let token = try journal.beginSession(for: scope)
        #expect(try journal.encoded().count == cap)
        journal.suspend()
        let before = try journal.encoded()
        #expect(throws: SyncOutboxError.capacityExceeded) {
            try journal.enqueue(.save(payload + Data([1, 2, 3])), for: key, scope: scope)
        }
        #expect(try journal.encoded() == before)
        var restored = try RevisionedSyncOutbox(restoring: before, expectedScope: scope, limits: limits)
        let current = try restored.beginSession(for: scope)
        #expect(throws: SyncOutboxError.inactiveSession) { try restored.pending(using: token) }
        #expect(try restored.pending(using: current).count == 1)
    }

    private func json(_ journal: RevisionedSyncOutbox) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: journal.encoded()) as? [String: Any])
    }
    private func restore(_ object: [String: Any]) throws -> RevisionedSyncOutbox {
        try RevisionedSyncOutbox(restoring: JSONSerialization.data(withJSONObject: object), expectedScope: scope)
    }
}

import Foundation
import SwiftData
import Testing
@testable import LorisSync

@Model final class SaveProbeNote {
    var title: String
    init(title: String) { self.title = title }
}

/// Real SQLite stores: one writable, one reopened with `allowsSave: false` so
/// `save()` is refused the way a full disk or a locked store refuses it.
@Suite(.serialized) struct ModelContextSaveReportingTests {
    private func storeURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LorisSyncSaveReporting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("probe.store")
    }

    private func container(_ url: URL, allowsSave: Bool) throws -> ModelContainer {
        try ModelContainer(
            for: SaveProbeNote.self,
            configurations: ModelConfiguration(url: url, allowsSave: allowsSave, cloudKitDatabase: .none)
        )
    }

    /// Creates the file with one saved row, then reopens it read-only.
    private func readOnlyContext() throws -> (ModelContext, URL) {
        let url = try storeURL()
        do {
            let writable = ModelContext(try container(url, allowsSave: true))
            writable.insert(SaveProbeNote(title: "existing"))
            try writable.save()
        }
        return (ModelContext(try container(url, allowsSave: false)), url)
    }

    private func titles(at url: URL) throws -> [String] {
        let context = ModelContext(try container(url, allowsSave: true))
        return try context.fetch(FetchDescriptor<SaveProbeNote>()).map(\.title).sorted()
    }

    @Test func successfulSavePersistsAndKeepsObjects() throws {
        let url = try storeURL()
        let context = ModelContext(try container(url, allowsSave: true))
        let note = SaveProbeNote(title: "new")
        context.insert(note)

        try context.saveReporting(removingOnFailure: [note])

        #expect(try titles(at: url) == ["new"])
        #expect(context.saveOutcome(removingOnFailure: []) == .saved)
    }

    @Test func refusedSaveThrowsAndRemovesOnlyCallerInsertions() throws {
        let (context, _) = try readOnlyContext()
        let unrelated = SaveProbeNote(title: "someone else's draft")
        context.insert(unrelated)
        let mine = SaveProbeNote(title: "mine")
        context.insert(mine)

        #expect(throws: (any Error).self) {
            try context.saveReporting(removingOnFailure: [mine])
        }

        let pending = context.insertedModelsArray.compactMap { $0 as? SaveProbeNote }.map(\.title)
        #expect(!pending.contains("mine"))
        // Never a global rollback: other pending work stays for its owner to handle.
        #expect(pending.contains("someone else's draft"))
    }

    @Test func refusedSaveIsReportedAsOutcome() throws {
        let (context, url) = try readOnlyContext()
        let mine = SaveProbeNote(title: "mine")
        context.insert(mine)

        let outcome = context.saveOutcome(removingOnFailure: [mine])

        #expect(!outcome.isSaved)
        #expect(outcome.error != nil)
        #expect(!context.insertedModelsArray.contains { ($0 as? SaveProbeNote)?.title == "mine" })
        // The store is untouched.
        #expect(try titles(at: url) == ["existing"])
    }

    @Test func refusedSaveCallsReporter() throws {
        let (context, _) = try readOnlyContext()
        let mine = SaveProbeNote(title: "mine")
        context.insert(mine)
        var reported: [String] = []

        _ = context.saveOutcome(removingOnFailure: [mine]) { error in
            reported.append(String(describing: type(of: error)))
        }

        #expect(reported.count == 1)
    }

    @Test func alreadySavedObjectsAreNotDeletedOnFailure() throws {
        let (context, url) = try readOnlyContext()
        let existing = try #require(try context.fetch(FetchDescriptor<SaveProbeNote>()).first)
        existing.title = "edited"
        let mine = SaveProbeNote(title: "mine")
        context.insert(mine)

        // Passing a persisted object by mistake must not schedule its deletion.
        _ = context.saveOutcome(removingOnFailure: [mine, existing])

        #expect(context.deletedModelsArray.isEmpty)
        #expect(try titles(at: url) == ["existing"])
    }
}

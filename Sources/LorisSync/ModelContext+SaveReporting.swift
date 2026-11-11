import Foundation
import SwiftData

/// Result of `ModelContext.saveOutcome(removingOnFailure:report:)`.
public enum SaveOutcome: Sendable, CustomStringConvertible {
    case saved
    /// The store refused the save. The caller's insertions were removed from
    /// the context; nothing else was rolled back.
    case refused(any Error)

    public var isSaved: Bool {
        if case .saved = self { true } else { false }
    }

    public var error: (any Error)? {
        if case .refused(let error) = self { error } else { nil }
    }

    public var description: String {
        switch self {
        case .saved: "saved"
        case .refused(let error): "refused(\(error))"
        }
    }
}

extension SaveOutcome: Equatable {
    /// Two refusals compare equal whatever their errors: the outcome is what
    /// callers branch on. Inspect `error` for the cause.
    public static func == (lhs: SaveOutcome, rhs: SaveOutcome) -> Bool {
        lhs.isSaved == rhs.isSaved
    }
}

public extension ModelContext {
    /// Saves, and on refusal removes the objects this call inserted before
    /// rethrowing — the replacement for `try? context.save()`, which loses the
    /// refusal and leaves the rejected objects pending in the context.
    ///
    /// Only `insertedByCaller` objects that are still unsaved insertions are
    /// removed. Already-persisted objects, other callers' pending insertions and
    /// pending edits are left alone: this is never a global `rollback()`.
    /// Edits the caller made to existing objects stay pending; undo them
    /// yourself if they must not be retried with the next save.
    ///
    /// - Throws: the error `save()` threw.
    func saveReporting(removingOnFailure insertedByCaller: [any PersistentModel]) throws {
        do {
            try save()
        } catch {
            removePendingInsertions(insertedByCaller)
            throw error
        }
    }

    /// Non-throwing form of `saveReporting(removingOnFailure:)` for UI state:
    /// returns the outcome and passes a refusal to `report` (log it, surface it).
    @discardableResult
    func saveOutcome(
        removingOnFailure insertedByCaller: [any PersistentModel],
        report: ((any Error) -> Void)? = nil
    ) -> SaveOutcome {
        do {
            try saveReporting(removingOnFailure: insertedByCaller)
            return .saved
        } catch {
            report?(error)
            return .refused(error)
        }
    }

    private func removePendingInsertions(_ models: [any PersistentModel]) {
        guard !models.isEmpty else { return }
        let pending = Set(insertedModelsArray.map(\.persistentModelID))
        var removed = false
        for model in models where pending.contains(model.persistentModelID) {
            delete(model)
            removed = true
        }
        // Deleting an unsaved insertion only cancels it out once pending
        // changes are processed; until then it is listed as both inserted and
        // deleted. Processing coalesces change tracking — it saves nothing and
        // rolls nothing back.
        if removed { processPendingChanges() }
    }
}

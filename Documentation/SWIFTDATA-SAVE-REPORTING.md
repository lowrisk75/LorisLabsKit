# LorisSync — sauvegardes SwiftData qui signalent les refus / SwiftData saves that report refusals

## Français

`try? context.save()` avale le refus du magasin (disque plein, magasin en lecture seule, contrainte violée) : l'interface croit la donnée enregistrée et les objets refusés restent en attente dans le contexte. Le motif est répandu dans le portfolio (Clasp, Éclair, iot-framework, 404, recensement du 2026-11-04). Synthesis l'a corrigé localement dans `ChatService.persistMessage` (`ChatSendOutcome`) ; ce helper en est la forme partagée.

- `try context.saveReporting(removingOnFailure: [objets insérés par l'appelant])` : en cas d'échec, supprime du contexte **uniquement** ces objets s'ils sont encore des insertions non enregistrées, puis relance l'erreur.
- `context.saveOutcome(removingOnFailure:report:) -> SaveOutcome` : même contrat sans `throws`, pour l'état d'interface ; `report` reçoit l'erreur (journal, message à l'utilisateur).

Jamais de `rollback()` global : les insertions d'autres appelants et les modifications en attente restent. Les modifications que l'appelant a faites sur des objets existants restent aussi en attente ; à lui de les annuler si elles ne doivent pas repartir avec la prochaine sauvegarde. Un objet déjà enregistré passé par erreur n'est pas supprimé.

Le helper appelle `processPendingChanges()` après suppression : sans cela SwiftData liste l'objet à la fois inséré et supprimé. Cet appel ne sauvegarde rien et n'annule rien.

Tests : magasin SQLite réel, rouvert avec `allowsSave: false` (`Tests/LorisSyncTests/ModelContextSaveReportingTests.swift`, macOS). Aucune app n'est migrée ; aucune qualification appareil n'est revendiquée.

## English

`try? context.save()` swallows the store's refusal (full disk, read-only store, violated constraint): the UI believes the data is stored and the refused objects stay pending in the context.

```swift
import LorisSync

let record = ChatMessageRecord(...)
context.insert(record)
switch context.saveOutcome(removingOnFailure: [record], report: { ErrorReporter.shared.report($0) }) {
case .saved: break
case .refused: showSaveFailure() // keep the user's draft; nothing was stored
}

// Or, in throwing code:
try context.saveReporting(removingOnFailure: [conversation, record])
```

Contract:

- On refusal, only the listed objects that are still unsaved insertions are removed; the error is rethrown (or returned as `.refused`).
- Never a global `rollback()`: other callers' insertions and all pending edits are left alone. Undo your own edits to existing objects if they must not be retried by the next save.
- `processPendingChanges()` runs after the removal so the insertion cancels out; it saves and rolls back nothing.
- `SaveOutcome` equality compares only saved vs refused; read `error` for the cause.

Not covered: a SwiftLint `no_try_optional_save` rule (proposed in the SDK feedback, not shipped here), app migrations, device or CloudKit-backed store qualification.

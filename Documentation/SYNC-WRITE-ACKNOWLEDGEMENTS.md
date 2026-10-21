# LorisSync — acquittements de transport / transport acknowledgements

## Français

Évolution locale non publiée du produit existant LorisSync, propriétaire LorisLabsKit. Aucun produit Foundation supplémentaire, aucune migration d'app. Minimums OS et signatures CloudDatabase/IncrementalCloudDatabase/SharedCloudDatabase inchangés.

Chaque mutation native vérifie les résultats retournés : toutes les identités demandées doivent apparaître exactement une fois dans la bonne catégorie (sauvegarde/suppression), sans résultat inattendu. Les erreurs par item et erreurs globales sont propagées. Les sauvegardes vérifient aussi l'identité du record, de la zone, de l'abonnement ou du partage retourné. CloudSyncWriteError expose invalidMutation, incompleteAcknowledgement et mismatchedSavedIdentity, sans identifiant ni contenu sensible.

L'exécuteur interne refuse les requêtes dupliquées ou contradictoires avant dispatch ; une requête vide ne déclenche aucun appel. L'annulation est vérifiée avant dispatch. Une confirmation complète reste une confirmation si l'annulation arrive pendant l'opération : le SDK ne prétend pas annuler une écriture déjà commise. Il n'effectue ni replay automatique ni suppression compensatoire.

ensureZone propage maintenant les erreurs au lieu de continuer après une préparation non confirmée. Les erreurs serverRejectedRequest ne signifient plus « abonnement existant ». L'acceptation ne transforme plus alreadyShared en succès générique : des métadonnées déjà accepted sont un no-op explicite ; sinon le résultat d'acceptation doit confirmer le partage attendu. La création de partage lit son URL/participants depuis le CKShare serveur acquitté, pas l'objet local non sauvegardé.

**Une erreur ne signifie pas absence d'effets distants.** L'API historique retourne Void, pas un rapport durable des succès partiels. Garder l'intention locale et réconcilier avant toute nouvelle tentative. Ne pas vider une outbox simplement à partir d'un ACK d'ID : une édition plus récente peut exister. Les ACK de version, mutationID/révision, CAS et transaction avec l'état métier restent au lot outbox. La politique savePolicy existante est conservée ; ceci n'ajoute pas de résolution de conflit.

Validation locale : 14 nouvelles méthodes Swift Testing, dont paramètres supplémentaires, avec 36 méthodes Sync précédentes ; 50 méthodes Debug et Release. Les fixtures contrôlent le même exécuteur que le code natif et la propagation jusqu'à CloudSyncEngine, mais n'instancient pas CKContainer et n'exécutent pas les branches CloudKit. Les séquences natives réelles, la fraîcheur des métadonnées accepted et les cas d'idempotence restent à qualifier sur hôte signé.

Limites restantes : erreurs/ambiguïtés de lookup du partage, identité zone+owner absente de SyncRecord, portée type des suppressions, mapping de schéma, token invalide, compte changé entre awaits, blocage/réentrance du moteur, stockage transactionnel durable, reprise après crash, conflits/CAS, qualification CloudKit/appareil/production. Aucune garantie d'effacement réglementaire ou de zéro risque. Le lot lecture précédent reste documenté dans SYNC-READ-INTEGRITY.md ; ses limitations historiques ensureZone/ACK sont remplacées uniquement dans le périmètre décrit ici.

## English

Local/unreleased change to LabsKit-owned LorisSync; no new Foundation product, app migration, protocol signature or platform-minimum change.

Native mutations now require exact save/delete result-key coverage, propagate item/global failures and verify returned saved-object identities. Setup errors are no longer ignored. Generic subscription rejection/alreadyShared errors are not success signals; explicitly accepted metadata is a no-op. Share creation uses the acknowledged server share's URL and participants.

The internal executor rejects duplicate/overlapping requests before dispatch, avoids empty operations, checks pre-dispatch cancellation and never replays or compensates automatically. A confirmed mutation is not falsely described as rolled back solely because cancellation arrived during its completion.

**Failure does not prove zero remote effects.** The legacy Void API is not a durable partial-result journal. Keep local intent and reconcile before retrying. Identity ACK is not exact-version ACK: local mutation revisions, atomic outbox/domain storage, CAS, account ownership and crash recovery remain open.

Fourteen new synthetic methods plus 36 existing Sync methods pass Debug/Release. They exercise the shared executor and profile engine propagation, not native CloudKit accounts/network. Signed-host acceptance metadata freshness/idempotence, share lookup/zone identity/type scope, schema, concurrency/conflict/account boundaries, provider/device and release qualification remain separate. No production or security certification is implied.

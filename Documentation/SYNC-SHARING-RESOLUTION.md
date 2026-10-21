# LorisSync — résolution sûre du partage / fail-closed sharing resolution

## Français

Évolution locale du produit LabsKit existant. Signatures publiques et minimums OS inchangés, aucune app migrée. CloudSyncSharingError ajoute ambiguousRecord, recordTypeMismatch, inconsistentMetadata et lookupLimitExceeded.

Un lookup retourne nil uniquement pour CKError.unknownItem. Réseau, droits, résultat mal formé et annulation sont des erreurs, pas « aucun partage ». Un root trouvé doit garder l'identité native attendue et le type demandé. Une référence de partage doit rester dans sa zone et résoudre un CKShare cohérent avec URL ; une référence cassée n'autorise pas la création d'un autre partage.

ShareInfo.isOwner dépend du rôle explicite de currentUserParticipant. L'absence de participant ou un rôle inconnu/non pris en charge refuse la décision ; deux identifiants optionnels absents ne sont jamais preuve de propriété. Les nouveaux rôles SDK, dont administrator, ne sont pas automatiquement assimilés à owner sous cette API minimale.

stopSharing cherche d'abord une racine unique parmi la base privée configurée et les zones partagées visibles. Une racine privée non partagée compte aussi comme collision : aucune priorité implicite vers un autre partage. La suppression ne commence qu'après le scan réussi. Erreur de zone/lookup, ambiguïté, zone répétée ou plus de1 000 zones : refus, pas suppression du premier résultat. Une révocation privée exige le rôle owner ; quitter via sharedDatabase exige un participant connu et accepté. La suppression cible la référence native complète du partage et conserve la validation ACK du lot précédent.

fetchShared refuse les IDs courts dupliqués, puisque SyncRecord ne peut pas représenter leurs zones/propriétaires. Ceci refuse des configurations ambiguës ; cela ne remplace pas une future API d'identité qualifiée. Une erreur de résolution des métadonnées d'acceptation est propagée au lieu d'être toujours convertie en invalidShare.

Fixtures :18 nouvelles méthodes Swift Testing, callbacks synthétiques et compteurs d'effets, avec classification NSError CloudKit sans CKContainer ni compte. Elles couvrent erreurs/annulation, scan incomplet, collisions et ordre d'énumération, rôles, limites et absence de replay. Les callsites CloudKit réels ne sont pas exécutés par ces fixtures.

**Limites :** unicité dans le snapshot visible, pas preuve globale ou transactionnelle. Un changement de compte, de rôle ou de partage entre lookup et mutation reste une race ; pas de CAS/autorité acquise pour toujours. CloudKit applique encore ses droits au moment de l'opération. Métadonnées natives, entitlements, références/hiérarchies réelles, erreurs et rôle accepté nécessitent un hôte signé. Cible : racines des hiérarchies de partage de cette API historique, pas une nouvelle API générale pour les partages de zone. Une erreur de suppression peut suivre un effet distant : pas de rollback/replay implicite.

Outbox durable par révision, transaction avec l'état métier, binding compte, conflits/CAS/crash, schéma, tokens et portée du type dans delete restent ouverts. Aucun audit intégral ou certificat de sécurité/production n'est revendiqué.

## English

Local LabsKit-owned LorisSync improvement; no app migration, protocol signature or platform-minimum change.

Only explicit unknownItem becomes absence. Transport/permission/malformed/cancellation failures propagate. Root identity/type and referenced share zone/identity/metadata are validated. Ownership follows the known current participant role, never equality of optional user IDs.

Removal first resolves a unique root across the configured private namespace and visible shared zones. An unshared private shadow also counts. Failed/incomplete scans, collisions, duplicate zones or the1,000-zone budget refuse before removal. Private revoke requires owner; shared leave requires a known accepted participant. Native share IDs and transport-ACK validation remain pinned. Duplicate short IDs in shared fetches fail rather than conflate zones.

Eighteen new synthetic methods cover policy/effect ordering; native provider branches are compiled, not executed. Visibility is not a transactional ownership guarantee: account/role/target races, native metadata and entitlements remain separate signed-host gates. The legacy hierarchy-root API is not full zone-sharing support. No rollback or automatic replay is promised. Durable revision outbox/CAS/account/crash/schema/token/type-delete gates and independent audit remain open.

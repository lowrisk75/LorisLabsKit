# LorisSync — précontrôle des suppressions / deletion preflight

## Français

CloudKitDatabase.delete(ids:type:) ne transmet plus aveuglément les IDs. Avant toute mutation, le helper interne valide la requête puis lit chaque record ; identité retournée et type UTF-8 exact doivent correspondre. Tout échec de lecture, identité/type incohérent ou annulation avant envoi empêche le lot entier de partir : aucun préfixe validé n'est supprimé. Requête vide : aucune lecture/mutation ; doublons/type blanc : erreur. Erreurs spécifiques : CloudSyncDeletionError.recordTypeMismatch et inconsistentIdentity. Les erreurs fournisseur restent propagées, y compris unknownItem : aucune absence transformée en succès.

Après validation complète : un seul lot passe au validateur d'ACK existant. Aucun replay/compensation automatique. Une erreur après dispatch peut suivre des effets distants ; une annulation tardive ne fabrique pas un rollback. Les lectures supplémentaires augmentent le coût/latence et peuvent faire échouer des appels qui supprimaient auparavant sans vérifier le type. Ne pas réessayer aveuglément ni effacer les intentions locales sur erreur.

**Ce n'est PAS une suppression conditionnelle atomique.** Les API natives examinées suppriment par CKRecord.ID, sans précondition de type/change-tag. savePolicy concerne les sauvegardes ; l'atomicité d'un lot ne joint pas sa prélecture. Un autre writer peut supprimer/recréer l'ID entre les deux. Compte/changement de zone et suppressions en cascade restent des gates distinctes. NO-GO d'adoption si l'appelant exige une protection atomique contre ce remplacement. Un protocole de coordination serveur/domaine, tombstones/CAS ou refus explicite de suppression physique demanderait une décision séparée ; aucun de ces changements n'est imposé ici.

Aucun changement de signature du protocole, de schéma ou des minimums OS. Une tombstone métier authentifiée de coffre n'est pas remplacée par une suppression physique. Aucune app migrée.13méthodes Swift Testing via callbacks synthétiques, sans CKContainer, compte, réseau ou fichiers ; elles prouvent le garde-fou local, pas le comportement CloudKit réel. Pas d'audit global/SOTA/release certificate.

## English

Before any physical deletion, the existing CloudKit adapter now reads every requested record and verifies returned identity and exact UTF-8 record type. Lookup/type/identity/cancellation failures prevent the entire batch from dispatching, not just the failing suffix. Empty requests do nothing; duplicate IDs/blank types fail. New errors: CloudSyncDeletionError.recordTypeMismatch/inconsistentIdentity. Provider errors, including unknownItem, propagate without invented success.

One mutation batch follows a complete preflight and uses the existing exact acknowledgement validator. No automatic retry/compensation or false late-cancellation rollback. Extra reads add cost/latency and can expose errors previously ignored. Preserve pending local intent and reconcile after a post-dispatch error.

**Preflight is NOT atomic expected-type/generation deletion.** Examined native APIs delete by ID; savePolicy governs saves, and batch atomicity does not include prior reads. Concurrent delete/recreation, account transitions and cascade effects remain unqualified. Adoption is NO-GO when atomic replacement protection is required. Server/domain coordination, tombstone/CAS protocols or disabling physical deletion would require a separate compatibility decision.

No existing protocol signature/schema/minimum-OS change and no app migration. Physical deletion is not authenticated domain tombstoning.13synthetic callback tests have no container/account/network/files and do not establish provider/runtime/security/release qualification.

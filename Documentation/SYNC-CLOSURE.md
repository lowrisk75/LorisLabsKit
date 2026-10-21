# LorisSync — clôture d'intégrité / integrity closure

## Français

### Suppression physique bloquée par défaut (changement de comportement)

`CloudKitDatabase` prend un paramètre `physicalDeletionPolicy: CloudSyncPhysicalDeletionPolicy`, par défaut `.disabled`. Dans ce mode, `delete(ids:type:)` (et donc `CloudSyncEngine.delete`) lève `CloudSyncDeletionError.physicalDeletionDisabled` avant toute construction d'ID natif ou appel fournisseur. Une requête vide reste un no-op.

Le préflight décrit dans [SYNC-DELETION-PREFLIGHT.md](SYNC-DELETION-PREFLIGHT.md) n'est plus le comportement par défaut : il exige `.allowNonAtomicPreflight`, choix explicite de compatibilité. Il reste **non atomique** (type/génération non garantis au moment du delete). `stopSharing` est une opération distincte, non soumise à cette politique.

**Migration :** un appelant qui supprimait des données doit soit passer `.allowNonAtomicPreflight` en acceptant ce TOCTOU, soit adopter un protocole de tombstone/coordination côté domaine.

### Une opération à la fois par moteur

`CloudSyncEngine` réserve un verrou couvrant tout `push`/`pull`/`delete`/`reconcile`, pris avant le premier `await` et libéré en `defer`. Un appel concurrent sur la même instance lève `CloudSyncOperationError.operationInProgress` : pas de file, pas de rejeu. Corrige la réentrance où un `reconcile` suspendu pouvait réécrire un ancien état après un `push`. Le verrou est local à l'instance : il ne protège ni plusieurs instances/processus/appareils, ni l'absence de CAS serveur. L'annulation est vérifiée entre les étapes mais n'annule pas une écriture déjà envoyée.

### Profil unique et identité

`pull`/`reconcile` refusent plus d'un record distant (`CloudSyncPayloadError.ambiguousProfiles`), un type différent ou une date non finie (`invalidRecord`), un ID distant différent de l'ID local ou un payload décodé dont l'`id` ne correspond pas au record (`inconsistentIdentity`). Les comparaisons se font octet par octet en UTF-8.

### Identités opaques en octets UTF-8

Le collecteur de pages indexe les IDs par `Data(id.utf8)` et non par `String`, qui fusionnait des IDs canoniquement équivalents mais d'octets différents (risque de perte d'une mutation avec avancement du checkpoint). Les chaînes d'origine sont conservées. L'acceptation de telles paires par CloudKit n'a pas été testée.

### Validation sortante

Avant construction native : ID non blanc et sans caractère de contrôle, IDs uniques par lot ; noms de type et de champ limités au sous-ensemble ASCII `[A-Za-z][A-Za-z0-9_]*` ; champs système/réservés refusés (dont `modifiedAt`) ; dates et doubles finis. Erreur : `CloudSyncValidationError.invalidRecord` (doublon : `CloudSyncWriteError.invalidMutation`). Ce sous-ensemble est un choix de l'adaptateur, pas une affirmation sur ce que CloudKit accepte.

### Permission d'un partage existant

`share(recordID:type:permission:)` vérifie la permission publique effective d'un partage existant et celle du partage acquitté. Une différence lève `CloudSyncSharePermissionError.existingPermissionMismatch` : aucune révocation ni recréation implicite.

### Checkpoint lié à un scope (`ScopedSyncCheckpoint`)

Enveloppe JSON versionnée liant le token opaque à un `SyncOutboxScope` et un type ; limites de taille (256 o à 128 Mio, défaut 8 Mio) ; restauration vérifiant version/scope/type/limites (le décodeur JSON standard ignore toutefois les clés inconnues et ne rejette pas les clés dupliquées) ; description et réflexion (`dump`/`Mirror`) expurgées. `fetchScopedChanges(type:since:scope:)` est additive et vérifie le scope **avant** l'appel fournisseur.

Le scope est fourni et vérifié par l'hôte : **ce n'est pas une authentification du compte natif**. Le namespace doit qualifier fournisseur/container/base/zone/propriétaire ; l'hôte doit arrêter le dispatch lors d'un changement de compte. Pas de MAC, chiffrement ni anti-rollback ; pas de migration automatique d'un token brut. `IncrementalSync` (token brut, non scopé) reste disponible.

### Suites de la revue finale (2026-10-21)

- **Révocation par le propriétaire :** `revokeOwnedShare(recordID:type:)` ne consulte que la base privée. Un participant ne peut plus bloquer la révocation en faisant accepter un partage portant le même nom. `leaveShare(recordID:type:)` ne consulte que les zones partagées et ne touche jamais les records privés. `stopSharing` (ancienne API) refuse toujours l'ambiguïté. Depuis les décisions SOTA ci-dessous, elles font aussi partie du protocole `SharedCloudDatabase`.
- Unicité et tri des IDs de `fetchShared` en octets UTF-8 ; types de record comparés octet par octet. Conséquence : deux IDs canoniquement équivalents mais d'octets différents sont désormais retournés tous les deux au lieu d'être refusés. L'égalité `SyncRecord ==` et tout dictionnaire `String` côté app les fusionneront : l'hôte doit indexer par octets.
- `reconcile` refuse un `localModifiedAt` non fini (`CloudSyncPayloadError.invalidRecord`).
- `ShareInfo` (URL = capacité d'accès) et `SyncRecord` (payload) ont une description et une réflexion expurgées, comme les types outbox et checkpoint.

### Décisions SOTA (2026-10-21, validées par l'utilisateur)

- **Partage sur invitation par défaut (comportement modifié).** `ShareAccess.invitedOnly` (`publicPermission = .none`) est le défaut de `share(recordID:type:title:)` ; le lien public exige `access: .anyoneWithLink(permission)`. L'ancienne `share(…permission:)` est dépréciée. Les participants sont ajoutés par nom via la feuille système : `CloudKitDatabase.shareItem(…)` renvoie un `SyncShareItem` pour SwiftUI `ShareLink` (`CKShareTransferRepresentation`, invitation seulement proposée). iOS/macOS/visionOS uniquement ; pas de feuille de partage sur tvOS/watchOS. Un partage existant d'un autre accès lève `existingPermissionMismatch`.
- **Options OS 26 (désactivées par défaut) :** `SyncShareOptions(allowsParticipantsToInviteOthers:allowsAccessRequests:)`, ignorées avant OS 26. Le rôle administrateur est reconnu comme participant non propriétaire.
- **Protocole :** `revokeOwnedShare`/`leaveShare` sont désormais des exigences de `SharedCloudDatabase` ; `stopSharing` est déprécié.
- **Compare-and-set serveur.** `VersionedCloudDatabase` : `fetchVersioned(type:id:)` lit un record par ID (cohérence forte) et renvoie `missing`, `found` ou `unreadable(version)` ; `fetchVersioned(type:)` sert seulement à la découverte (requête indexée, peut être en retard). `SyncRecordVersion` est opaque (ID du record + change tag + champs système archivés), égalité par ID et change tag, expurgée. **La stocker en lieu protégé** : décodage en secure coding, rejet si ID/tag ne correspondent pas ou si une référence `parent` apparaît. `save(_:expecting:)` utilise `.ifServerRecordUnchanged` (`nil` = création seulement) ; les champs fournis remplacent ceux du serveur, **les champs non fournis sont conservés** (compatibilité avec les versions plus récentes) ; `replacingAllFields: true` supprime tous les autres champs : c'est la seule façon d'effacer un champ. Les records avec `parent` (hiérarchies) sont refusés dès la lecture. Un écart lève `CloudSyncConflictError.serverRecordChanged(current:)`. `CloudSyncEngine.synchronize(local:base:hasLocalChanges:)` lit par ID dès que le record est connu et ne s'appuie sur aucune horloge : `upToDate`, `pushed`, `adoptRemote` (à n'appliquer que si la copie locale n'a pas changé pendant l'appel), `conflict` (rien n'est écrit ; l'hôte fusionne puis resynchronise avec `base: remoteVersion`), `remoteDeleted` ou `remoteUnreadable(remoteVersion:)` (contenu ou payload illisible, rien n'est écrit ; l'écraser exige `base: remoteVersion` et fait un remplacement complet ; ne jamais stocker cette version comme base habituelle). Au premier sync (`base: nil`), un profil existant sous un autre ID est refusé (`inconsistentIdentity`) au lieu d'en créer un second ; un record existant illisible fait échouer ce premier sync. Une suppression locale passe par `delete`, pas `local: nil`. `reconcile` et `push` (écriture sans CAS) sont dépréciés ; ne pas les mélanger avec `synchronize`.
- **Migration des partages publics existants :** `share()` lève `existingPermissionMismatch` pour un ancien lien public ; `updateShareAccess(recordID:type:access:)` (propriétaire, compare-and-set) le passe en `.invitedOnly` sans le révoquer. Les personnes déjà entrées par le lien gardent probablement leur accès (non vérifié) : les retirer via la feuille de partage d'Apple.
- **Changements cassants à la compilation :** l'exigence `share(…permission:)` devient `share(…access:)` ; `revokeOwnedShare`, `leaveShare`, `fetchSharedReport`, `updateShareAccess` et `fetchVersioned(type:id:)` sont de nouvelles exigences de protocole sans implémentation par défaut. Les conformances externes (mocks d'app) doivent être mises à jour.
- **Quarantaine des records illisibles.** `CloudSyncReadPolicy.quarantineUnreadable` (défaut) : `fetchChanges`/`fetchScopedChanges` livrent les records valides, listent les illisibles dans `quarantined` (ID + raison, sans contenu) et avancent le checkpoint. Un record en quarantaine **n'est pas une suppression** : garder la copie locale et signaler. Les erreurs de transport/permission échouent toujours. `fetchSharedReport` fait de même pour le partage ; `fetchShared`, `fetchAll` et la découverte `fetchVersioned(type:)` restent stricts ; `fetchVersioned(type:id:)` renvoie `.unreadable`. `.strict` rétablit l'échec complet.

**Limites :** comportement CloudKit réel (change tags, `serverRecordChanged`, feuille de partage, rôles OS 26) non testé sur compte ni appareil ; tests sur mock en mémoire et objets natifs hors ligne.

### Validation et limites

191 méthodes ciblées en Debug et en Release (29 XCTest, 162 Swift Testing dont SQLite réel) le 2026-10-21, plus builds génériques iOS/tvOS/watchOS/visionOS Simulator. Callbacks/fixtures synthétiques : aucun compte CloudKit, appareil signé, partage multi-utilisateur, ni qualification release. Aucune app migrée.

## English

### Physical deletion disabled by default (behaviour change)

`CloudKitDatabase` takes `physicalDeletionPolicy: CloudSyncPhysicalDeletionPolicy`, defaulting to `.disabled`. In that mode `delete(ids:type:)` (and therefore `CloudSyncEngine.delete`) throws `CloudSyncDeletionError.physicalDeletionDisabled` before any native ID or provider call. Empty requests remain a no-op.

The preflight described in [SYNC-DELETION-PREFLIGHT.md](SYNC-DELETION-PREFLIGHT.md) is no longer the default: it requires `.allowNonAtomicPreflight`, an explicit compatibility choice. It is still **not atomic** (type/generation are not guaranteed at delete time). `stopSharing` is a separate operation and is not governed by this policy.

**Migration:** callers that delete data must either pass `.allowNonAtomicPreflight` and accept that TOCTOU, or adopt a domain tombstone/coordination protocol.

### One operation at a time per engine

`CloudSyncEngine` holds a lease over each whole `push`/`pull`/`delete`/`reconcile`, taken before the first `await` and released in `defer`. An overlapping call on the same instance throws `CloudSyncOperationError.operationInProgress`: no queue, no replay. This fixes the reentrancy where a suspended `reconcile` could overwrite newer state after a `push`. The lease is instance-local: it does not cover multiple instances/processes/devices or the lack of server CAS. Cancellation is checked between steps but cannot undo a dispatched write.

### Single profile and identity

`pull`/`reconcile` reject more than one remote record (`CloudSyncPayloadError.ambiguousProfiles`), a mismatched type or non-finite timestamp (`invalidRecord`), and a remote ID differing from the local ID or a decoded payload whose `id` differs from its record (`inconsistentIdentity`). Comparisons are byte-exact UTF-8.

### Opaque identities as UTF-8 bytes

The page collector keys IDs by `Data(id.utf8)` instead of `String`, which merged canonically equivalent IDs with different bytes (risk of losing a mutation while advancing the checkpoint). Original strings are kept. Whether CloudKit accepts such pairs is untested.

### Outgoing validation

Before native construction: non-blank IDs without control characters, unique per batch; type and field names limited to the ASCII subset `[A-Za-z][A-Za-z0-9_]*`; system/reserved fields rejected (including `modifiedAt`); finite dates and doubles. Error: `CloudSyncValidationError.invalidRecord` (duplicates: `CloudSyncWriteError.invalidMutation`). The subset is this adapter's choice, not a claim about what CloudKit accepts.

### Existing share permission

`share(recordID:type:permission:)` checks the effective public permission of an existing share and of the acknowledged share. A mismatch throws `CloudSyncSharePermissionError.existingPermissionMismatch`: no implicit revoke or re-create.

### Scope-bound checkpoint (`ScopedSyncCheckpoint`)

Versioned JSON envelope binding the opaque token to a `SyncOutboxScope` and record type; size limits (256 B to 128 MiB, default 8 MiB); restore checks version/scope/type/limits (the standard JSON decoder still ignores unknown keys and does not reject duplicate keys); redacted description and reflection (`dump`/`Mirror`). `fetchScopedChanges(type:since:scope:)` is additive and checks the scope **before** the provider call.

The scope is supplied and verified by the host: **it does not authenticate the native account**. The namespace must qualify provider/container/database/zone/owner, and the host must stop dispatch on account change. No MAC, encryption or rollback protection; no automatic migration of raw tokens. `IncrementalSync` (raw, unscoped token) remains available.

### Final review follow-ups (2026-10-21)

- **Owner revocation:** `revokeOwnedShare(recordID:type:)` looks only at the private database, so a participant can no longer block revocation by getting a same-name share accepted. `leaveShare(recordID:type:)` looks only at shared zones and never touches private records. Legacy `stopSharing` still refuses ambiguity. Since the SOTA decisions below, they are also `SharedCloudDatabase` requirements.
- `fetchShared` uniqueness and ordering use UTF-8 bytes; record types are compared byte-exactly. Consequence: two canonically equivalent but byte-distinct IDs are now both returned instead of refused. `SyncRecord ==` and any app-side `String`-keyed collection will merge them, so hosts must key by bytes.
- `reconcile` rejects a non-finite `localModifiedAt` (`CloudSyncPayloadError.invalidRecord`).
- `ShareInfo` (URL is a bearer capability) and `SyncRecord` (payload) have redacted description and reflection, like the outbox and checkpoint types.

### SOTA decisions (2026-10-21, user-approved)

- **Invite-only sharing by default (behaviour change).** `ShareAccess.invitedOnly` (`publicPermission = .none`) is the default of `share(recordID:type:title:)`; a public link requires `access: .anyoneWithLink(permission)`. The old `share(…permission:)` is deprecated. Participants are added by name in the system sheet: `CloudKitDatabase.shareItem(…)` returns a `SyncShareItem` for SwiftUI `ShareLink` (`CKShareTransferRepresentation`, specified recipients only). iOS/macOS/visionOS only; tvOS/watchOS have no share sheet. An existing share with another access throws `existingPermissionMismatch`.
- **OS 26 options (off by default):** `SyncShareOptions(allowsParticipantsToInviteOthers:allowsAccessRequests:)`, ignored before OS 26. The administrator role is recognised as a non-owner participant.
- **Protocol:** `revokeOwnedShare`/`leaveShare` are now `SharedCloudDatabase` requirements; `stopSharing` is deprecated.
- **Server compare-and-set.** `VersionedCloudDatabase`: `fetchVersioned(type:id:)` reads one record by ID (strongly consistent) and returns `missing`, `found` or `unreadable(version)`; `fetchVersioned(type:)` is for discovery only (index-backed query, may lag). `SyncRecordVersion` is opaque (record ID + change tag + archived system fields), equality by ID and change tag, redacted. **Store it in protected storage**: decoding uses secure coding and rejects an ID/tag mismatch or an injected `parent` reference. `save(_:expecting:)` uses `.ifServerRecordUnchanged` (`nil` = create only); provided fields replace server values, **fields not provided are preserved** (forward compatible with newer clients); `replacingAllFields: true` removes every other field and is the only way to clear a field. Records with a `parent` (hierarchies) are refused at read time. A mismatch throws `CloudSyncConflictError.serverRecordChanged(current:)`. `CloudSyncEngine.synchronize(local:base:hasLocalChanges:)` reads by ID whenever the record is known and uses no clocks: `upToDate`, `pushed`, `adoptRemote` (apply only if the host copy did not change during the call), `conflict` (nothing written; host merges, then synchronizes with `base: remoteVersion`), `remoteDeleted`, or `remoteUnreadable(remoteVersion:)` (content or payload unreadable, nothing written; overwriting requires `base: remoteVersion` and is a full replacement; never store this version as the routine base). On first sync (`base: nil`) an existing profile under another ID is refused (`inconsistentIdentity`) instead of creating a second one; an existing unreadable record fails that first sync. Local deletion goes through `delete`, not `local: nil`. `reconcile` and `push` (writes without CAS) are deprecated; do not mix them with `synchronize`.
- **Migrating existing public shares:** `share()` throws `existingPermissionMismatch` for a legacy public link; `updateShareAccess(recordID:type:access:)` (owner, compare-and-set) switches it to `.invitedOnly` without revoking it. People who already joined through the link probably keep access (unverified): remove them in Apple's share sheet.
- **Source-breaking changes:** the `share(…permission:)` requirement becomes `share(…access:)`; `revokeOwnedShare`, `leaveShare`, `fetchSharedReport`, `updateShareAccess` and `fetchVersioned(type:id:)` are new protocol requirements without default implementations. External conformers (app mocks) must be updated.
- **Unreadable-record quarantine.** `CloudSyncReadPolicy.quarantineUnreadable` (default): `fetchChanges`/`fetchScopedChanges` deliver valid records, list unreadable ones in `quarantined` (ID + reason, no content) and advance the checkpoint. A quarantined record is **not a deletion**: keep the local copy and flag it. Transport/permission errors still fail. `fetchSharedReport` does the same for sharing; `fetchShared`, `fetchAll` and discovery `fetchVersioned(type:)` stay strict; `fetchVersioned(type:id:)` returns `.unreadable`. `.strict` restores whole-read failure.

**Limits:** real CloudKit behaviour (change tags, `serverRecordChanged`, share sheet, OS 26 roles) untested on an account or device; tests use the in-memory mock and offline native objects.

### Validation and limits

191 targeted methods in Debug and Release (29 XCTest, 162 Swift Testing including real SQLite) on 2026-10-21, plus generic iOS/tvOS/watchOS/visionOS Simulator builds. Synthetic callbacks/fixtures only: no CloudKit account, signed device, multi-user sharing or release qualification. No app migrated.

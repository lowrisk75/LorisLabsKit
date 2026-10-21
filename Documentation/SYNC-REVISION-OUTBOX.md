# LorisSync — journal d'outbox versionné / revision outbox

## Français

Le journal vit dans le produit existant LorisSync (LabsKit). Aucun nouveau produit/dépendance runtime, aucune migration d'app. Il n'écrit aucun fichier et ne lance aucun transport : sa durabilité dépend d'une transaction du stockage métier hôte.

### API et stockage

- SyncOutboxScope(accountID:namespace:) fixe un compte authentifié et un keyspace pleinement qualifié (provider/container/database/zone/owner). Le SDK ne vérifie pas l'identité du fournisseur. Ne pas transformer ces chaînes en chemins.
- SyncOutboxKey(recordType:recordID:) distingue les types dans ce scope. Les identifiants sont opaques, non normalisés, bornés en UTF-8 ; contrôles/blancs seuls refusés.
- RevisionedSyncOutbox.enqueue(_:for:scope:) garde la dernière intention locale par clé, avec révision UInt64 persistée et mutationID neuf. Les limites sont validées sur un candidat avant publication ; échec = état/révision inchangés.
- encoded() et init(restoring:expectedScope:limits:) sérialisent un format versionné, refusent scope/version/structure/limites invalides sans reset silencieux.
- beginSession(for:), suspend(), pending(using:limit:) et acknowledge(_:using:) bornent les callbacks. Un ACK ne retire que la mutation exacte (journal+scope+session+clé+révision+mutationID). Ancienne révision : false sans effacement. Mauvaise session/reçu : erreur.

Exemple des primitives seulement, **pas une transaction durable complète** :

```swift
let scope = SyncOutboxScope(accountID: verifiedAccountID, namespace: qualifiedNamespace)
var candidate = try RevisionedSyncOutbox(scope: scope)
try candidate.enqueue(.save(protectedPayload), for: key, scope: scope)
let bytes = try candidate.encoded()
// Dans UNE transaction hôte : mutation métier + bytes, puis commit.
// Publier candidate en mémoire seulement après le succès du commit.
```

Tous les writers doivent sérialiser et recharger l'état courant dans cette transaction ; ne pas réécrire depuis un cache périmé. Pour ACK, persister retrait exact + system fields/métadonnées métier ensemble. Capturer le SyncOutboxDelivery AVANT dispatch et conserver son reçu : ne jamais reconstruire l'ACK depuis une recherche pending effectuée après la réponse. Le transport doit confirmer la requête réellement envoyée.

Aucun adaptateur SwiftData/SQLite de production n'est imposé. SwiftData doit stocker le blob dans son propre modèle/transaction ; SQLite peut le stocker dans sa transaction métier existante. Le harnais de référence est uniquement dans Tests/LorisSyncTests/OutboxSQLiteTransactionTests.swift et ne modifie aucune app.

### Compte, processus et concurrence

Un journal ne change jamais de compte/namespace. Suspendre conserve l'intention de A sans l'envoyer à B ; routage, quarantaine ou effacement explicite restent des décisions hôte. Arrêter transport/callbacks immédiatement lors d'un compte indisponible/changé, même si la persistance échoue. Rester arrêté tant que la transition du compte vérifié et de sa nouvelle session n'a pas commité.

Sur CHAQUE démarrage de propriétaire runtime/processus, commencer une nouvelle session vérifiée et la persister avant dispatch. Le sessionID est stocké pour les reloads transactionnels du même propriétaire ; le token de session n'est ni Codable ni publiquement constructible. Décoder seul n'autorise pas l'envoi. La valeur Sendable n'est pas un verrou, un acteur transactionnel ou un CAS interprocessus ; copier/rejouer un ancien snapshot/token contrevient au contrat.

La coalescence locale n'ordonne pas les écritures serveur. Single-flight par clé, sauvegardes conditionnelles, conflits/ancêtres et authenticité des tombstones restent au transport/domaine. .delete est une intention de suppression de transport, pas une tombstone E2EE : un coffre doit préserver son protocole et transmettre sa tombstone authentifiée comme payload approprié. Pas de replay automatique ni promesse exactly-once/rollback distant. Aucun branchement automatique à CloudSyncEngine ou CKSyncEngine.

### Sécurité et limites

Descriptions redigées sans scope/clé/payload. En revanche encoded() contient ces données : ce n'est PAS du chiffrement, de l'intégrité cryptographique, une protection anti-rollback ou un effacement sécurisé. L'hôte doit protéger DB/WAL/backups, autorité d'accès, révocation et rétention. Ne pas stocker des secrets en clair en supposant que le journal les protège.

Limites par défaut :1 024 intentions,1MiB/payload,8MiB encodés,1 024 octets UTF-8/identifiant. Configurations positives bornées validées à l'initialisation ; octets acceptés ne sont pas un plafond RSS/CPU du décodeur. UInt64 épuisé refuse au lieu de reboucler. Le format journal n'est pas un protocole réseau ou un JSON à convertir via nombres JavaScript.

Les quatre champs d'identité (compte, namespace, type, ID) sont comparés/hachés par octets UTF-8 exacts, pas par équivalence canonique Unicode. Le fournisseur reste responsable de sa propre correspondance ; ne pas normaliser silencieusement. Deux anciennes intentions déjà coalescées ne peuvent pas être reconstruites par ce correctif.

La limite encodée réserve aussi le champ de session actif, même hors ligne. Construction, ajout et restauration vérifient cette représentation canonique avant acceptation. Un ancien journal sans cette réserve peut lever capacityExceeded à la restauration : conserver ses octets, arrêter le dispatch et prévoir une récupération explicite (limite accrue dans les bornes, ou migration hôte validée). À la borne absolue, augmenter la limite n'est pas possible. Aucun reset, purge ou abandon d'intention automatique.

Tests ajoutés :23 méthodes d'invariants et5 méthodes SQLite (cas paramétrés supplémentaires). La suite SQLite nécessite LORIS_SYNC_OUTBOX_TEST_ROOT vers un dossier dédié créé/enregistré par Throttle selon les règles locales ; sans variable, elle est explicitement désactivée, sans dossier temporaire implicite. Les fichiers sont synthétiques et restent dans ce dossier de preuve. Commit, rollback, close sans commit et réouverture sont testés ; close n'est pas un kill de processus, panne électrique ou test réel SwiftData/CloudKit.

NO-GO adoption sans intégration transactionnelle réelle de l'hôte, coordination des writers et lifecycle compte, protection au repos, protocole serveur/CAS/conflits, tests kill/recovery et audit indépendant/natif approprié. Aucun certificat de sécurité/SOTA/release à partir de ces fixtures.

## English

RevisionedSyncOutbox is a synchronous transaction-owned value in existing LorisSync, not a separate file store or automatic transport. Persist its bounded versioned bytes with the domain mutation in ONE host transaction; publish candidate memory state after commit. Serialize/reload every writer. Production SwiftData/SQLite adapters and apps are not modified.

A fixed authenticated account/fully qualified namespace and typed key bind intent. Fresh mutation IDs and monotonic revisions prevent a captured stale receipt from removing a replacement. Capture deliveries before dispatch; acknowledge only their actual confirmed request, never a later pending lookup. Exact ACK plus server/domain metadata must commit atomically. Coalescing does not provide remote ordering/CAS or authenticated tombstones.

Stop transport/callbacks immediately on account change even if persistence fails; do not resume until a verified new session transition commits. Begin a fresh runtime session on every owner/process start. Persisted session IDs support same-owner transaction reload, not authorization from decoded bytes. Tokens are not Codable/publicly constructible; stale caches, copied snapshots and multiple writers still need host coordination.

Encoding contains identifiers/payloads and is NOT encryption, authenticated storage, anti-rollback, secure deletion or a memory/RSS bound. Host protects DB/WAL/backups and account retention. Descriptions redact content. No automatic retry, remote rollback, exactly-once or provider qualification.

All four identity fields compare/hash exact UTF-8 bytes, not Unicode canonical equivalence. Provider mapping remains host-owned; do not silently normalize. Already coalesced older intent cannot be recovered by this fix.

Encoded capacity reserves an active session field even while offline. Construction, enqueue and restore validate canonical activation capacity. Legacy full inactive bytes may now throw capacityExceeded: preserve those bytes, stop dispatch and use explicit host recovery (bounded larger limits or a validated migration). At the absolute cap, limits cannot increase. Never reset, purge or silently drop intent.

Twenty-three invariant methods and five test-only SQLite methods cover local policy and a real single-database transaction/reopen contract. SQLite requires an explicit registered LORIS_SYNC_OUTBOX_TEST_ROOT; otherwise that suite is disabled without implicit temp files. Abandoned-transaction close is not process-kill/power-loss proof. Real host lifecycle/storage, account/provider, crash/concurrency/security and release gates remain open.

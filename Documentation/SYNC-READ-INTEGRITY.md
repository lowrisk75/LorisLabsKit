# LorisSync — lecture complète ou erreur / complete reads or failure

## Français

LorisSync reste le produit du dépôt LorisLabsKit ; aucun LorisSync concurrent n'est créé dans Foundation. Cette évolution locale ne migre aucune app et ne change ni signatures de protocoles ni minimums OS.

fetchAll et fetchShared suivent les queryCursor jusqu'à la dernière page. Une erreur de page, de zone partagée ou d'élément est propagée, jamais convertie en snapshot vide/partiel. Un record attendu sans modifiedAt est refusé via CloudSyncReadError.invalidRecord, au lieu d'être omis. Les champs non pris en charge restent une limite du mapping historique, pas une promesse de schéma complet.

fetchChanges draine moreComing en mémoire et ne rend le token qu'après succès de toutes les pages et de son encodage. Les suppressions sont filtrées sur recordType. Le dernier événement entre pages pour un ID prévaut ; modification/suppression contradictoire ou ID dupliqué au sein d'une page non ordonnée provoque conflictingChanges. Un échec ne doit jamais autoriser l'hôte à effacer ses données locales ou avancer son checkpoint.

Le collecteur interne vérifie l'annulation avant/après chaque fetch et refuse plus de 1 000 pages (paginationLimitExceeded). Ce plafond borne les pages acceptées, pas le RSS ni le coût natif. fetchAll reste une API en mémoire, pas une API de streaming ou un snapshot transactionnel serveur. L'annulation ne révoque pas une mutation déjà commise ; ce lot concerne les lectures.

Tests : 10 méthodes Swift Testing sur pages synthétiques et 26 méthodes XCTest existantes sur mocks, Debug/Release. Aucun CKContainer, compte, appel CloudKit réel ou appareil n'est utilisé par ces fixtures. Le code de branchement natif compile mais n'est pas exécuté dans ces tests. Les fixtures de formes blob/typed ne sont pas des apps importées ni des preuves d'adoption.

Gates restantes : tests signés de pagination/partial failure/token expiré, changements de compte/zone, collision d'identité entre zones partagées ; intégrité des écritures par item, ensureZone et partage ; stockage local transactionnel, outbox/ACK exacts, CAS/conflits et récupération après crash. Ne pas activer le SDK en production sur la seule base de ce lot. Les consommateurs doivent garder leurs anciennes données quand une lecture échoue.

## English

LorisSync remains LabsKit-owned. Existing protocol signatures/platform minimums stay unchanged; no apps are migrated.

Private/shared queries drain cursors and propagate item/page/zone failures instead of returning a partial success. Missing required modifiedAt metadata fails explicitly. Zone changes drain moreComing before exposing a checkpoint, filter deletion types and fold successive page events. Contradictory/duplicate identities within an unordered page fail rather than inventing an order. Hosts must not erase local state or advance tokens on failure.

The internal collector checks cancellation around each fetch and caps reads at 1,000 accepted pages. This is neither an allocation bound nor a streaming/transactional server snapshot guarantee. Existing unsupported-field mapping remains a limitation.

Ten new Swift Testing methods plus 26 existing mock XCTest methods cover local contracts in Debug/Release. Native wiring compiles but is not executed by these fixtures. Signed CloudKit, shared-zone identity, account changes, per-item write ACK, local durability/CAS/conflicts/crash recovery and release remain separate open gates. No remote release or adoption qualification is implied.

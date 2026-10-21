# LorisSync — checkpoint decoding / décodage des jetons

## Français

CloudKitDatabase.fetchChanges(type:since:) distingue désormais l'absence de jeton (Data? = nil, première lecture) d'un jeton présent mais illisible. Archive vide, invalide, racine d'une autre classe ou racine décodée nil : CloudSyncReadError.invalidCheckpoint. Le décodage NSSecureCoding reste limité à CKServerChangeToken, avant ensureZone ou lecture distante ; annulation vérifiée avant/après décodage. Pas de log du jeton ni des erreurs d'archive contenant éventuellement des métadonnées.

L'hôte conserve le jeton et les données d'origine sur erreur. Ne pas attraper cette erreur pour effacer silencieusement le jeton ou les données et recommencer. Une récupération explicite doit vérifier compte, container, base, zone, type, conservation des intentions locales et transaction données+checkpoint. La simple réussite du décodage ne prouve aucune de ces identités ni la fraîcheur. Aucun nouveau format, stockage ou limite de taille opaque arbitraire ; le décodeur natif n'est pas un budget RSS/CPU garanti contre un stockage hostile.

Le chemin existant de CKError.changeTokenExpired reste distinct : une seule nouvelle lecture depuis nil, résultat complet marqué wasReset=true uniquement après succès. Ce correctif ne qualifie pas ce comportement fournisseur ni la politique d'adoption/suppression de l'app. Format d'archive existant, signatures publiques et minimums OS préservés. Un appel qui récupérait auparavant silencieusement une archive corrompue renverra maintenant une erreur explicite.

Cinq méthodes Swift Testing locales (cas paramétrés supplémentaires) appellent le décodeur réellement utilisé par l'adaptateur, avec Foundation/CloudKit importés mais sans CKContainer, compte ou réseau. Elles ne fabriquent pas de CKServerChangeToken valide : Apple fournit ces objets côté serveur. Le round-trip d'un vrai jeton et l'expiration réelle restent à qualifier. Aucune migration d'app, publication ou certificat de sécurité global.

## English

CloudKitDatabase.fetchChanges now distinguishes missing bytes (nil, first fetch) from present invalid checkpoint data. Empty/malformed archives, wrong root class or a decoded nil root throw CloudSyncReadError.invalidCheckpoint. Secure decoding remains restricted to CKServerChangeToken and precedes zone setup/remote reads, with cancellation checks before/after decoding. No archive/token content is logged by this code.

Hosts must preserve original checkpoint/domain bytes on error. Do not silently clear data/tokens and restart. Explicit recovery must verify account/container/database/zone/type, protect pending local intent and atomically persist fetched data+checkpoint. Successful decoding alone proves neither scope nor freshness. No new wire/storage format or arbitrary opaque-token size limit; native decoding is not a hostile-storage RSS/CPU guarantee.

The existing explicit server changeTokenExpired path remains a single full-read retry, marked wasReset=true only on complete success. Provider behavior and host reset/adoption policy are not qualified by this patch. Public signatures/minimum OS versions are unchanged; corrupted archives now fail instead of silently restarting.

Five local Swift Testing methods exercise the actual adapter decoder with synthetic archives and native framework imports, without container/account/network access. Valid server-token round-trip, provider expiry/account behavior, host transaction/storage security and release readiness remain open. No app migration or global audit clearance.

# SiliconPass — checkpoint SDK du 6 octobre 2026

État final au **6 octobre 2026 à 14:42 Europe/Paris** : candidat minimal local séparé ; aucune adoption ni activation de production. **27 tests SDK, 16 tests de contrat CRM et 6 tests UI mobiles passent. UI macOS bloquée par provisioning/Gatekeeper.**

Le handoff `SiliconPass/Docs/SUPPORT-SDK-COORDINATION-2026-10-06.md` a été lu. Les copies concurrentes ne sont pas poursuivies dans SiliconPass. Le candidat se trouve dans `/Users/kevin/GitHub/LorisLabsKit/Qualification/SiliconPassSupport-20261006/`.

Révision candidate finale : `8fabdca451caf1088e40bda25fd73012eef74dc5e734f39174ca2296b9638064` ; 36 fichiers contrôlés.

## Révision et périmètre

Le candidat repart des 12 sources/resources du snapshot adapté contrôlé du 5 octobre, restaurées depuis les sauvegardes uniquement après comparaison avec `previousAdaptedSnapshot20261005`. L’original courant de SiliconPass est conservé. Le parent est documenté dans `PARENT.json` ; toutes les sources compilées, resources, tests, fixtures et spécification du banc sont inventoriés dans `PROVENANCE.json`, avec vérificateur read-only `verify-candidate.py`.

Cette révision ne contient aucun diagnostic, journal, assistant, notification, MetricKit ou dépendance coffre/crypto/broker/extension/watch. Elle conserve le support text-only, appID exact, client partagé, groupe Keychain support explicite device-only/non synchronisé, gates de livraison false par défaut et aide historique. Aucun droit Apple ou App Group de SiliconPass n’a été changé.

Le transport annule pendant la réception dès dépassement de la borne déclarée ou constatée, avec un buffer borné et aucun fichier téléchargé. Le choix de callbacks de données suit le contrat [Apple URLSessionDataDelegate](https://developer.apple.com/documentation/foundation/urlsessiondatadelegate). URLSession conserve HTTPS/URL exacte, refus des redirections, absence de cookies/cache/credentials, limites distinctes et annulation/timeout. La session injectée fournit seulement une configuration assainie, pas son delegate.

Les réponses/actions confirmées survivent à la relance dans une queue privée support, sans tracking token : même UUID, kind, texte filtré et version confirmée. Une opération incertaine par conversation ; lecture/réconciliation avant réessai ; pas de nouvel UUID ou changement silencieux du payload/version pour contourner 409. Maximum 20 opérations/256 KiB. Après 7 jours, effacement du texte au prochain accès et conservation d’un marqueur borné jusqu’à suppression ; aucun envoi automatique au lancement et aucune purge pendant que l’app est fermée. Le texte non confirmé reste en mémoire. Suppression/pending/completed/410 retirent les opérations associées ; completed/410 retirent le reçu.

La redaction Swift et celle du CRM local sont comparées sur 13 vecteurs purement synthétiques, y compris NFKC, URLs et marqueurs de secrets factices, pour reconnaître l’accusé du serveur après sa canonicalisation. La rétention et la résolution explicite des conflits restent des gates produit à relire ; cette révision ne remplace pas une politique de confidentialité publiée.

## Résultats acquis

- **27 tests du package candidat : PASS le 6 octobre à 13:44:54 Europe/Paris**, dont identité/charge de réponse et octets du rapport inchangés lors de la reprise après relance, y compris URL filtrée.
- 16 tests de contrat sur le vrai code CRM local, base SQLite privée et seule appID autorisée `siliconpass` : PASS. Déduplication avant vérification de version pour message/resolved/reopened, conflits de charge, canonicalisation/redaction et réessai. Aucun appel au CRM de production.
- Package iOS et visionOS : builds non signés PASS. Le banc iOS a ensuite recompilé le SDK final après alignement de redaction.
- **iOS Simulator dédié : 3/3 PASS** sur la révision finale, fin de passe **14:36:26 Europe/Paris**. Demande/reçu perdu/relances/suppression completed/410 ; réponse confirmée avec accusé perdu, texte réel capturé avant terminaison et identique après relance, un seul message/une seule tentative puis suppression completed/410 ; GET public natif exigeant `siliconpass present`.
- **visionOS Simulator dédié : 3/3 PASS** sur la même révision finale, fin de passe **14:41:40 Europe/Paris**. Les trois mêmes parcours passent, y compris reprise de réponse sans doublon et suppression completed/410. La scène spatiale n’est pas une qualification physique du confort ou de l’accessibilité.
- macOS : SDK compile/tests unitaires PASS, hôte et runner compilent. **UI BLOCKED** avant exécution des tests. Trois modes ont été éprouvés (non signé, ad hoc, identité de développement existante). Le dernier runner est signé avec l’identité existante ; les journaux système à **13:35:15** montrent `taskgated-helper: no eligible provisioning profiles found`, puis refus Gatekeeper à **13:35:17**. Ce n’est pas un refus de l’outil d’approbation Codex. Aucun profil/certificat créé, aucune mutation Apple, aucun changement de Gatekeeper/TCC/quarantaine ou de sandbox pour contourner ce blocage. La qualification native macOS reste false.
- Lecture publique supplémentaire `/v2/apps` : `siliconpass` présent avec les sept identités préexistantes ; aucune mutation de serveur/allowlist effectuée ici.
- Isolation actuelle de SiliconPass : script de l’app PASS. Les deux gates de livraison et les trois gates annexes restent false.

Les parcours de conversations du banc injectent un serveur local et un stockage de reçus synthétiques : ils ne qualifient ni CFNetwork pour les soumissions/réponses, ni le Keychain signé. Seul le préflight app-list utilise le transport HTTPS natif réel. Aucun ticket utilisateur lu et aucun rapport/réponse/suppression de production envoyé ; compteur live de cette reprise : 0 conversation.

La dernière revue ajoute une protection des enveloppes de rapport déjà confirmées : leur texte filtré n’est pas filtré une seconde fois lors d’un retry, ce qui évite la modification des marqueurs d’URL. Les deux requêtes de soumission sont comparées octet par octet par le test de régression.

Les premiers essais UI ont révélé une course d’initialisation de la navigation de fixture après relance, des assertions hors zone virtualisée et un espace final ajouté par le clavier. Le dernier échec iOS montrait déjà la réponse récupérée et les compteurs 1 message/1 tentative ; la comparaison attendue omettait cet espace. Le test capture maintenant le texte réellement confirmé dans l’UI avant terminaison et exige ce texte exact après relance. Les attentes d’initialisation/défilement et la capture du texte confirmé sont corrigées uniquement dans le banc séparé, sans modifier le SDK pour contourner ses gates. Les échecs préalables sont conservés. Un collecteur simctl de diagnostic après un essai échoué a été arrêté après la fin des tests ; cela ne constitue pas un test passant.

Les deux patches passent `git apply --check` dans une copie privée du parent restauré et du fichier hôte actuel, sans application dans SiliconPass.

## Livraison pour revue, pas copie automatique

- `minimal-sdk.patch` : diff des sources depuis le parent contrôlé, pas depuis le snapshot enrichi actuellement présent dans SiliconPass.
- `app-adoption.patch` et `APP-ADOPTION.json` : proposition non appliquée d’une seule adaptation du constructeur de `SPAppSupport` (retirer `features: .forBuild()` car cette révision minimale ne fournit aucune de ces fonctions). Les deux gates restent false.
- `PROVENANCE.json` et `verify-candidate.py` : intégrité/inventaire candidat ; un contrôle vert n’est pas une approbation d’adoption ou de production.
- `NativeFixture/` : banc indépendant avec bundle IDs et namespace synthétique propres ; `project.yml` permet la régénération. Ne pas exporter les screenshots macOS plein écran.

La session SiliconPass doit revoir le diff concret et le delta de confidentialité, puis effectuer elle-même une adoption atomique sur un checkpoint frais, en préservant tout travail concurrent. Ne pas appliquer ce patch aveuglément au snapshot enrichi, ni supprimer ses fichiers optionnels sur la seule base d’un manifest. Ne pas simplement réécrire UPSTREAM pour rendre l’isolation verte. Après adoption revue : provenance/inventaire réellement compilés, génération du projet, builds/tests frais des trois hôtes et de l’app, puis candidat natif signé/droits inspectés avant tout échange synthétique autorisé.

Le plafond communiqué reste six conversations synthétiques et trois tentatives par conversation, une réponse opérateur/client chacune, suppression completed/410 ; rien n’a été consommé ici. Les appareils physiques, provisioning/identités Apple nouvelles et publication restent hors de cette reprise. Aucun commit/push/publication, aucun message envoyé à une autre session, aucun changement Auth/WAF/DNS/portée agent, aucun nouvel automatisme serveur.

## Preuves locales et gates restantes

Logs privés : `/private/tmp/siliconpass-sdk-candidate-final-tests-20261006.log`, `siliconpass-reply-server-final-contract-20261006.log`, `siliconpass-sdk-candidate-ios-ui-final-20261006.log`, `siliconpass-sdk-candidate-ios-reply-r3-20261006.log`, `siliconpass-sdk-candidate-vision-ui-20261006.log`, `siliconpass-sdk-candidate-vision-reply-r2-20261006.log` et `siliconpass-sdk-candidate-macos-ui-development-20261006.log`. Les bundles xcresult correspondants sont conservés. Les premiers runs mobiles complets ont des échecs du nouveau test de réponse ; les réessais ciblés et la dernière passe complète des deux plateformes passent. Ne pas présenter les premiers bundles complets comme 3/3 PASS. Les correctifs d’initialisation/défilement concernent le banc ; le correctif final de reprise d’un rapport contenant une URL concerne le SDK et reçoit une nouvelle passe de tests unitaires et mobiles.

Les tests natifs mobiles sont en anglais, sans qualification VoiceOver/grand texte/FR ni appareil physique. Les trois plateformes restent sans qualification live de bout en bout avec Keychain signé. Les nouvelles fonctions annexes sont absentes de ce candidat et les gates de production restent false.

Avant activation : revue/adoption de la révision, builds/tests frais réellement intégrés, résolution macOS par un canal de signature/provisioning explicitement autorisé, inspection des droits, parcours CFNetwork de bout en bout sur identités synthétiques autorisées, suppression réelle completed/410, puis gates physiques/confidentialité/accessibilité de chaque cible. Ne pas déduire une autorisation d’envoi, de nouvelle identité Apple ou de publication de l’intégrité du candidat.

### Bundles mobiles finaux faisant autorité

- `/private/tmp/siliconpass-sdk-candidate-ios-final-checkpoint-r2-20261006.xcresult` et log homonyme : 3 tests, zéro échec, exit 0.
- `/private/tmp/siliconpass-sdk-candidate-visionos-final-checkpoint-r2-20261006.xcresult` et log homonyme : 3 tests, zéro échec, exit 0.

Ces deux passes complètes suivent le dernier correctif SDK d’enveloppe confirmée et la capture du texte effectivement confirmé par le test. Leur exécution est séquentielle, avec comparaison des sources SDK avant chaque cible et délai maximal de 600 secondes par invocation. La source candidate et ses 36 fichiers contrôlés sont figés à la révision indiquée en tête. Le contrôle d’isolation courant de SiliconPass passe ; aucun fichier source de SiliconPass n’a été modifié pendant cette reprise.

### Suivi du 6 octobre à 15:09 Europe/Paris — ordre JSON

L’adaptation du candidat pour Vif a reproduit deux échecs des assertions d’égalité des octets de rapport après relance : `JSONEncoder` sans `.sortedKeys` ne garantit pas l’ordre des clés. Les passes SiliconPass ci-dessus restent des résultats datés, mais elles ne prouvent pas la stabilité de cet ordre dans tous les processus. Le candidat SiliconPass figé n’a pas été modifié. Avant son adoption, préparer une nouvelle révision avec `encoder.outputFormatting = .sortedKeys` dans `DirectReportTransport`, puis relancer les gates pertinentes. Le snapshot Vif contient ce correctif et ses tests adaptés passent. Ne pas activer SiliconPass sur la seule base de l’ancien checkpoint.

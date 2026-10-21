> **État actualisé le 7 octobre :** [activation et handoff Filova](FilovaActivation-2026-10-07.md) fait foi. Messagerie locale macOS/iOS qualifiée et gates true ; visionOS reste false, bloqué par HTTPS public 503. Les sections ci-dessous conservent les preuves historiques avant activation.

# Filova — checkpoint support du 6 octobre 2026

Travail local uniquement, sans activation serveur, envoi de rapport, commit, push ou distribution. L’intégration préexistante et tous les autres changements de Filova sont préservés.

## Correction de l’intégration

Le constructeur historique `FeedbackClient(profile:)` utilisait des gates internes true et `requiresExactAppAuthorization: false` pour maintenir les consommateurs anciens. Filova emploie désormais une **configuration explicite**, avec gates build `LorisReportsBackendAllowed` et `LorisReportsMessagingVerified`, false par défaut, distinctes pour ses trois Info.plist iOS/macOS/visionOS. Les préférences utilisateur n’activent pas la livraison.

`FilovaServices` conserve un client par processus ; ses fenêtres, aide et hooks le partagent. L’aide se base sur la configuration de cette même instance. La vérification HTTPS de `GET /v2/apps` doit accepter l’identité exacte `filova` avant les livraisons. Les noms voisins et la casse différente ne valent pas autorisation. Aide email `support@lorislab.fr`, avis, portfolio, StoreKit, MusicKit, MatchEngine, CKSyncEngine et signalements de contributions conservés. Aucun groupe Keychain/App Group/entitlement ou delegate Apple modifié. Le namespace de reçus existant et le Keychain non synchronisé sont conservés ; droits effectivement signés et stockage natif restent à qualifier.

Les trois gates diagnostics/assistant/push restent false. Le provider de codes component/permissionState est injecté seulement si la gate diagnostics est qualifiée ; sinon contexte nil. Aucun titre, morceau, playlist, bibliothèque, message, nom de fichier ou log brut ajouté au support. Les hooks de succès préexistants restent locaux et opt-in ; leurs chemins d’échec, corrélations et mesures pertinentes ne sont pas qualifiés par un build. Aucune opération musicale n’attend le réseau support.

## Correctifs SDK partagés

- Le transport URLSession reçoit des callbacks de données avec buffer borné et annulation au dépassement déclaré ou reçu ; aucun téléchargement temporaire complet avant contrôle de taille. HTTPS et URL exactes, redirections refusées, cookies/cache/credentials désactivés, annulation et timeouts. Une session injectée fournit sa configuration assainie, pas son delegate ou ses connexions. Tests de borne exacte, absence/erreur de longueur, redirection/URL changée, annulation avant/en cours et JSON invalide.
- Encodage des rapports avec `.sortedKeys`, conservation de l’enveloppe déjà filtrée pour le réessai confirmé, UUID et recovery token inchangés après relance. Deux régressions vérifient les octets identiques, y compris URL filtrée. L’autorisation exacte est vérifiée avant la création d’une nouvelle entrée outbox pour les configurations qui l’exigent.
- API et fonctions avancées existantes conservées. Les copies embarquées d’autres apps ne sont pas recopiées ; seuls les consommateurs du SDK partagé compilés ultérieurement recevront ces correctifs. Pas de qualification de toutes ces apps revendiquée.

## Preuves

- **45 tests SDK PASS le 6 octobre à 15:31:13 Europe/Paris** : 35 préexistants, 7 transport borné, 2 rapports confirmés/reprise et un préflight public HTTPS natif explicitement opt-in.
- Préflight URLSession : **`filova authorized=false`**, GET-only, aucun rapport/réponse/suppression ou accès Keychain. Curl indépendant confirme l’absence de `filova` dans les huit identités publiques. Aucun changement d’allowlist dans cette tâche.
- **7 tests Filova ciblés PASS**, zéro skip, fin de passe **15:29:45 Europe/Paris** : quatre régressions de l’intégration existante et trois tests de gates indépendantes, absence d’I/O/envoi/outbox quand une gate manque, et refus d’identités voisines.
- **Builds Release iOS/macOS/visionOS : PASS**, sans signature, trois sorties 0. Les deux gates de messagerie sont false dans les Info.plist des bundles effectivement compilés.
- **UI Aide FR/EN iPhone : 2/2 PASS**, zéro échec ni skip, fin de passe **15:41:54 Europe/Paris**. Aide email, message de disponibilité, avis/portfolio ; EN en taille Accessibility XXXL. Audit automatique ciblé textClipped/dynamicType/sufficientElementDescription passé ; pas de qualification humaine VoiceOver, iPad, macOS/visionOS UI ou appareil physique revendiquée.

Les tests et builds utilisent une copie isolée fraîche de l’app et du SDK, avec projet XcodeGen propre, stockage externe m2-build et sans provisioning. Le premier build de tests Filova a échoué parce que la fixture utilisait un initializer de ticket interne au SDK ; fixture corrigée par décodage du ticket synthétique, sans changement de l’API de production. Le résultat final est distinct du premier bundle échoué. Les avertissements existants des autres modules ne sont pas des correctifs support et restent préservés.

Logs privés : `/private/tmp/filova-shared-sdk-tests-20261006.log`, `filova-shared-sdk-final-tests-20261006.log`, `filova-shared-sdk-and-preflight-20261006.log`, `filova-feedback-gate-tests-20261006.log` (premier build échoué), `filova-feedback-gate-tests-final-20261006.log` et xcresult homonyme. Builds : `filova-feedback-{macos,ios,visionos}-release-build-20261006.log`, résumé `filova-feedback-build-results-20261006.json`. SDK compilé : `/private/tmp/filova-feedback-build-20261006/SDK-SOURCES.json`.

## Gates restantes

1. `filova` doit être ajouté à `FEEDBACK_ALLOWED_APP_IDS` avec autorisation séparée. Conserver identités/secrets/FEEDBACK_AGENT_ALLOWED_APP_IDS ; sauvegarde privée, attente readiness bornée, rollback automatique, aucun changement Auth/WAF/DNS/agents. Cette autorisation n’est pas donnée ici.
2. Qualifier chaque cible réellement signée : appID exact via URLSession, droits/Keychain, consentement → envoi synthétique séparément autorisé → présence opérateur → réponse à cette seule identité → lecture native → réponse client → relance/hors ligne/reprise sans doublon → suppression completed et 410. Aucun échange synthétique réel effectué ici.
3. **Reprise des réponses/actions client : implémentée et qualifiée localement à 16:21:55.** Queue durable, réconciliation, UI enrichie et cleanup d’effacement sont maintenant portés dans le SDK partagé. Les 3 parcours natifs synthétiques iPhone passent, dont réponse avant acceptation hors ligne et accusé perdu après acceptation, avec vraie relance et sans doublon. Ce résultat local ne ferme pas la qualification signée/live du point 2, ni APNs/assistant/diagnostics.
4. Journaux : qualification séparée des échecs réellement observés, pertinence des codes sans contenu musical, opt-in/révocation/effacement/expiration, sélection revue et consentement distinct. Aucun journal brut automatiquement envoyé. Assistant Apple local sur appareil et fallback guidé restent à qualifier ; une hypothèse doit être confirmée.
5. Push : propriétaire/callbacks/routage à froid non branchés à Filova, APNs/topic/provisioning et serveur non qualifiés. Aucune alerte réelle ou email automatique n’est active. Les réponses deviennent consultables dans la conversation privée quand la messagerie est activée ; l’aide email conservée ouvre le client mail sans envoyer à la place de l’utilisateur.
6. Worker d’effacement automatique du LXC et passage réel pending → completed/410 restent une qualification serveur distincte. Ne toucher à aucune autre demande.
7. Manifests et notices de confidentialité, FR/EN iPhone/iPad/macOS/visionOS, grand texte/VoiceOver et appareils physiques doivent être relus selon les fonctions activées. Ne mettre une gate true que pour une fonction et une cible effectivement qualifiées. Le chemin SDK local non publié n’est pas un pin de distribution reproductible.

Les trois cibles restent non activées. Aucun certificat/profil créé, compte/provider changé, achat, installation physique, message à une autre session ou publication.

## Livraison locale

Patch de l’app appliqué avec vérification SHA256 des cinq fichiers existants et refus d’écraser les nouveaux fichiers concurrents. Sauvegarde privée app : `/private/tmp/filova-feedback-private-before-20261006/` ; sauvegarde SDK partagé : `/private/tmp/filova-sdk-private-before-20261006/`. Le projet Xcode original ignoré n’est pas remplacé : régénérer depuis `project.yml` après intégration des changements concurrents pour utiliser le nouveau test. Le contrôle read-only `scripts/verify-feedback-integration.py` vérifie les cinq gates false dans les trois cibles, le client/config explicite, le mail et l’inventaire SDK compilé.

Patches de revue : `/Users/kevin/GitHub/LorisLabsKit/Qualification/FilovaSupport-20261006/APP-INTEGRATION.patch` et `SHARED-SDK.patch`. Les sources app/SDK réellement copiées sont comparées à la révision construite ; aucune qualification live n’est déduite de cette égalité. Les tests UI sont dans `/private/tmp/filova-feedback-help-ui-20261006.xcresult` et log homonyme.

## Revalidation — reprise des réponses, 16:21:55 Europe/Paris

Cette passe remplace la gate locale de reprise précédemment ouverte, et complète les preuves antérieures sans les antidater. **58 tests SDK, 16 contrats CRM local, 7 tests Filova et 3 parcours natifs de reprise passent.** Zéro échec ou skip dans les deux suites Xcode. Les trois builds Release macOS/iOS/visionOS passent de nouveau avec le SDK corrigé, sans signature. Les 2 tests Aide FR/EN précédents restent des preuves de la passe antérieure, pas de nouveaux tests de cette passe.

Les réponses/actions confirmées gardent UUID, corps filtré et version attendue ; lecture paginée avant un réessai incertain, POST identique seulement si le message manque. Une opération non acquittée bloque l’éditeur et les nouvelles actions. Queue privée bornée, contenu expiré effacé au prochain accès après sept jours ; aucune émission automatique au lancement. pending/completed/410 effacent les données locales de la référence concernée et completed/410 retirent le reçu. Les tests couvrent aussi concurrence réponse/effacement, pagination incohérente et bornes de lecture avant décodage. Les erreurs de stockage pendant cleanup restent hors de cette qualification.

Le banc natif compile les vrais `FilovaServices` et `FilovaHelpView` avec injections de serveur/tickets factices dédiés, sans réseau de production ni Keychain. La réponse opérateur, les suppressions et compteurs de messages sont synthétiques locaux. Les contrats CRM utilisent sa source locale et une SQLite isolée. Aucune conclusion sur le worker du LXC ou le push réel n’en découle. Le préflight public natif de cette passe donne encore `filova authorized=false` à 16:05:15. Les cinq gates restent false dans les trois cibles.

Preuves et patch incrémental : [qualification locale complète](../Qualification/FilovaSupportRecovery-20261006/README.md), [résultats datés](../Qualification/FilovaSupportRecovery-20261006/RESULTS.json), [patch de reprise](../Qualification/FilovaSupportRecovery-20261006/REPLY-RECOVERY.patch). Les inventaires du dossier qualifié comparent les sources actuelles aux copies réellement construites. L’inventaire SDK de Filova est actualisé seulement après cette qualification ; il ne constitue pas un pin de distribution.

Sauvegarde initiale de cette passe SDK : `/private/tmp/filova-reply-recovery-before-20261006/`. Logs privés finaux : `filova-reply-recovery-sdk-final-20261006.log`, `filova-reply-recovery-crm-contract-final-20261006.log`, `filova-reply-recovery-app-tests-20261006.log` et `filova-reply-recovery-ui-final-20261006.log` dans `/private/tmp`, bundles xcresult homonymes pour les deux suites Xcode. Les tentatives initiales échouées sont conservées séparément. Aucun commit, push, changement serveur, provisioning ou publication.

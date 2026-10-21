# Filova — activation et handoff, 7 octobre 2026

La messagerie est qualifiée et activée **dans les sources locales macOS et iOS**. VisionOS reste désactivé. Aucune nouvelle version n’est distribuée. Le service public est actuellement indisponible : `GET https://help.lorislab.fr/v2/apps` renvoie **503, `no available server`**, observé le 7 octobre à **08:44:46 Europe/Paris**. Le CRM dans le LXC 185 répond `ready` et ses routes locales healthz/readyz/v2/apps répondent 200. L’autorisation exacte `filova` demeure dans l’allowlist ; les livraisons natives vérifient cette identité avant envoi et conservent les données confirmées si le réseau échoue.

| Cible | BackendAllowed | MessagingVerified | Diagnostics / assistant / push |
|---|---|---|---|
| macOS | true | true | false / false / false |
| iOS | true | true | false / false / false |
| visionOS | false | false | false / false / false |

## Preuves et limites

Le 6 octobre, ajout du seul `filova` dans FEEDBACK_ALLOWED_APP_IDS, avec sauvegarde privée, remplacement atomique, redémarrage, attente readiness bornée et restauration conditionnelle en cas d’échec. La restauration n’a pas été nécessaire. Le contrôle final du 7 octobre à **08:44:50** confirme les autres entrées d’environnement, secrets et portée des agents inchangés par comparaison avec la sauvegarde. Aucun changement Auth/WAF/DNS ou configuration du proxy.

macOS et iOS : consentement explicite, envoi via le vrai URLSession, reçu Keychain natif, présence opérateur et réponse adressée à cette seule identité, lecture dans Filova, réponse client, vraie relance, panne injectée avant acceptation, accusé perdu après acceptation, réconciliation et réessai identiques sans doublon. Le serveur confirme **un rapport et deux réponses client par cible**, avec une réponse opérateur. Suppression native puis finalisation opérateur : completed, 410 et nettoyage SDK des reçus/files locales passent. Le parcours macOS est exécuté dans une app Development signée ; iOS est exécuté sur un simulateur dédié, avec build générique signé vérifié séparément. Aucun appareil iPhone/iPad physique n’est qualifié par cette passe.

VisionOS : livraison et réponses/reprise passent sur simulateur visionOS 27.0 dédié, build générique signé vérifié séparément. La suppression native échoue au chargement de la conversation : l’accès HTTPS public renvoie 503. Les deux tentatives échouées sont conservées, sans les compter comme une réussite. Le rapport synthétique restant a été supprimé par le traitement serveur officiel, limité à son enregistrement exact, puis completed et 410 opérateur confirmés. Le simulateur jetable a ensuite été supprimé pour effacer ses reçus privés. **Ce nettoyage ne qualifie pas completed/410 ou cleanup SDK visionOS** ; ses flags restent false.

Les trois demandes synthétiques de cette passe sont effacées et leurs marqueurs opérateur retirés. Aucune autre demande n’a été modifiée ni aucun contenu effacé restauré. L’effacement a été finalisé par l’opérateur : **le worker automatique n’est pas qualifié**. Le push, l’assistant et les journaux détaillés restent des qualifications distinctes ; le client lit les réponses dans Aide → sa conversation, sans alerte APNs ni email automatique activé ici.

Les **trois builds Release signés finaux passent**, avec inspection des flags des bundles et vérification des signatures. **Sept tests Filova ciblés passent**, zéro échec/skip, le 7 octobre à 08:26:14 Europe/Paris. Le contrôle d’intégration vérifie la révision SDK, les gates et l’empreinte des preuves natives. Les 58 tests SDK, 16 contrats CRM local et 3 parcours locaux de reprise du checkpoint du 6 restent des preuves historiques de cette même source de production SDK ; ils ne sont pas présentés comme une nouvelle exécution. Le test GET public a été adapté pour permettre une attente autorisé/non autorisé explicite ; sa passe positive unique date du 6 à 17:06:00.

## Instructions pour la session Filova

Les modifications sont déjà appliquées dans `/Users/kevin/GitHub/Filova`. Lire ce handoff et `docs/feedback/ACTIVATION-QUALIFICATION-20261006.json`, puis exécuter `python3 scripts/verify-feedback-integration.py`. Préserver les modifications concurrentes et le SDK partagé. Aucun correctif QA, fenêtre spéciale, injection réseau ou test live ne doit entrer dans le produit. Le projet Xcode original n’a pas été régénéré ; les tests/builds utilisent sa copie isolée issue de project.yml.

Pour finir visionOS : rétablir et vérifier l’entrée HTTPS publique dans une tâche d’administration autorisée, puis refaire une qualification synthétique native complète et datée, sans réutiliser le contenu effacé. Ne pas basculer les flags visionOS avant les preuves manquantes. Ne pas activer diagnostics/assistant/push à partir de cette qualification de messagerie. Les parcours FR/EN iPad, VoiceOver et appareils physiques restent à revalider avant distribution selon le scope de release.

Aucun commit, push, changement de profil/certificat, TestFlight ou publication.

Preuves : [résultats natifs](../Qualification/FilovaActivation-20261006/NATIVE-UI-RESULTS.json), [contrôle final serveur](../Qualification/FilovaActivation-20261006/SERVER-POSTFLIGHT.json), [statut HTTPS final](../Qualification/FilovaActivation-20261006/FINAL-PUBLIC-STATUS.json), [builds finaux](../Qualification/FilovaActivation-20261006/FINAL-BUILDS.json), [tests finaux](../Qualification/FilovaActivation-20261006/FINAL-APP-TESTS.json), [patch d’activation appliqué](../Qualification/FilovaActivation-20261006/ACTIVATION-APP.patch), [banc QA et provenance](../Qualification/FilovaActivation-20261006/README.md). Le patch SDK complet de la reprise est dans [le checkpoint précédent](FilovaSDK-Checkpoint-2026-10-06.md).

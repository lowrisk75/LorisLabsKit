# Catalogue et avis — 15 octobre 2026

## État et périmètre

Implémentation appliquée dans le SDK canonique et Sève/Foods. Propriétaire : Codex. Changements locaux non publiés ; aucun commit, push, déploiement ou changement de service. Périmètre : catalogue/menu et demandes d’avis, sans réécriture des achats, de la synchronisation ou du support. Ces validations ne constituent pas un audit global ni une certification « SOTA » de tous les modules.

## Travail terminé

- Catalogue de 21 apps publiées, vérifiées sur le compte Apple 1874045866 : 20 disponibles dans la réponse FR, 21 dans la réponse US. Titres, identités et liens officiels ; descriptions de produit FR/EN relues et icônes officielles embarquées. Aucun téléchargement, suivi ou identifiant requis à l’affichage. Script reproductible `Scripts/update-portfolio-catalog.py`, rejet des nouvelles identités sans description relue et des ressources inattendues.
- `LorisLabsAppsMenu`, entrée `LorisLabsAppsLink` et lignes compatibles `MoreFromLorisLabsView`. Exclusion de l’app courante et de ses variantes debug/extensions, liens neutres en pays, textes sans limite de lignes, icônes décoratives, cible d’au moins 44 points et indicateur externe allégé en grand texte. Chargement UIImage/NSImage explicite mis en cache : le rendu natif a révélé et permis de corriger l’échec de résolution initiale des noms d’images.
- Politique commune `ReviewPolicy` utilisée par `SmartReviewPromptManager`. Valeurs par défaut : 14 jours écoulés, cinq actions sur trois jours distincts, action réellement terminée dans la session depuis moins de cinq minutes, deux minutes de session, pause de deux secondes, 120 jours entre tentatives et au plus un essai par version/session. Navigation et passage en arrière-plan annulent l’opportunité ; gestes, interactions, feuilles et alertes suspendent la demande. Conditions revérifiées avant StoreKit. Historique de tentatives conservé avant l’appel, y compris si Apple n’affiche rien. Paiement, satisfaction, erreurs et historique support ne filtrent pas les personnes sollicitées.
- Compatibilité des anciens appels conservée ; `recordCompletedAction`, `reviewPromptWhenIdle` et import conservateur `ReviewAttempt` documentés. Les copies de SDK dans les autres apps ne sont pas mises à jour automatiquement.
- Sève : menu Réglages FR/EN avec icônes, exclusion de Sève ; ancienne politique aux résultats 3/15 retirée. Signaux après analyse live terminée ou consommation effectivement enregistrée. Aucun signal sur l’apparition d’une vue, une démonstration ou le lancement. Migration d’une ancienne tentative sans date vers un délai conservateur, importé une seule fois.
- Sève conserve son snapshot LorisReports original ; produit LorisLabsKit ajouté au snapshot figé. 87 empreintes source/ressource vérifiées. Les gates support, entitlements et données métier sont préservés. 66 fichiers appliqués à 09:07:49 UTC après gardes de concurrence et sauvegarde ; toutes les empreintes correspondaient au candidat à l’application.

## Sources et décisions

Recommandations Apple actuelles : [Requesting App Store reviews](https://developer.apple.com/documentation/storekit/requesting-app-store-reviews) et [Ratings and reviews](https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews). Elles soutiennent l’usage du prompt natif après engagement et à une pause naturelle ; les seuils 14/5/3/120 et les deux minutes de session sont des choix conservateurs de produit, pas une exigence Apple ni une preuve mesurée de conversion. Le système reste maître de l’affichage.

Catalogue public : [Apple FR](https://itunes.apple.com/lookup?id=1874045866&entity=software&country=fr&limit=200), [Apple US](https://itunes.apple.com/lookup?id=1874045866&entity=software&country=us&limit=200). Identités, provenance et hashes des images dans `APPLE-RELEASE-CATALOG.json`.

## Validations

- Suite complète SDK macOS PASS, zéro échec. 73 cas Swift Testing, 26 cas Sync, 72 cas Reports et cinq cas XCTest du SDK/harnais ; les tests publics GET et trois cas de Keychain iCloud restent volontairement ignorés comme prévu par leurs contrats.
- Limites de temps, jours distincts, session sans action, version, relance, plusieurs instances, persistance avant callback, scène inactive, annulation et revérification pendant la pause couverts. Aucun prompt StoreKit réel ouvert.
- Trois tests de l’adaptateur Sève exécutés sur macOS PASS : engagement minimal, reprise sans nouveau signal, import unique du cooldown ancien. Même source d’adaptateur que l’app, version et horloge injectées. Ce résultat ne remplace pas l’exécution de la suite applicative iOS.
- Rendu SwiftUI/AppKit natif FR/EN PASS, deux captures inspectées après correction des icônes. Décodage des 21 images et validation de leurs liens/localisations PASS. Le rendu macOS ne qualifie pas à lui seul le Dynamic Type iPhone.
- Candidat Sève : build Release iPhone non signé PASS et build-for-testing iOS Simulator PASS après le dernier correctif. Deux nouveaux parcours FR/EN grand texte ajoutés et compilés ; non exécutés, voir blocage ci-dessous. Les warnings nouveaux d’isolation des tests ont été corrigés ; warnings existants Reports/StoreKitTest conservés.
- Vérification de snapshot embarqué, correspondance canonique des sources engagement et `git diff --check` PASS. Sauvegardes et plan gardé conservés sous Qualification.

## Concurrence et état courant

Une écriture simultanée du SDK a été détectée pendant le premier build. L’édition des dépôts a été suspendue, puis l’utilisateur a confirmé l’écriture exclusive. Les ajouts externes ont été sauvegardés et réconciliés, notamment les tests de catalogue, l’exclusion des variantes de bundle et les délais de session. Les nouveaux changements métier de Foods présents avant application ont été réconciliés sans conflit.

Après application, des écritures extérieures ont encore modifié `AppFlowView.swift`, `Localizable.xcstrings`, `PersonalizationTraceTests.swift`, `ShareCard.swift` et `PRISMTheme.swift`. Elles sont conservées, sans réapplication du candidat. Les quatre hooks d’engagement et les traductions du menu sont toujours présents ; les 64 autres fichiers appliqués restent identiques au candidat. Le build qualifie le candidat testé, pas ces modifications extérieures ultérieures. Détails et empreintes finales dans `FINAL-CHECKS.json`.

## Travail restant et blocages

Continuation ultérieure : le SDK commun a reçu l’API `additionalEligibility` après cette intégration. Un complément de deux fichiers pour actualiser le coordinateur embarqué et sa provenance a réussi son build Release iPhone sur une copie fraîche. Des modifications extérieures dans trois fichiers Foods ont ensuite bloqué l’application avant toute écriture ; le complément reste non appliqué. Voir `Qualification/PortfolioRollout-20261015/seve/APPLICATION-BLOCKED.json` et le journal de rollout. L’intégration initiale demeure en place ; les anciennes preuves ne qualifient pas ces évolutions ultérieures.

Aucune correction de code restante identifiée pour les deux volets implémentés. Qualification native iPhone à reprendre sur un créneau de simulateur : `SeveEngagementUITests` et régression `SeveSupportUITests`, puis inspection des captures FR/EN grand texte. L’attribution Throttle a retourné « Simulator request is unconfirmed » pour request/status/release ; aucun appel direct de boot/test n’a contourné une demande en file. L’app courante ayant reçu des modifications extérieures, refaire son snapshot avant cette qualification. Aucun résultat UI iPhone ni audit VoiceOver complet revendiqué.

Ne pas réexécuter le script d’application : ses guards et la sauvegarde décrivent l’état pré-application. Pour reprendre, lire les fichiers vivants, ce journal et le plan/FINAL-CHECKS, obtenir une écriture réellement exclusive si une correction est nécessaire, puis requalifier uniquement ce qui a changé.

## Ressources et preuves

Preuves durables : `Qualification/Engagement-20261015` : snapshots avant réconciliation, sauvegarde juste avant application, plan/hashes, scripts bornés, logs des passes, deux captures natives et registre de ressources. Aucun transcript privé ni secret conservé. Journal Sève : `/Users/kevin/GitHub/Foods/audit-output/Seve-Engagement-20261015.md` ; ce journal décrit l’application, les changements ultérieurs sont précisés ici.

Ressources propres créées puis supprimées après export : source et sauvegarde `/private/tmp/lorislabs-engagement-20261015`, builds `/Volumes/DeveloperStorage/BuildScratch/Auto/LorisLabsKit/engagement-20261015` et `/Volumes/DeveloperStorage/BuildScratch/Auto/Foods/engagement-20261015`, simulateur Seve-Engagement-20261015 / iPhone 17 Pro iOS 27.0 / `ACA0F751-B8CD-49AA-A61D-9089ADA3E1D4` (jamais démarré, shutdown puis delete exécutés). Ressource Throttle `9B0CFAEC-4804-4882-A0A9-2C4ACD53B790` marquée released. Aucun processus de fond conservé, cache partagé préexistant ou simulateur tiers supprimé.

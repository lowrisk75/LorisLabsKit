# Reprise SDK dans les sept projets réservés

## Coordination

Complément découvert lors de la continuation : Sève reste intégrée auparavant, mais deux fichiers de son SDK embarqué nécessitent une actualisation. Le candidat compile ; une écriture extérieure a bloqué son application avant toute modification. Ce huitième checkout réservé est suivi séparément sous `Qualification/PortfolioRollout-20261015/seve` et dans le journal principal. Les sept consignes ci-dessous gardent leur périmètre initial.

Sept dépôts conservent leur écrivain existant. Millrace et Millrace Scan ont été intégrés après transfert explicite ; leurs 33 fichiers appliqués, deux builds et onze tests sont vérifiés dans le journal principal. Le propriétaire a choisi de les laisser continuer. Ne pas appliquer de fichiers ni générer de projet dans leurs checkouts avant fin ou transfert explicite de cette écriture. Les intégrer ensuite depuis leur état vivant, sans écraser les modifications courantes. Ce document est une passation technique, sans transcript privé.

## Objectif commun

Raccorder le catalogue hors ligne et ses icônes officielles, ainsi que la politique d’avis prudente du checkout `/Users/kevin/GitHub/LorisLabsKit`. Les sources Core/Reports revues sont figées dans `Qualification/PortfolioRollout-20261015/sdk-source` ; empreintes dans SDK-HASHES.json. Ce travail n’est pas publié sous un nouveau tag distant. Ne pas inventer de version ni changer de pin vers un tag ancien en prétendant récupérer ce snapshot.

Conserver commerce, identité, synchronisation, moteurs métier, forks de transport et gates existants. Ne pas activer diagnostics, assistant, notifications ou backend. Un dossier de support existant ne doit pas être remplacé intégralement par un snapshot générique sans comparaison de ses adaptations.

Le SDK fournit `LorisLabsAppsLink` pour un NavigationStack de réglages, `LorisLabsAppsMenu` pour une destination/sheet et `PortfolioText.title(locale:)` pour un hôte personnalisé. Copier aussi Resources et traiter les ressources dans le manifeste du module. Exclure l’app courante avec son vrai bundle ID. Sur Apple TV, conserver une navigation native et transférer les destinations à un téléphone si nécessaire ; aucun prompt StoreKit indisponible.

Créer un seul SmartReviewPromptManager tôt dans la vie de l’exécutable. Compter uniquement une action utilisateur réellement terminée, puis utiliser `reviewPromptWhenIdle`. Alimenter les états de saisie, navigation, sheets et opérations en cours ; utiliser `additionalEligibility` pour relire les fenêtres/modals natifs non observables après la pause. Le lancement, la navigation, l’achat et l’actualisation passive ne sont pas des completions. Un bouton volontaire de notation ouvre le lien App Store de composition vérifié, sans appeler directement requestReview. L’absence de moment calme justifie de laisser les avis automatiques désactivés.

## Candidats préparés dans des copies isolées

Les fichiers modifiés, empreintes et preuves de chaque candidat sont exportés sous `Qualification/PortfolioRollout-20261015/<clé>/`. Lire `CANDIDATE.json`, `PLAN.json` et `REVIEW.patch` ; les fichiers après modification sont sous `candidate-files/`. Ces exports ne sont pas une autorisation de remplacement. Les diffs omettent les fichiers dont le contenu vivant a changé pendant notre travail.

| Projet / clé | Raccordement préparé | Validation actuelle |
| --- | --- | --- |
| Lumen / `lumen` | Snapshot local Core ; menus iOS/Mac et catalogue TV avec QR ; demandes automatiques liées aux connexions, alertes, parrainages et fermeture d’événement supprimées ; une seule instance du gestionnaire, seuils communs, lien volontaire existant conservé. | Mac/iOS/tvOS réussis après raccordement des helpers TV. |
| Clasp / `clasp` | Engagement/Resources uniquement dans son fork ; menus dans les vrais réglages Mac/iOS ; demandes du premier snippet, dixième collage et parrainage supprimées ; lien volontaire App Store dans l’aide. | Mac/iOS réussis ; 11 tests embarqués réussis. |
| Kernel / `kernel` | Sous-ensemble KernelEngagement mis à jour ; menu SDK ; coordination partagée après reconstruction terminée ; sortie du résultat vers l’accueil sur mobile, contrôle des fenêtres natives sur Mac. | Mac/iOS réussis ; 15 tests embarqués réussis. `Kernel/Sources/UI/KernelWindow.swift` a changé dans le checkout vivant : une proposition fraîche est disponible sous `kernel/Reconcile-20261015` avec ses empreintes ; recapturer/requalifier avant application. |
| Filova / `filova` | SDK canonique déjà référencé ; catalogue commun et coordination d’inactivité SDK ; completion dédupliquée et attentes existantes préservées. | Mac/iOS réussis ; quatre contrats du service exécutés dans un harnais macOS isolé, app complète/UI non requalifiées. |
| SiliconPass / `siliconpass` | Core/Resources dans le package support ; menu hors ligne depuis l’aide autorisée ; transports bornés et gates conservés. Pas de prompt automatique. | Mac/iOS réussis. |
| Vif / `vif` | Core/Resources dans VifFeedbackSDK, wrapper de menu et bouton dans l’aide réelle ; transports et flags de confidentialité conservés. Pas de prompt automatique. | Package support Release + hôte de qualification des fichiers réels d’aide/licences Mac/iOS réussis. Build complet arrêté par la garde de provenance native ; aucune garde contournée. |
| DNS Sinkhole / `sinkhole` | Snapshot Core partagé ; menu dans les réglages du client iOS et de la console Mac Home. DNS, daemon et extensions conservés. Pas de prompt automatique. | Sinkhole iOS et SinkholeHome Mac réussis. |

Vif : dans la copie temporaire, la vérification FFI refuse `/tmp`, ancêtre symbolique, avec `O_NOFOLLOW`. Les reçus natifs lient aussi la source et les options au checkout d’origine. Reprendre le build complet dans le vrai checkout avec son écrivain ; ne pas recréer les reçus sans compilation native ni désactiver la garde.

Lumen TV : les appels existants à PaywallMetrics et InternalProQualification nécessitaient un raccordement de sources. Le helper InternalProQualification est séparé à l’identique de DevUnlockService et partagé ; la TV conserve son propre DevUnlockService. Ce lot ne change pas la logique d’achat ou d’octroi Pro.

## Validation et passation

Commencer par un snapshot des fichiers vivants et une inspection des instructions locales. Préparer une copie indépendante si la session précédente écrit encore. Ne pas appliquer cette copie sans nouvelle vérification des empreintes et de l’écriture exclusive. Valider les raccordements de l’hôte, puis les builds pertinents ; les 24 tests SDK et les trois contrats 404/Velya de ce rollout ne qualifient pas automatiquement les hosts restant à appliquer.

Les quatorze intégrations disponibles sont déjà appliquées : TypeMetrics, 404, Kiosk, Velya, Weave, Lumen Bridge, Aegis, AuroraPulse, EntroFold Archive, Halte, Kalou, Mela, Rampart et Millrace/Scan. Le vrai checkout EntroFold Archive est `/Users/kevin/GitHub/WINRAR`, projet `EntroFoldArchive/EntroFold Archive.xcodeproj` ; le dépôt `/Users/kevin/GitHub/EntroFold` est un moteur distinct.

Journal autoritaire : `Documentation/PortfolioSDK-Rollout-2026-10-15.md` et `Qualification/PortfolioRollout-20261015/STATE.json`. Toutes les copies, dossiers de build, miroir SDK et parent temporaire de cette mission sont nettoyés. Les exports et preuves durables restent dans Qualification/PortfolioRollout-20261015 ; aucune ressource externe active à reprendre. Aucun commit, push, publication ou activation externe n’est autorisé par cette passation.

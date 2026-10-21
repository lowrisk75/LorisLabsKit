# Vérification du menu et des demandes d’avis — 15 octobre 2026

Périmètre : répondre sur l’état réellement présent dans le SDK et dans Sève. Inspection commencée en lecture seule. Aucun changement de code, configuration, app, service ou gate. Les travaux existants, notamment `Engagement-2026-10-15.md`, sont préservés. Ce journal ne contient aucun transcript privé.

## Travail terminé

- Catalogue SDK lu : cinq entrées dans `LorisLabsApp.portfolio`, exclusion de l’identité exacte de l’app courante et liens App Store.
- Composant `MoreFromLorisLabsView` lu : lignes de boutons avec initiales dans `AppIconPlaceholder`, sans véritables icônes d’app. Le composant doit être placé par l’app hôte ; sa présence dans le SDK ne prouve pas son intégration.
- Sève : aucun menu des autres apps trouvé dans les Réglages ; dépendance au seul produit LorisReports. Le chemin courant est `Packages/LorisLabsKit`, différent de l’intégration historique relative au dépôt SDK.
- SDK avis : valeurs par défaut 14 jours, cinq actions, trois jours actifs, 120 jours entre tentatives, une tentative par version et par instance/session. Garde `interactionInProgress`. Ces paramètres sont configurables par chaque app.
- Limite SDK identifiée : aucune obligation d’une action terminée dans la session courante. Le modifier peut contrôler l’éligibilité à l’apparition d’une vue ; il annule correctement sa tâche lorsque le délai est interrompu.
- Sève : politique indépendante `ReviewPrompt`, seuils aux résultats 3 et 15, ou consommation confirmée dès qu’un résultat a été affiché ; au plus une tentative par version. Aucun âge minimum, nombre de jours actifs ou délai entre versions. L’affichage d’un résultat est compté dans `onAppear`, donc ne prouve pas une nouvelle analyse distincte.
- Sève : la demande différée de deux secondes est lancée dans une tâche non liée au cycle de vie de la vue ; `try?` n’empêche pas l’appel après annulation. L’essai est marqué avant ce délai, sans nouvelle vérification de l’interaction au moment de l’appel.

## Validations et limites

Lecture des sources, des raccordements et des tests existants ; empreintes prises après inspection. Aucun test ou build exécuté dans cette vérification, aucune fenêtre StoreKit déclenchée, aucune qualification UI revendiquée. Les tests Sève existants autorisent explicitement une demande après un résultat et une consommation ; ils ne qualifient pas une politique espacée dans le temps. Cette vérification ne constitue pas un audit de toutes les apps du portefeuille.

Empreintes SHA-256 des principales sources vérifiées :

| Fichier | SHA-256 |
| --- | --- |
| SDK `CrossPromotion/LorisLabsApp.swift` | `299a22b30785742870419b5f3dc394d71ab175b47bae19a846490b16db666a4c` |
| SDK `CrossPromotion/MoreFromLorisLabsView.swift` | `6389a3c6fc5c6277e5c77b7b17d1c1039bbde64ad98b3f7f94c072d35706432f` |
| SDK `Review/SmartReviewPromptManager.swift` | `8eed49e651cf5b9605153f1e30814efb952ef35bba6e0b7ac02525b8b944e777` |
| SDK `Review/ReviewPromptOnAppearModifier.swift` | `39363aa77c65eb1f9e8fd6a7bb729f60c1abc52c12ef13fa0343ca5637b8f7e1` |
| Foods `PRISM/Services/ReviewPrompt.swift` | `ab41d2e600b2594661c3fe84b71557a2b92dfb58b05ea9bd943d8b0ef2cdf008` |
| Foods `PRISM/Presentation/Result/ResultView.swift` | `9aa803f8fa44e7d0e44a06d7fed9509e32b6c28f708a076febebe413bc7f7779` |
| Foods `PRISM/Presentation/Settings/SettingsView.swift` | `18fde44f4033f9e85848f4e7e636fbef2a9507e81e1a79a59e559f4367612b40` |
| Foods `project.yml` | `ad72fa434dd1fd9111fb78c1f5373fcb34438c0939abefbaaf1c772c2d2bd26d` |

## Travail restant et reprise

La vérification demandée est terminée. L’implémentation des vraies icônes et du menu, la condition d’action dans la session courante et l’espacement de la politique propre à Sève restent à faire ; ne pas les présenter comme livrés. Le journal `Engagement-2026-10-15.md` décrit déjà un chantier distinct inachevé à relire avant toute correction. Vérifier l’écriture exclusive et les sources courantes avant modification. Ne pas supposer que les copies SDK embarquées dans les apps suivent le working tree canonique.

Aucun blocage pour cette vérification. Aucune ressource créée hors dépôt, aucun processus, simulateur ou dossier de build à nettoyer. Aucun commit, push, déploiement ou publication.

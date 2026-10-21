# Déploiement local du SDK — 15 octobre 2026

## État de la mission

Quatorze projets sont intégrés localement, dont Millrace et Millrace Scan après transfert explicite d’écriture. Sept checkouts restent réservés à leurs sessions : Lumen, Clasp, Filova, Kernel, SiliconPass, Vif et DNS Sinkhole. Leurs candidats sont exportés, sans application dans ces dépôts. Aucun commit, push, portail Apple, publication ou activation serveur effectué.

Dernière continuation : les 966 fichiers appliqués de ces quatorze projets sont conformes. Sève, déjà intégrée séparément auparavant, possède aussi un complément SDK de deux fichiers compilé mais bloqué par des écritures extérieures observées pendant qualification. Huit checkouts sont donc actuellement réservés : les sept ci-dessus et Sève pour ce complément. Aucun projet applicatif libre restant à appliquer dans cette file ; les copies et builds propres sont nettoyés.

Dernier contrôle de disponibilité après 21:18 UTC : activité récente des sept sessions initiales, aucun transfert d’écriture confirmé ; Sève conserve sa réservation après la concurrence observée. Les trois empreintes Sève précédemment modifiées sont stables à ce contrôle, ce qui ne prouve pas une libération de l’écrivain. Vérification des chemins réels et racines Git : aucune autre racine résolue n’explique cette absence de session Foods dans l’inventaire Codex. Reçu : AVAILABLE-NEXT-CHECK.json ; état courant dans CURRENT-STATUS.json, champ latestAvailability. Aucun dépôt applicatif modifié ni nouvelle ressource créée. Le choix du propriétaire de laisser continuer les sessions occupées est maintenu.

Les changements préexistants ont été capturés puis préservés. Le journal structuré est `Qualification/PortfolioRollout-20261015/STATE.json`. Il contient travail terminé/restant, validations, limites, blocages et ressources, sans transcript privé.

## Travail terminé

| Projet | Raccordement | Builds Release non signés |
| --- | --- | --- |
| TypeMetrics | Catalogue/icônes avec contrôle parental existant ; avis après pratique terminée pour le groupe adulte existant. | iOS, macOS |
| 404 Network | Catalogue/icônes ; ancienne règle de trois scans remplacée, migration du dernier avis conservée. | iOS, macOS |
| Meetglow / Kiosk | Catalogue dans Admin, Bridge et Display ; icônes et QR codes sur Apple TV ; aucun avis automatique ajouté aux affichages passifs. | KioskAdmin, KioskBridge, KioskBridgeQA, KioskDisplay, KioskDisplayMac, KioskTV |
| Velya | Catalogue ; avis différé sur Insights après un vrai Stop ; compteurs de l’offre Pro conservés ; support existant préservé. | iOS |
| Weave | Catalogue ; occasion d’avis à la fin d’une session distante utilisable ; ancien bouton de demande native directe retiré. | Host-macOS, Mobile-iOS, Viewer-macOS |
| Lumen Bridge | Catalogue avec icônes ; vérification réelle des fenêtres/aide/modals avant la demande d’avis. | macOS |
| Aegis | SDK Core/Reports et aide/catalogue natifs sur iOS et Mac ; aucune collecte ni demande d’avis automatique. | iOS, macOS |
| AuroraPulse | SDK Core/Reports et aide/catalogue natifs ; pas d’avis sur simple actualisation des données. | iOS |
| EntroFold Archive | Projet Apple retrouvé sous WINRAR/EntroFoldArchive ; aide/catalogue natifs et avis à l’inactivité après création réelle d’une archive. | macOS |
| Halte | SDK Core/Reports et aide/catalogue ; ancienne demande d’avis liée à l’historique supprimée. | iOS |
| Kalou | SDK Core/Reports et aide/catalogue ; aucune demande automatique dans le parcours de soins. | iOS |
| Mela AAC | SDK Core/Reports et aide/catalogue derrière le contrôle parental, fermeture au verrouillage ; aucun avis automatique AAC. | iOS |
| Rampart | SDK Core/Reports et catalogue complet remplaçant le lien unique ; aucune demande automatique dans la configuration du pare-feu. | iOS, macOS |
| Millrace + Millrace Scan | Core/catalogue/icônes hors ligne dans l’aide partagée ; support conservé et cinq gates fermées ; aucun avis automatique ajouté. | macOS, iOS |

Le SDK commun dispose aussi du contrôle `additionalEligibility` : les fenêtres et modals non observés par SwiftUI sont relus après la pause, avant toute tentative. Un refus ne consomme pas le cooldown. Les valeurs par défaut restent 14 jours, cinq actions sur trois jours, deux minutes de session, pause calme, 120 jours entre tentatives et une tentative par version. La navigation seule ne compte jamais.

## Validations

- 26 lanes de builds Release non signés réussies sur les quatorze projets appliqués.
- 24 tests ciblés du gestionnaire d’avis réussis, dont ouverture d’un modal pendant la pause ; trois contrats d’adaptateurs 404/Velya réussis (migration, anciens compteurs, offre Pro indépendante).
- Projets générés comparés structurellement : réglages et sources/ressources métier conservés, dépendances SDK et fichier d’aide seuls ajoutés. Les sources applicatives modifiées figurent dans chaque PLAN.json.
- Vérification du premier lot : aucune dérive des fichiers appliqués dans les treize dépôts. Reçu : `Qualification/PortfolioRollout-20261015/FINAL-VERIFICATION.json`.
- Sources canoniques Core/Reports sans dérive par rapport à `SDK-HASHES.json`. Le snapshot `sdk-source` sert de source de copie et n’est pas un package autonome complet : les produits Sync/Design n’y sont pas figés.
- L’erreur d’isolation Swift 6 de l’adaptateur Velya et le mauvais scheme TV initial ont été corrigés puis requalifiés. Le premier timeout 404 a été résolu par reprise dans le même dossier.

## Limites et travail restant

Les builds ne qualifient pas les parcours UI natifs des hosts, VoiceOver, la signature, les archives ou la distribution. Les anciennes preuves Sève/SDK restent décrites dans Engagement-2026-10-15.md et ne sont pas réinterprétées comme une qualification des nouveaux hosts.

Les nouveaux hosts Reports ne collectent aucun contexte automatiquement et ne branchent aucun journal, flush, APNs ou assistant. Les gates réseau demeurent fermées par défaut. Inscription serveur exacte, essais natifs consentis et activation sont des lots séparés. Les wrappers de support existants des apps déjà intégrées sont préservés ; cette mission ne prétend pas remplacer tous leurs forks métier.

Aegis a été lié contre des copies exactes des bibliothèques Rust déjà présentes dans son checkout ; leurs hashes figurent dans prebuilt-rust.json. Il ne s’agit pas d’une requalification indépendante du moteur Rust.

TypeMetrics utilise le groupe pédagogique adulte du modèle existant ; ce groupe ne constitue pas une vérification d’âge. Mela garde son verrou parental et ne reçoit aucun avis automatique.

## Millrace : application et préservation vérifiées

Le propriétaire a confirmé la fin de la session Millrace ; l’écriture n’a été reprise que pour ce projet et son compagnon Scan. Nouvelle capture de 5 470 fichiers, aucune dérive pendant copie. L’intégration appliquée porte sur 33 fichiers, dont deux existants : Package.swift et MillraceHelpView.swift. Les 31 nouveaux fichiers regroupent Core, ressources du catalogue, provenance et un fichier contenant deux tests.

Les deux builds Release Mac/iOS passent. Les produits contiennent chacun 21 entrées de catalogue et 21 icônes, avec exclusion correcte de l’app courante. Le bouton d’aide reçoit un style natif et une hauteur minimale de 44 points. Les neuf tests de support conservés et les deux tests du catalogue embarqué passent, avec transport synthétique et données de test isolées. Aucun stockage ni serveur utilisateur utilisé pour ces tests.

Les cinq gates backend/messaging/diagnostics/assistant/push restent false dans les deux produits. Le fork Reports, sa session unique, son brouillon et ses règles de consentement ne sont pas remplacés. Aucun avis automatique n’est ajouté aux scans, transferts ou traitements documentaires.

Application avec garde de chaque empreinte et sauvegarde des deux fichiers existants. Après application : 33 empreintes conformes, 5 468 autres fichiers du snapshot inchangés et sept entrées préexistantes protégées, notamment CompanionEnvoi, DuoOnboardingUITests et les suppressions du dépôt extérieur. Le registre de réutilisation des dossiers a été corrigé ; quatre contrôles synthétiques couvrent rollback après copie partielle, collisions, baseline périmée et réutilisation de ressources.

Preuves sous `Qualification/PortfolioRollout-20261015/millrace` : WRITER-TRANSFER.json, APPLIED.json, POST-APPLY-VERIFICATION.json, BUILT-PRODUCT-QUALIFICATION.json, SUPPORT-TEST-PROVENANCE.json, support-portfolio-tests.log, WRITE-GUARD-CHECKS.json et before-apply. Le candidat antérieur est conservé dans pre-handoff-20261015. Ne pas rejouer un plan déjà appliqué.

## Sept dépôts réservés et travail restant

Aucun transfert confirmé pour les sept autres checkouts ; aucune écriture n’y a été faite par ce rollout. Les réservations sont conservées, conformément au choix du propriétaire. Métadonnées opérationnelles sans contenu de conversation : WRITERS-AFTER-MILLRACE.json.

| Projet | Checkout | Qualification du candidat exporté |
| --- | --- | --- |
| Lumen + LumenTV | `/Users/kevin/GitHub/Lumen for Frigate` | Mac/iOS/tvOS ; catalogue TV par QR, demandes automatiques liées au parrainage/connexions/alertes retirées |
| Clasp | `/Users/kevin/GitHub/Clasp` | Mac/iOS et 11 tests ; prompts premier snippet/dixième collage/parrainage retirés |
| Filova | `/Users/kevin/GitHub/Filova` | Mac/iOS ; quatre contrats du service exécutés dans un harnais Mac isolé, source de service exacte |
| Kernel | `/Users/kevin/GitHub/Kernel` | Mac/iOS et 15 tests ; KernelWindow a changé depuis capture, proposition sous kernel/Reconcile-20261015 à requalifier |
| SiliconPass | `/Users/kevin/GitHub/SiliconPass` | Mac/iOS ; catalogue hors ligne depuis l’aide, aucun avis automatique |
| Vif | `/Users/kevin/GitHub/AirDrop` | Package SDK et hôte d’aide/licences Mac/iOS ; build complet arrêté par la garde FFI liée au checkout et au refus de /tmp symbolique |
| DNS Sinkhole | `/Users/kevin/GitHub/Sinkhole` | Client iOS et console Mac Home ; catalogue sans modification du filtrage ni avis automatique |

Restent : fin/transfert confirmé de chaque écriture, nouvelle capture des sources vivantes, réconciliation et validation, puis application gardée. Les candidats compilés qualifient leurs copies, pas les changements ultérieurs des autres sessions. Les diffs omettent les fichiers vivants devenus conflictuels ; ne pas écraser leurs versions récentes.

Point de reprise du 15 octobre à 16:28 UTC : activité récente des sept sessions parentes, aucun nouveau transfert d’écriture confirmé. Filova est proposé comme prochain lot : trois fichiers préparés, builds Mac/iOS et quatre contrats déjà réussis, à réconcilier avec les sources vivantes après libération. Empreintes des fichiers planifiés : seule KernelWindow présente une dérive ; ce contrôle ne requalifie pas les arbres complets. Reçu : NEXT-CHECKPOINT.json. Aucun checkout réservé modifié, aucune nouvelle ressource externe créée.

Recontrôle du 15 octobre après 20:19 UTC : activité récente des sept sessions, toujours aucun transfert confirmé. Les fichiers planifiés Filova restent identiques à leur baseline ; seule KernelWindow diffère dans les sept plans. Observation enregistrée dans NEXT-WRITER-CHECK.json, sans contenu de conversation. Pour permettre au propriétaire de poursuivre avec l’écrivain Filova déjà actif, consigne prête sous `filova/HANDOFF-FOR-CURRENT-WRITER.md` ; aucun message envoyé à cette session et aucun fichier Filova appliqué par la mission SDK. Les validations doivent être reprises sur ses sources vivantes. Aucune ressource externe créée.

Consignes propriétaires complétées pour les sept projets réservés : index `Documentation/PortfolioSDK-Handoffs-2026-10-15.md`, avec un prompt commun et une consigne bornée par checkout sous `<clé>/HANDOFF-FOR-CURRENT-WRITER.md`. Les six nouvelles consignes décrivent leurs périmètres, builds antérieurs, préservation des adaptations et revalidation nécessaire. Le conflit KernelWindow et le build complet FFI Vif restent explicitement ouverts. Aucun envoi aux sessions, aucune application supplémentaire, aucun changement de propriétaire ou de statut de validation. Restent la transmission par le propriétaire, l’intégration dans chaque session écrivain et la vérification des sources et preuves retournées. Aucune ressource externe créée.

Reprise directe demandée pour les sept intégrations restantes : les consignes sont conservées comme références techniques, sans nécessité de transmission manuelle. Au contrôle de 20:28 UTC, six sessions montrent encore une activité récente ; Vif présente un événement turn_aborted à 20:21 UTC, qui ne constitue pas un transfert confirmé de sa réservation. Aucun nouveau checkout repris en écriture. Le prochain gate reste la libération de l’écrivain du dépôt repris, puis capture fraîche, réconciliation, validation et application gardée. État détaillé dans CURRENT-STATUS.json, champ directIntegration. Aucun message envoyé aux autres sessions, aucune ressource externe créée.

Continuation après 21:00 UTC : Vif avait terminé une tâche à 20:59:05 UTC, puis a commencé une nouvelle tâche à 21:01:09 UTC pendant la vérification, avant toute reprise en écriture. Les sept réservations sont conservées ; aucun dépôt applicatif modifié. Métadonnées de cycle de vie seulement dans WRITERS-DIRECT-CONTINUATION.json. Une réponse de libération effective des sessions est attendue avant l’application directe ; la demande générique de continuation ne prouve pas leur arrêt. Les candidats et consignes demeurent disponibles, les validations antérieures inchangées. Aucune ressource externe créée et aucun agent lancé, interrompu ou contacté par cette mission.

La qualification UI iPhone Sève reste bloquée par une attribution Throttle non confirmée (request/status/release). Runtime iOS 27.0 disponible, aucun nouvel UDID confirmé et aucun boot/test ayant contourné l’admission. La qualification complète FFI Vif reste ouverte ; aucune garde de provenance contournée.

## Sève : complément SDK préparé, application bloquée

Le propriétaire demande de travailler uniquement sur les projets disponibles et de laisser continuer les autres sessions. Vérification en lecture seule des quatorze intégrations appliquées : 966 empreintes conformes, aucune dérive ; reçu AVAILABLE-WORK-RECHECK.json.

Sève conserve son intégration précédente mais son coordinateur embarqué précède l’ajout de `additionalEligibility`. Une capture fraîche de 1 565 fichiers sans dérive initiale et 91 entrées Git préexistantes a permis de préparer deux fichiers seulement : `Packages/LorisLabsKit/Sources/LorisLabsKit/Review/ReviewPromptOnAppearModifier.swift` et `Packages/LorisLabsKit/UPSTREAM.json`. Le package Reports, les autres empreintes de provenance et les sources métier ne sont pas remplacés. Le build iPhone Release non signé du candidat réussit.

Pendant qualification, trois fichiers vivants ont changé : OnboardingAccessibilityUITests.swift, SevePlusStore.swift et PaywallView.swift. La garde complète de baseline a arrêté l’application avant toute écriture et avant création des sauvegardes. Les deux fichiers cibles restent à leurs empreintes initiales. Ces changements extérieurs sont préservés ; l’absence de session Foods récente dans les métadonnées Codex ne prouve pas l’absence d’un autre écrivain. Sève est désormais réservée pour ce complément.

L’export des candidats est renforcé pour rendre `applicationAllowed` false dès qu’un fichier du snapshot vivant a changé, même hors du plan SDK. Deux contrôles synthétiques réussissent : baseline inchangée admissible, modification extérieure hors patch refusée ; aucun checkout applicatif utilisé par ces contrôles et fixtures supprimées.

Preuves durables sous `Qualification/PortfolioRollout-20261015/seve` : BASELINE.json, PREEXISTING-CHANGES.json, PLAN.json, REVIEW.patch, CANDIDATE.json, candidate-files, iOS-build.log, APPLICATION-BLOCKED.json, EXPORT-GUARD-CHECKS.json et CLEANUP-VERIFIED.json. Candidat non appliqué ; requalification nécessaire après fin ou transfert confirmé de l’écrivain, car le build ne qualifie pas les modifications extérieures ultérieures. Aucun test UI iPhone exécuté, aucune nouvelle demande de simulateur ni aucun boot direct. La lecture du registre Throttle confirme uniquement l’ancienne ressource libérée ; aucune configuration partagée n’a été modifiée. Parent source, copie Sève et dossier de build isolé supprimés ; zéro ressource propre active.

## Ressources et passation

Les copies sources, dossiers de build, données de test et parent temporaire propres sont supprimés après export/vérification. Aucun processus propre actif, aucun simulateur créé dans le lot Millrace. Aucun dossier, cache, processus ou simulateur d’une autre session nettoyé.

État courant : `Qualification/PortfolioRollout-20261015/CURRENT-STATUS.json` et STATE.json ; ce dernier contient le travail terminé/restant, validations, blocages, autorisations et ressources sans transcript privé. Sources canoniques figées dans sdk-source avec SDK-HASHES.json. Les scripts sont bornés à cette mission, pas un installeur général ni une permission d’écrire dans un dépôt réservé. La signature, les archives, les parcours natifs et l’activation réseau ne sont pas revendiqués.

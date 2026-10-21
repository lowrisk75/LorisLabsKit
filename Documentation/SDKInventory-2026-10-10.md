# Inventaire local du SDK — 10 octobre 2026

## Travail terminé

Inventaire en lecture seule des sources applicatives et des dépendances Swift/Xcode dans `/Users/kevin/GitHub`, `/Users/kevin/Documents/ChatGPT` et `/Users/kevin/Documents/Codex`. Treize projets applicatifs confirmés. Le module principal et le support peuvent être livrés ensemble ou sous forme de copies embarquées renommées ; cette liste ne signifie pas que toutes les fonctions du SDK sont utilisées.

| App / projet | Modules constatés dans le code applicatif | Source de vérification |
| --- | --- | --- |
| 404 | LorisReports | [Contexte support](/Users/kevin/GitHub/404/404/Services/Network404BugReportContext.swift:2) |
| Clasp | LorisLabsKit + LorisReports | [Projet Xcode](</Users/kevin/GitHub/Clasp/Clasp 2.xcodeproj/project.pbxproj>) |
| Filova | LorisLabsKit + LorisReports | [Services](/Users/kevin/GitHub/Filova/Filova/Core/FilovaServices.swift:3) |
| Kernel | LorisLabsKit + LorisReports, sous-ensembles KernelEngagement et KernelSupport ; paywall existant | [Intégration](/Users/kevin/GitHub/Kernel/Support/KernelIntegration.swift:2) |
| Kiosk | LorisReports via KioskSupport, apps Admin et Bridge | [Dépendance](/Users/kevin/Documents/ChatGPT/Kiosk/Packages/KioskSupport/Package.swift:25) |
| Lumen for Frigate | LorisLabsKit + copie du support LumenFeedbackSDK | [Projet Xcode](</Users/kevin/GitHub/Lumen for Frigate/Lumen for Frigate.xcodeproj/project.pbxproj>) |
| Lumen Bridge | LorisLabsKit + LorisReports (raccordement ajouté le 11 octobre) | [Intégration](/Users/kevin/GitHub/lumen-bridge/LumenBridge/Services/BridgeSupport.swift:1) |
| Millrace | LorisReports via MillraceSupport | [Dépendance](/Users/kevin/GitHub/Millrace/Millrace/Packages/MillraceSupport/Package.swift:8) |
| SiliconPass | LorisReports via SiliconPassSupport | [Adaptateur](/Users/kevin/GitHub/SiliconPass/App/Support/SPAppSupport.swift:7) |
| TypeMetrics | LorisLabsKit + copie du support TypeMetricsFeedbackSDK | [Projet Xcode](/Users/kevin/GitHub/TypeMetrics/TypeMetrics.xcodeproj/project.pbxproj) |
| Velya | Copie du support VelyaFeedbackSDK | [Vue support](/Users/kevin/GitHub/Velya/Velya/Views/Settings/VelyaFeedbackView.swift:3) |
| Vif / AirDrop | LorisReports via VifSupport | [Vue aide](/Users/kevin/GitHub/AirDrop/apple/Shared/VifHelpView.swift:3) |
| Weave / Remote | LorisLabsKit + LorisReports | [Intégration](/Users/kevin/GitHub/Remote/Weave/Sources/Core/LorisLabsIntegration.swift:2) |

## Validations

- Présence croisée dans les imports du code applicatif et les déclarations de dépendances Swift/Xcode ; inspection des wrappers pour les modules renommés.
- Doublons `404-sota`, worktrees, copies de qualification, snapshots sous `iphone DUO` et dépôts imbriqués exclus du décompte.
- Les pistes du contexte global ont été revérifiées dans les fichiers locaux. Aucun contenu de conversation privée n'est conservé ici.
- Aucun changement applicatif, build, test, activation serveur, commit ou publication effectué pour cet inventaire. Seul ce journal est ajouté au checkout du SDK.

## Travail restant et limites

La demande de liste est terminée. Les versions effectivement distribuées, la qualification de chaque plateforme et les activations serveur ne sont pas vérifiées par cet inventaire. Plusieurs intégrations conservent des gates de messagerie désactivées ; la présence du SDK ne prouve donc pas que le support est accessible aux utilisateurs.

## Blocages

Aucun pour l'inventaire local. Aucun transfert d'écriture à un autre agent n'a eu lieu.

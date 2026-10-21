> **Addendum du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) et sa matrice de qualification avant les consignes historiques ci-dessous. Les nouvelles fonctions sont implémentées localement, avec gates false ; aucune nouvelle activation serveur ni publication.

# Inventaire et handoffs SDK — 5 octobre 2026

Sources actuelles inspectées dans GitHub, rapports datés d’intégration, dépendances et endpoint public. Cet inventaire distingue les intégrations constatées aujourd’hui de celles déjà présentes. Il ne garantit pas l’exhaustivité des dépôts hors de ce dossier, des branches non ouvertes ou des modifications encore en cours dans d’autres sessions.

Les instructions sont préparées ici pour les sessions de chaque projet ; elles n’ont pas été envoyées à une session externe et aucun autre projet n’a été modifié par cet inventaire.

| App | État vérifié | Instruction |
| --- | --- | --- |
| Filova | Messagerie macOS/iOS qualifiée, gates true ; visionOS false (HTTPS public 503) ; trois builds Release signés et 7 tests finaux passent ; diagnostics/assistant/push false ; trois rapports de qualification effacés | [Filova](Filova.md) |
| Weave | Ajout local retrouvé le 5 octobre ; trois apps, flags désactivés ; contrôle HEAD à corriger | [Weave](Weave.md) |
| Velya | Intégration datée du 4 octobre, FeedbackCenter ; `velya` déjà autorisé | [Velya](Velya.md) |
| Clasp | SDK et ancien BugReportView présents ; ajout ce matin non attesté | [Clasp](Clasp.md) |
| 404 | Ancien BugReportView ; ajout ce matin non attesté ; 404-sota exclu comme doublon | [404](404.md) |
| TypeMetrics | SDK/provider d’export présent ; point d’entrée à vérifier ; ajout ce matin non attesté | [TypeMetrics](TypeMetrics.md) |
| Lumen | Ancien BugReportView ; `lumen` autorisé mais migration v2 non constatée dans ces sources | [Lumen](Lumen.md) |
| Lumen Bridge | Ancien BugReportView ; identité distincte à qualifier ; intégration ancienne | [Lumen Bridge](LumenBridge.md) |
| AirDrop / Vif | Intégration locale text-only du 6 octobre ; builds iOS/macOS, 28 tests SDK/préflight et 2 tests UI passent ; gates false, `vif` non autorisé | [Vif](Vif.md) |

Commencer par [COMMUN.md](COMMUN.md), puis le fichier de l’app. Les clés ci-dessus désignent des dossiers de handoff, pas de nouvelles identités serveur à adopter arbitrairement.

Éclair apparaît dans l’allowlist serveur, mais aucune intégration SDK dans ses sources n’est attestée par cet inventaire. Cette présence ne suffit pas à l’ajouter aux apps intégrées ce matin. Les sources SDK imbriquées dans Clasp et les copies de validation/worktrees ne sont pas des apps supplémentaires.

Le SDK peut être intégré pour les avis, portfolio ou achats sans activer le support. La correction serveur déjà déployée ne nécessite pas de réintégrer le SDK dans toutes les apps. L’activation/migration client nécessite une nouvelle version de l’app et une qualification native propre.

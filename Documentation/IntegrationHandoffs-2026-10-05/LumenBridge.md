> **Addendum du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) et sa matrice de qualification avant les consignes historiques ci-dessous. Les nouvelles fonctions sont implémentées localement, avec gates false ; aucune nouvelle activation serveur ni publication.

# Instructions à transmettre — Lumen Bridge

Projet : `/Users/kevin/GitHub/lumen-bridge`.

```text
Dans ce projet, prépare/corrige l’intégration support LorisLabs. Lis d’abord
/Users/kevin/GitHub/LorisLabsKit/Documentation/IntegrationHandoffs-2026-10-05/COMMUN.md
puis le présent fichier. Applique les corrections locales nécessaires et teste-les ;
documente les gates serveur et natives restantes avant activation. Préserve le travail existant.
Aucune publication ni modification de service externe dans cette tâche.
```

Intégration SDK déjà existante ; migration LorisReports attestée par l’historique du 29 juillet. `LumenBridge/MainWindow.swift` utilise BugReportView avec `Services/LumenBridgeBugReportContext.swift`.

Lumen Bridge est une app distincte de Lumen. Ne pas réutiliser l’identité `lumen` uniquement pour profiter de son autorisation serveur. Vérifier/choisir une identité propre et demander son activation après qualification. Aucune identité Bridge dédiée n’est attestée dans l’allowlist actuelle.

L’export actuel peut contenir host/port MQTT, dernière erreur, URL Frigate, état de pairing et transcript : ne pas l’envoyer tel quel via Feedback v2. Préparer un provider minimisé de codes fermés. Garder l’export volontaire existant, les fonctions MQTT/HomeKit et l’aide. Aucun réseau support sur les chemins broker/pairing. Vérifier les plateformes de l’app et la dépendance réellement liée. Suivre COMMUN.

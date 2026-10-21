> **Addendum du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) et sa matrice de qualification avant les consignes historiques ci-dessous. Les nouvelles fonctions sont implémentées localement, avec gates false ; aucune nouvelle activation serveur ni publication.

# Instructions à transmettre — TypeMetrics

Projet : `/Users/kevin/GitHub/TypeMetrics`.

```text
Dans ce projet, prépare/corrige l’intégration support LorisLabs. Lis d’abord
/Users/kevin/GitHub/LorisLabsKit/Documentation/IntegrationHandoffs-2026-10-05/COMMUN.md
puis le présent fichier. Applique les corrections locales nécessaires et teste-les ;
documente les gates serveur et natives restantes avant activation. Préserve le travail existant.
Aucune publication ni modification de service externe dans cette tâche.
```

Intégration SDK déjà existante ; provider `TypeMetrics/Services/TypeMetricsBugReportContext.swift` indique un onboarding ancien. C’est `BugReportContextProvider` et un export Markdown ; aucun FeedbackClient/FeedbackCenter trouvé dans l’inventaire des sources.

Vérifier le point d’entrée UI réel : la présence du provider seul ne prouve pas qu’un rapport est accessible depuis l’app. Préparer FeedbackCenter avec client partagé et profil/appID propre, vérifié contre les configurations existantes. Aucune identité TypeMetrics n’est attestée dans l’allowlist actuelle.

Ne pas transmettre le transcript/export en contexte technique automatique. Ne pas envoyer les textes saisis, passage de course, identités des joueurs ou mesures individuelles sans contrat explicite. Garder le diagnostic minimal existant et StoreManager/droits inchangés. Pas d’envoi dans le chemin frappe/course. Suivre COMMUN avant activation.

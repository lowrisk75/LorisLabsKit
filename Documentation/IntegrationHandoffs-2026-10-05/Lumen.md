> **Addendum du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) et sa matrice de qualification avant les consignes historiques ci-dessous. Les nouvelles fonctions sont implémentées localement, avec gates false ; aucune nouvelle activation serveur ni publication.

# Instructions à transmettre — Lumen for Frigate

Projet : `/Users/kevin/GitHub/Lumen for Frigate`.

```text
Dans ce projet, prépare/corrige l’intégration support LorisLabs. Lis d’abord
/Users/kevin/GitHub/LorisLabsKit/Documentation/IntegrationHandoffs-2026-10-05/COMMUN.md
puis le présent fichier. Applique les corrections locales nécessaires et teste-les ;
documente les gates serveur et natives restantes avant activation. Préserve le travail existant.
Aucune publication ni modification de service externe dans cette tâche.
```

Intégration SDK déjà existante ; `Lumen for Frigate/Views/WhatsNewSheet.swift` et `Views/Settings/SettingsView+ServerNotifications.swift` présentent BugReportView avec `Services/BugReport/LumenBugReportContext.swift`. Ne pas confondre ces sources avec FeedbackCenter.

`lumen` est déjà autorisé côté serveur, mais cela ne migre pas automatiquement l’app. Vérifier la révision distante réellement résolue et la disponibilité du contrat v2 avant migration vers `.lumen`, un client partagé et un contexte fermé. Préserver les exports/aide accessibles pendant la transition.

Jamais de caméra, image, flux vidéo, URL Frigate/proxy, jeton, secret push ou logs bruts dans le contexte automatique. Utiliser LumenDiagnosticContext et les états réellement observés ; aucune collecte sur le chemin vidéo/stream. Conserver SubscriptionManager, paywall, ReferralKit et les configurations serveur existantes. Ne pas modifier lumen-bridge dans cette tâche. Suivre COMMUN.

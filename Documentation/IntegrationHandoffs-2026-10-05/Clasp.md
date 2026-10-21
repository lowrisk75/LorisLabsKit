> **Addendum du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) et sa matrice de qualification avant les consignes historiques ci-dessous. Les nouvelles fonctions sont implémentées localement, avec gates false ; aucune nouvelle activation serveur ni publication.

# Instructions à transmettre — Clasp

Projet : `/Users/kevin/GitHub/Clasp`.

```text
Dans ce projet, prépare/corrige l’intégration support LorisLabs. Lis d’abord
/Users/kevin/GitHub/LorisLabsKit/Documentation/IntegrationHandoffs-2026-10-05/COMMUN.md
puis le présent fichier. Applique les corrections locales nécessaires et teste-les ;
documente les gates serveur et natives restantes avant activation. Préserve le travail existant.
Aucune publication ni modification de service externe dans cette tâche.
```

Intégration SDK déjà existante ; non attestée comme ajoutée ce matin. `Clasp/Views/SettingsView.swift` présente `BugReportView(provider: ClaspBugReportContext())`, provider dans `Clasp/Services/ClaspBugReportContext.swift`. Le dossier imbriqué LorisLabsKit contient aussi des sources/tests SDK : ne pas les compter comme une seconde app.

Identifier la dépendance réellement liée dans le projet Xcode avant migration. L’ancien BugReportView n’établit pas une conversation Feedback v2. Préparer un profil propre à Clasp et une migration UI vers FeedbackCenter avec client partagé, en conservant l’ancien moyen d’aide. `clasp` serait une proposition d’identité, à vérifier dans toute configuration existante, pas une identité déjà autorisée.

Clasp est absent de l’allowlist actuelle. Suivre COMMUN avant activation. Préserver PremiumService, droits acquis, ReferralKit et clés existantes. Ne pas envoyer l’ancien bundle/transcript comme contexte technique v2.

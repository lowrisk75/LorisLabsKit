> **Addendum du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) et sa matrice de qualification avant les consignes historiques ci-dessous. Les nouvelles fonctions sont implémentées localement, avec gates false ; aucune nouvelle activation serveur ni publication.

# Instructions à transmettre — Velya

Projet : `/Users/kevin/GitHub/Velya`.

```text
Dans ce projet, prépare/corrige l’intégration support LorisLabs. Lis d’abord
/Users/kevin/GitHub/LorisLabsKit/Documentation/IntegrationHandoffs-2026-10-05/COMMUN.md
puis le présent fichier. Applique les corrections locales nécessaires et teste-les ;
documente les gates serveur et natives restantes avant activation. Préserve le travail existant.
Aucune publication ni modification de service externe dans cette tâche.
```

Intégration antérieure : rapport `audit-output/velya-lorisreports-integration-20261004.md` daté du 4 octobre. `project.yml` utilise la révision distante `2bb8246f47ce9299086b9006f71c2dfac1db497e`. Ne pas la remplacer par un SHA local supposé publié.

Lire `Velya/Views/Settings/VelyaFeedbackView.swift` : profil `.velya`, client partagé, context provider et endpoints QA réservés au simulateur. `velya` est déjà autorisé sur le serveur. Aucun changement d’allowlist nécessaire pour cette identité.

Le correctif Inbox/410 est côté serveur/dashboard : ne pas refaire une intégration complète pour ce seul correctif. Vérifier la compatibilité du SDK réellement compilé et qualifier le parcours natif selon COMMUN. Conserver les endpoints QA hors Release. L’état scheduler inconnu doit rester inconnu ; permission depuis AlarmManager. Aucun envoi réseau sur le chemin réveil, programmation, audio ou arrêt d’alarme. Préserver l’aide existante et les consentements ; nouveau build seulement si une modification client est nécessaire.

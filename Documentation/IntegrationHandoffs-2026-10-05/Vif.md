> **Checkpoint du 6 octobre 2026, après intégration :** [VifSDK-Checkpoint-2026-10-06](../VifSDK-Checkpoint-2026-10-06.md) fait foi pour Vif. Intégration text-only appliquée localement aux deux hôtes ; 28 tests SDK/préflight et 2 tests UI iPhone passent, builds Release iOS/macOS non signés passent. `vif` reste absent de l’allowlist, toutes les gates false. Diagnostics/assistant/push absents de ce snapshot minimal, à intégrer et qualifier séparément. Aucun envoi ni changement serveur.

> **Addendum historique du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) pour les fonctions avancées du SDK partagé ; leur présence ne prouve pas leur intégration à Vif.

# Instructions à transmettre — AirDrop / Vif

Projet : `/Users/kevin/GitHub/AirDrop`.

```text
Dans ce projet, prépare/corrige l’intégration support LorisLabs. Lis d’abord
/Users/kevin/GitHub/LorisLabsKit/Documentation/IntegrationHandoffs-2026-10-05/COMMUN.md
puis le présent fichier. Applique les corrections locales nécessaires et teste-les ;
documente les gates serveur et natives restantes avant activation. Préserve le travail existant.
Aucune publication ni modification de service externe dans cette tâche.
```

L’intégration n’est pas attestée dans les sources inspectées : le prompt précédent est une instruction, pas une preuve de réalisation. Le profil `.vif` est prêt dans le SDK local, mais `vif` est absent de l’allowlist actuelle.

Inspecter `apple/project.yml` et les sources de l’app. Intégrer LorisLabsKit/LorisReports avec un chemin relatif vérifié, client partagé et FeedbackCenter depuis Aide. Conserver les offres Pro/Cloud et StoreKit existants. Utiliser `.vif` pour le support, avec contextes fermés de transfert/permission ; pas de noms de fichier, contenu, chemin, nom/adresse de pair ni logs.

Demande serveur : autoriser `vif` après validation, sans étendre les agents distants. Garder l’aide actuelle et l’envoi indisponible avant les gates. Vérifier iOS et macOS natifs, le même appID, la capacité privée locale et les nouveaux builds. Aucun réseau support sur discovery, pairing ou transfert. Suivre COMMUN.

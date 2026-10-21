> **Addendum du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) et sa matrice de qualification avant les consignes historiques ci-dessous. Les nouvelles fonctions sont implémentées localement, avec gates false ; aucune nouvelle activation serveur ni publication.

# Instructions à transmettre — Weave

Mise à jour après autorisation spécifique du 5 octobre : les trois appIDs sont maintenant autorisés ; Viewer et iOS sont qualifiés et leurs flags source sont à true. Host reste à false, son interface étant bloquée par un timeout Computer Use. Le résultat daté remplace les constats initiaux ci-dessous : [WeaveActivation-2026-10-05.md](../WeaveActivation-2026-10-05.md).

Projet : `/Users/kevin/GitHub/Remote/Weave`.

```text
Dans ce projet, prépare/corrige l’intégration support LorisLabs. Lis d’abord
/Users/kevin/GitHub/LorisLabsKit/Documentation/IntegrationHandoffs-2026-10-05/COMMUN.md
puis le présent fichier. Applique les corrections locales nécessaires et teste-les ;
documente les gates serveur et natives restantes avant activation. Préserve le travail existant.
Aucune publication ni modification de service externe dans cette tâche.
```

Intégration locale retrouvée dans le travail du 5 octobre et vérifiée dans `Sources/Core/LorisLabsIntegration.swift` / `project.yml`. SDK local `../../LorisLabsKit`. Cibles Host macOS, Viewer macOS, Viewer iOS.

`WeaveFeedbackBackendVerified` est false pour les trois apps. Le profil utilise le bundleIdentifier de chaque exécutable, donc les identités actuelles sont `com.lorislab.weave.host`, `com.lorislab.weave.viewer`, `com.lorislab.weave.ios`. Aucune n’est dans l’allowlist actuelle. Le CLI n’est pas une quatrième intégration support à activer.

Corriger `WeaveFeedbackAvailabilityView.checkAvailability()` : actuellement HEAD sur la racine Help. Cette racine avait renvoyé 405 à HEAD lors du diagnostic ; même un 200 ne prouverait pas l’autorisation. Utiliser le GET /v2/apps décrit dans COMMUN, exiger l’appID exact et couvrir liste absente, 405, redirection, panne et annulation. Maintenir l’export diagnostic existant accessible.

Demande serveur : enregistrer les trois appIDs exacts ci-dessus après validation du choix d’identité. Ne pas les remplacer silencieusement par `weave` : cela change le namespace de conversation/capacité et exige une migration explicite. Ne pas étendre les agents distants. Activer les trois flags uniquement pour les builds qualifiés.

Conserver `contextProvider: nil` tant qu’un provider minimisé n’est pas prêt : aucun nom d’hôte, adresse, pairing secret, écran capturé, contenu de transfert ou log brut. Pas d’envoi sur stream, input ou transfert critique. Vérifier réglages macOS et menu Aide iOS compact, FR/EN, et ne pas modifier les signatures/protocoles d’appairage ou les preuves de release existantes.

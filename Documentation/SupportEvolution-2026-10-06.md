# LorisReports — évolution locale du 6 octobre 2026

L’implémentation SDK, CRM et dashboard est appliquée localement. Aucun commit, push, déploiement, envoi APNs réel ou publication d’app n’a été effectué. Les gates des nouvelles fonctions restent **false**. Le support Weave déjà qualifié conserve ses gates de messagerie.

## Comportement implémenté

- Journal technique local opt-in : 24 heures, 1 000 événements, 2 Mio. Champs fermés : composant, opération, résultat, durée bornée, nombre de tentatives et UUID de corrélation. Aucun texte métier, adresse, chemin, identifiant de caméra, horaire de réveil, contenu de fichier, clé ou erreur brute. Stockage privé exclu des sauvegardes. La révocation désactive la collecte et efface le journal ; un marqueur de révocation empêche sa réactivation si un effacement de fichier échoue.
- Sélection de diagnostics par période/composant, revue immuable et confirmation distincte du consentement au journal. Au plus 150 événements/128 Kio par sélection, 20 sélections en attente. Reprise pendant sept jours avec le même bundle et le même payload. Les capacités de conversation restent dans le Keychain. Conservation serveur des diagnostics : au plus 30 jours et jamais au-delà de celle de la demande.
- Assistant explicitement local Apple Foundation Models, avec parcours guidé si le modèle est indisponible. Six tours maximum ; outils en lecture seule, six appels maximum, événements bornés et aide embarquée versionnée. Aucune réparation ni action réseau. Une hypothèse reste à confirmer ; les citations inventées sont refusées. Les précisions alimentent un brouillon relu avant tout envoi. Le modèle Apple effectif n’est pas qualifié par les tests de fallback.
- Notifications : API d’abonnement par demande, jeton APNs en mémoire côté app, chiffré côté serveur avec un domaine de chiffrement distinct. Alerte FR/EN générique et UUID de routage opaque, sans texte de conversation ni capacité privée. Le SDK conserve les delegates de l’hôte ; le propriétaire doit transmettre ses callbacks. Permission explicite après la demande, reprise d’un consentement antérieur sans nouvelle demande de permission, révocation et réconciliation des retraits en attente. Aucun jeton APNs stocké sur disque dans l’app.
- File transactionnelle de notifications opérateur, regroupement sur 30 secondes, backoff, expiration après 24 heures, retrait d’un jeton APNs retournant 410. JWT fournisseur réutilisé au plus 20 minutes entre exécutions du worker, dans un fichier privé. Les envois de tests utilisent un transport synthétique.
- Worker d’effacement dédié, désactivé par défaut : timer 30 secondes, batch 50, budget d’exécution 20 secondes, verrous par sujet, compteurs sans données privées et tombstones signés. Il n’a pas traité le backlog réel du LXC. Les nouveaux liens produit sont retirés dès la demande de suppression ; les données restantes sont supprimées par l’effacement final et la rétention.
- Dashboard : timeline technique, listes des demandes de fonctionnalités et idées, backlog versionné `proposed/accepted/planned/shipped/declined`, liens vers les sources actives. Suggestions de rapprochement par titre normalisé ou échec technique partagé. Liaison à une issue existante seulement après confirmation opérateur.
- Hunt d’opportunités déclenché par l’opérateur : demande récurrente et friction technique récurrente dans les 1 000 derniers rapports actifs. Résultats présentés comme des signaux, avec sources, sans estimation de revenus. Revue obligatoire avant création d’un élément produit. Aucun regroupement, fusion ou validation automatique. L’effacement d’une source invalide le texte dérivé et remet les propositions restantes en revue.

La pertinence du journal dépend des hooks de chaque app : le SDK ne transforme pas un événement absent en preuve. Les raccordements Weave et Filova ajoutent des succès réellement observés ; la couverture de leurs chemins d’échec et des autres domaines reste une gate de qualification. MetricKit fournit uniquement des comptes crash/hang à l’instant de réception, sans call tree ni faux horodatage du crash. La fenêtre locale de 24 heures est appliquée à la lecture et à l’enregistrement ; aucun effacement à une heure exacte n’est promis quand l’app est fermée. Une durée laissée à zéro par un hook n’est pas une mesure de latence.

## Contrat d’intégration

Conserver un `FeedbackClient` par processus. Les nouvelles gates sont indépendantes de la messagerie :

```text
LorisReportsDiagnosticsVerified = false
LorisReportsAssistantVerified = false
LorisReportsPushVerified = false
```

`SupportFeatureConfiguration.forBuild()` les lit. Les configurations injectées doivent recevoir explicitement `features`; l’absence de configuration active ne constitue pas une qualification. Le journal local exige en plus un opt-in utilisateur. Aucun envoi automatique de journal.

Pour une migration d’un ancien `BugReportView`, `FeedbackMigrationCenter` garde l’aide historique tant que **les deux** gates `LorisReportsBackendAllowed` et `LorisReportsMessagingVerified` ne sont pas vraies. Il conserve un client par processus, un contexte nil et le contrôle exact de `/v2/apps`. Pour brancher le push, utiliser un propriétaire explicite de `SupportNotificationCoordinator` et l’injecter dans `FeedbackCenter`, puis transmettre inscription, échec et notification depuis les delegates existants. Ne jamais remplacer un delegate CloudKit, Firebase ou métier. Tester aussi le routage à froid jusque dans Aide ; recevoir une alerte ne prouve pas l’ouverture de la conversation.

API additive :

| Route | Usage |
| --- | --- |
| `GET /v2/apps` | appID exact, HTTPS sans redirection |
| `GET /v2/capabilities` | versions de bundle et disponibilité des nouvelles capacités |
| `POST /v2/reports/{reference}/diagnostics` | sélection explicitement revue ; capability header |
| `PUT /v2/reports/{reference}/notifications` | abonnement borné, topic approuvé par le serveur |
| `DELETE /v2/reports/{reference}/notifications?installation_id=UUID` | retrait de cette installation |
| `GET /internal/reports/{reference}/support-features` | diagnostics et compteurs, sans jeton ni UUID de routage |
| `/internal/product-feedback`, `/internal/related-reports`, `/internal/product-opportunities/hunt` | routes opérateur existantes, aucune extension de portée agent |

`/v2/apps` relu le 6 octobre : Weave Host/Viewer/iOS, `eclair`, `lorislabs.staging`, `lumen`, `velya`. Cette lecture publique n’est pas une nouvelle qualification URLSession d’app. Les autres identités restent non autorisées.

## Dépôts mis à jour

| Projet | Changement local | Activation nouvelle |
| --- | --- | --- |
| Weave | SDK partagé, journal de succès du stream, trois plist et source XcodeGen ; gates de messagerie conservées | false |
| Filova | SDK partagé, événements de fin d’opération typés sans I/O réseau sur le chemin métier ; trois plist | false ; messagerie déjà désactivée conservée |
| SiliconPass | snapshot Reports adapté, UI texte seule et gates d’autorisation conservées ; Keychain support isolé, aucun lien vers coffre/extensions ; provenance et tests mis à jour | false ; appID absent |
| Lumen | snapshot `LumenFeedbackSDK` adapté, disponibilité exacte et adaptations de consentement/410 conservées ; nouvelles API et UI sous gates | false ; entrée v2 toujours DEBUG, aide Release historique conservée |
| Velya | snapshot `VelyaFeedbackSDK` Reports seul, imports et références Xcode/XcodeGen cohérents ; aucun hook sur l’armement des réveils | false |
| TypeMetrics | snapshot `TypeMetricsFeedbackSDK` Reports seul ; autres produits SDK distants conservés ; futur accès natif derrière le contrôle parental, lien support actuel conservé avant activation | false ; appID absent |
| Clasp | Reports seul dans la copie SDK embarquée, autres modules conservés ; migration d’Aide avec fallback historique | false ; appID absent |
| 404 | deux entrées Aide principales prêtes pour la migration, dépendance Reports partagée et fallback historique | false ; appID absent ; TV/vision non qualifiés |
| Lumen Bridge | deux entrées Aide prêtes, dépendance Reports partagée ; identité distincte `lumen-bridge` et fallback conservé | false ; appID absent |
| AirDrop/Vif | handoff mis à jour ; intégration préalable non attestée, aucun ajout d’app inventé | non activé |

Les snapshots gardent la provenance de l’arbre local **non publié**, avec empreintes de fichiers. Une ancienne révision distante ne contient pas ces changements par magie. Les handoffs du 5 octobre sont historiques ; lire leur addendum du 6 octobre en premier.

## Qualification et limites

Tests exécutés sur données synthétiques isolées : SDK **35 réussis** ; CRM **96 réussis** ; dashboard **7 réussis**, types et build support réussis ; snapshots Velya et TypeMetrics **35 chacun**, SiliconPass **18**, Lumen **41 réussis et 1 test HTTPS réel volontairement ignoré**. Migration additive testée sur SQLite isolé. Contrôle SiliconPass : graphe app-only, namespace Keychain, App Groups, gates false et provenance passent. La readiness refuse les tables additives manquantes. La récupération des reçus tolère uniquement l’ordre des catégories de consentement des anciens SDK, tout en refusant un payload différent ou une mauvaise capacité de récupération.

Les builds réellement terminés figurent dans [la matrice de qualification](SupportEvolution-Qualification-2026-10-06.md). Un build non signé ne qualifie ni APNs, ni les entitlements signés, ni le parcours appareil.

Gates encore ouvertes : intégration/qualification des callbacks et du routage push des apps ; topics/provisioning APNs et envoi réel autorisé ; couverture des échecs métier par des hooks fermés ; disponibilité et qualité du modèle Apple local sur appareils ; UI FR/EN, grand texte et accessibilité des nouvelles surfaces ; concurrence PostgreSQL ; déploiement du worker et passage automatique pending → completed/410 sur une identité de qualification séparément autorisée ; réconciliation des manifests/privacy des apps avant activation et distribution.

## Déploiement séparé

Les fichiers CRM et dashboard sont locaux ; les units systemd et règles proxy ne sont pas installées. Les nouveaux réglages `FEEDBACK_SUPPORT_DIAGNOSTICS_ENABLED`, `FEEDBACK_SUPPORT_PUSH_ENABLED` et `FEEDBACK_ERASURE_WORKER_ENABLED` sont false par défaut. Ni Auth, ni WAF, ni DNS, ni `FEEDBACK_AGENT_ALLOWED_APP_IDS`, ni l’allowlist de production n’ont été modifiés dans cette évolution.

Avant un futur déploiement autorisé : sauvegarde privée du code/configuration et snapshot transactionnel DB ; migration additive `20261006_support_features` ; service candidat avec nouvelles capacités désactivées ; attente readiness bornée (par exemple 30 essais de 2 secondes) ; retour au code précédent si readiness échoue avant exposition des nouvelles écritures. Ne pas supprimer les tables additives en rollback. Après des écritures nouvelles, un rollback ne doit jamais rétablir un ancien chemin d’effacement qui ignorerait diagnostics, abonnements ou liens produit. Garder une implémentation d’effacement compatible et ne restaurer aucun contenu effacé.

Activer et qualifier ensuite chaque capacité/cible séparément avec une identité synthétique autorisée, sans autres demandes. Aucune gate true sur la seule base des tests unitaires ou d’un curl. Les secrets, capacités de conversation et jetons APNs ne doivent pas figurer dans les preuves.

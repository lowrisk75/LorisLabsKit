# Qualification locale — 6 octobre 2026

Snapshot final du 6 octobre 2026, après les contrôles Swift de 10 h 58 CEST et le contrôle final du lock Python. Logs privés dans `/private/tmp/lorisreports-evolution-20261005/`. Aucune capacité privée ni valeur de secret n’est reproduite ici. Pas de commit, push, déploiement, signature de distribution, installation sur appareil ni publication.

## Contrats testés

| Composant | Résultat |
| --- | --- |
| SDK canonique LorisReports | 35 tests réussis |
| CRM candidat puis sources locales appliquées | 96 tests réussis sur SQLite synthétique ; un warning Starlette/httpx préexistant |
| Dashboard | 7 tests réussis ; revue obligatoire avant proposition, payload accepté par le serveur, source effacée/410 et brouillon conservé ; contrôles de types et build support réussis |
| Migration CRM additive | upgrade jusqu’à `20261006_support_features` sur une base SQLite isolée ; aucune migration de production |
| Readiness | 503 si une table additive manque, même lorsque les nouvelles capacités sont désactivées |
| Dépendances CRM | lock actualisé pour HTTP/2 : h2/hpack/hyperframe ajoutés, versions existantes conservées ; `uv sync --locked` dans un environnement Python 3.12 isolé puis 96 tests réussis |
| Erasure worker | exécution isolée sur références synthétiques ; disabled par défaut, effacement et tombstone, suppression des diagnostics/abonnements/jobs/liens produit |
| Push worker | transport injecté : regroupement, retries, expiration, jeton invalide/410, payload générique ; JWT testé avec clé synthétique privée |
| Reprise | bundle et payload identiques après relance ; pas de nouvel envoi après acquittement ; récupération compatible avec l’ordre des consentements des anciens clients, mauvaise capacité et payload modifié refusés |
| Assistant | fallback guidé et refus des citations inventées ; aucun modèle Apple réel qualifié |
| SiliconPass snapshot | 18 tests réussis ; protections de texte seul et des deux gates conservées ; journal/assistant/reprise testés séparément |
| SiliconPass isolation | graphe principal/hosts de qualification, App Groups, groupe Keychain et absence du journal brut historique vérifiés ; gates false et provenance vérifiées |
| Lumen snapshot | 41 tests réussis ; 1 test HTTPS réel ignoré volontairement ; disponibilité exacte, offline, 410, consentement et adaptations UI conservés |
| Velya snapshot | 35 tests réussis |
| TypeMetrics snapshot | 35 tests réussis ; produits achat/avis distants préservés |
| Clasp Reports embarqué | 17 tests historiques réussis ; les nouvelles sources Reports correspondent au SDK canonique qualifié |

## Builds terminés

| Cible | Configuration / plateforme | Résultat |
| --- | --- | --- |
| Weave Host | Release macOS non signé | réussi |
| Weave Viewer | Release macOS non signé | réussi |
| Weave Mobile | Debug iOS générique non signé | réussi |
| FilovaMac | Debug macOS non signé | réussi |
| Velya | Debug iOS générique non signé | réussi |
| TypeMetrics | Debug iOS générique non signé | réussi |
| SiliconPass Support Qualification | Debug macOS, host synthétique non signé | réussi |
| LumenMac | Debug macOS non signé | réussi |
| Clasp | Debug macOS non signé | réussi |
| LumenBridge | Debug macOS non signé | réussi |
| 404 | Debug macOS non signé | réussi |

L’essai Weave iOS simultané avec Viewer avait échoué sur le verrou de leur base de build partagée. Reprise iOS seule après Viewer : réussie. Les premiers défauts de compilation Swift, le formulaire produit trop large et l’encodage instable du Set de consentement ont été corrigés puis retestés. Le contrôle de provenance SiliconPass a été actualisé en conservant les empreintes historiques et en vérifiant explicitement les gates false.

Après le dernier ajustement du brouillon assistant (dernière réponse conservée, arrêt du guidage après trois questions et dépassement de taille expliqué sans troncature silencieuse), les tests ont été relancés sur les sources **réellement appliquées** du SDK et des cinq snapshots : tous passent avec les nombres ci-dessus. Les builds app de la table précèdent cet ajustement privé à une UI désactivée ; le nouveau build Weave iOS final a réussi et vérifie le SDK final sur iOS. Pas de qualification runtime de cette UI déduite de ces résultats.

Vérification des 202 fichiers appliqués hors SDK : aucun écart SHA-256 ; puis lock CRM ajouté avec contrôle SHA-256 et sauvegarde privée, soit 203 fichiers distincts. Cinq provenances de snapshots vérifiées sans écart ; 15 plist principaux vérifiés avec les nouvelles gates false. Les références Xcode Velya/TypeMetrics passent `plutil`; le contrôle SiliconPass final passe. Le client HTTP/2 a été construit puis fermé sans requête réseau ; l’environnement de proxy du harness a été exclu seulement pour ce contrôle de construction, sans modifier le transport de production ni prétendre valider son egress.

À la dernière relecture, une modification concurrente de `NSCameraUsageDescription` dans `SiliconPass/App/iOS/Info.plist` a été constatée. Elle a été préservée ; aucune valeur de cette description n’est reproduite ici. Les trois gates LorisReports de ce fichier sont toujours false et le contrôle d’isolation reste réussi. Les 202 autres fichiers appliqués correspondent à leurs empreintes attendues. Ce changement indépendant n’est pas une qualification SDK et n’a pas été annulé pour forcer un snapshot ancien.

## Gates restantes

Les résultats ci-dessus ne qualifient pas une capacité nouvelle en production. Tous les flags diagnostics/assistant/push restent false. Les gates Weave de messagerie existantes n’ont pas été abaissées ou étendues.

- Autorisation distincte et déploiement CRM/dashboard, units worker et migration PostgreSQL ; concurrence PostgreSQL non testée ici.
- Test automatique réel du timer d’effacement sur une demande synthétique autorisée, sans traiter d’autres demandes pour qualifier le timer. Aucun backlog réel n’a été traité pendant cette évolution.
- Propriétaire et forwarding des callbacks push des apps, entitlements signés, topics/environment et clé fournisseur APNs ; inscription, réponse opérateur, alerte générique et routage à froid, relance/reprise/révocation/suppression/410 sur appareils.
- Couverture des échecs métier avec codes fermés et corrélations par opération ; les nouveaux hooks Weave/Filova couvrent pour l’instant des succès observés.
- Qualité du modèle Apple local et parcours guidé FR/EN avec les jeux synthétiques propres à chaque domaine.
- UI des nouvelles surfaces : FR/EN, VoiceOver, grand texte, téléphone/tablette/fenêtres et plateformes pertinentes. Pas de qualification UI ni APNs signée déduite des builds.
- Privacy manifest et déclarations effectives des apps, provenance de toute distribution future. Aucun SDK publié ne porte encore ces sources locales.

Voir [le contrat et l’inventaire](SupportEvolution-2026-10-06.md). Les sauvegardes privées des fichiers locaux ont été faites avant chaque application, avec contrôle SHA-256 de la source et de la destination et restauration des écritures appliquées si l’application échoue. Aucun fichier d’environnement serveur ni secret n’a été inclus dans les preuves.

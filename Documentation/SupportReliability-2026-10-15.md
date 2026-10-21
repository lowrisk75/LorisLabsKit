# Support — reprise renforcée et qualifiée, 15 octobre 2026

Mission Codex terminée, périmètre limité à la supervision Nginx du LXC 185. Un seul agent écrit. Aucun arrêt/redémarrage du service réel, changement de route, d’authentification, de données ou d’apps. Aucun transcript ni secret conservé.

## Cause et défaut couvert

L’incident initial venait de l’ordre de démarrage : Nginx tentait d’écouter sur `10.9.8.185:8080` avant que l’adresse soit disponible, puis restait failed. L’API et la base étaient toujours actives. Le proxy externe ne disposait donc plus d’un serveur joignable et renvoyait 503.

Le correctif du 14 octobre ajoutait attente network-online et reprises, mais ses 12 démarrages autorisés sur 300 s pouvaient être consommés en environ une minute avec un délai de 5 s. Après saturation, systemd ne relance plus seul, même si le prérequis revient ; ce comportement est documenté dans [la source officielle de systemd.unit](https://github.com/systemd/systemd/blob/main/man/systemd.unit.xml) et reproduit par le test ci-dessous.

## Travail terminé

- Inspection initiale en lecture seule : service public disponible, configuration précédente en place.
- Deux unités systemd synthétiques isolées reproduisent un échec ExecStartPre analogue au préflight Nginx ; aucun changement d’interface réseau réelle et aucune interruption de production.
- Correction du seul délai dans l’override existant : **RestartSec=30s**, au lieu de 5 s. Wants/After network-online.target, Restart=on-failure, StartLimitIntervalSec=300 et StartLimitBurst=12 conservés.
- Les relances automatiques espacées restent sous le seuil de saturation, tout en conservant la limite contre une rafale de démarrages. Le retour tardif du prérequis peut donc être suivi d’une nouvelle tentative ; les reprises ne sont pas limitées aux premières dizaines de secondes du boot.
- Écriture atomique avec garde de l’empreinte de l’override possédé, conservation uid/gid/mode, validation systemd puis daemon-reload. Aucun restart de Nginx.

## Validations

- Hôte : **systemd 257.8**. Test accéléré à l’échelle **0,04** : fenêtre de 12 s, ancienne reprise 200 ms, nouvelle reprise 1,2 s, burst 12. Ce test porte sur la politique de supervision, pas sur un reboot physique.
- Prérequis absent **18,714 s**, au-delà d’une fenêtre complète. Ancienne politique : état failed, **12 reprises**, compteur figé après retour du prérequis et journal « Start request repeated too quickly ». Nouvelle politique : état active après **15 reprises** et retour du prérequis. Qualification PASS.
- Le premier harnais attendait Result=start-limit-hit ; cette version conserve Result=exit-code après l’échec ExecStartPre. Critères corrigés pour exiger l’état, le compteur figé et la preuve journal ; aucune assertion de récupération supprimée. Résultat initial et diagnostic conservés.
- Nginx réel : même **PID 7266** avant/après tests et application, active/running. Readiness backend 200. Paramètres effectifs : reprise 30 s, fenêtre 5 min, burst 12. Routes Nginx et environnement CRM inchangés ; aucun rapport consulté ou modifié.
- HTTPS final **2026-10-15T07:15:39Z** : Help /v2/apps et /v2/capabilities **200** ; Feedback racine et API opérateur anonymes **302** vers Authentik. Aucun cookie ou état OAuth stocké.

## Travail restant / limites

Aucun travail restant pour le renforcement ciblé demandé. La reprise de l’échec de démarrage est qualifiée sur des unités réelles isolées. Un redémarrage complet du conteneur et un parcours navigateur authentifié restent des validations distinctes à réaliser en maintenance ; ils ne sont pas revendiqués ici. Ce correctif ne prétend pas qualifier toutes les pannes possibles du backend ou de l’infrastructure.

## Ressources et preuves

Preuves durables : [Qualification/SupportReliability-20261015](../Qualification/SupportReliability-20261015/), qualification, script borné, override, application et postflight public.

Ressources temporaires créées puis supprimées : `/run/feedback-nginx-retry-qualification-20261015`, `feedback-nginx-retry-old-20261015.service`, `feedback-nginx-retry-spaced-20261015.service` et leurs seuls processus sleep. Stop/reset-failed, déchargement des unités et absence du dossier vérifiés en finally. Le fichier d’écriture atomique `.feedback-reliability-20261015.tmp` est absent. Aucun simulateur, build ou processus de mission conservé.

Seul changement durable : `/etc/systemd/system/nginx.service.d/50-feedback-network-retry.conf`, empreinte **557ab2657c2300f7fc2391eea53b2743d554d7932b184b07f0ea14a71e4407f7**. L’ancienne version est conservée dans les preuves du 14 octobre ; avant rollback, vérifier l’empreinte actuelle puis restaurer seulement cet override et daemon-reload. Ne pas arrêter la passerelle saine ni restaurer des données.

## Blocages

Aucun. Modification serveur bornée autorisée, appliquée et vérifiée. Aucun commit, push, déploiement applicatif, changement d’allowlist/gate ou message externe effectué.

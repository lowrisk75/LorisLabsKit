# File des mises à jour SDK — 15 octobre 2026

Quatorze projets du rollout sont intégrés localement ; sept disposent de candidats réservés à leurs écrivains. Sève a été intégrée auparavant : un complément SDK de deux fichiers compile, mais son application est désormais bloquée par des modifications extérieures observées ; sa qualification iPhone reste ouverte. Huit checkouts sont donc réservés, dont Sève pour ce complément seulement. État autoritaire et preuves : [journal de déploiement](PortfolioSDK-Rollout-2026-10-15.md), [passation des sept réservations initiales](PortfolioSDK-ReservedProjects-2026-10-15.md) et `Qualification/PortfolioRollout-20261015/CURRENT-STATUS.json`.

Millrace et Millrace Scan ont été appliqués après confirmation de fin de l’autre session, nouvelle capture, builds Mac/iOS, onze tests et gardes d’empreintes. Leurs changements antérieurs sont préservés. Aucune permission de publication ou d’activation serveur n’est déduite de cette liste.

| App / projet | État local | Checkout vérifié |
| --- | --- | --- |
| Lumen for Frigate + LumenTV | Candidat compilé ; transfert d’écriture et rebase requis | `/Users/kevin/GitHub/Lumen for Frigate` |
| Clasp | Candidat compilé ; transfert d’écriture et rebase requis | `/Users/kevin/GitHub/Clasp` |
| TypeMetrics | Intégré et compilé localement | `/Users/kevin/GitHub/TypeMetrics` |
| 404 Network | Intégré et compilé localement | `/Users/kevin/GitHub/404` |
| Filova | Candidat compilé ; transfert d’écriture et rebase requis | `/Users/kevin/GitHub/Filova` |
| Kernel | Candidat compilé ; transfert d’écriture et rebase requis | `/Users/kevin/GitHub/Kernel` |
| Meetglow / Kiosk | Intégré et compilé localement | `/Users/kevin/Documents/ChatGPT/Kiosk` |
| Millrace + Millrace Scan | Intégré Mac/Scan ; deux builds et onze tests réussis | `/Users/kevin/GitHub/Millrace` |
| SiliconPass | Candidat compilé ; transfert d’écriture et rebase requis | `/Users/kevin/GitHub/SiliconPass` |
| Velya | Intégré et compilé localement | `/Users/kevin/GitHub/Velya` |
| Weave | Intégré et compilé localement | `/Users/kevin/GitHub/Remote/Weave` |
| Vif | Candidat SDK/aide compilé ; FFI complet non qualifié, écrivain conservé | `/Users/kevin/GitHub/AirDrop` |
| Lumen Bridge | Intégré et compilé localement | `/Users/kevin/GitHub/lumen-bridge` |
| Aegis | Intégré et compilé localement | `/Users/kevin/GitHub/Aegis` |
| AuroraPulse | Intégré et compilé localement | `/Users/kevin/GitHub/AuroraPulse` |
| DNS Sinkhole | Candidat compilé ; transfert d’écriture et rebase requis | `/Users/kevin/GitHub/Sinkhole` |
| EntroFold Archive | Intégré et compilé localement | `/Users/kevin/GitHub/WINRAR/EntroFoldArchive` |
| Halte | Intégré et compilé localement | `/Users/kevin/GitHub/halte` |
| Kalou | Intégré et compilé localement | `/Users/kevin/GitHub/Dog` |
| Mela AAC | Intégré et compilé localement | `/Users/kevin/GitHub/Mela` |
| Rampart | Intégré et compilé localement | `/Users/kevin/GitHub/Rampart` |
| Sève | Intégré auparavant ; complément SDK de deux fichiers compilé mais non appliqué, écriture extérieure détectée ; qualification iPhone restante | `/Users/kevin/GitHub/Foods` |

Les builds qualifient les candidats testés, sans preuve de distribution, signature ou parcours UI natif des nouveaux hosts. Conserver forks Reports, moteurs métier, gates et données locales. Les sept candidats réservés ne doivent pas être copiés directement sur des sources ayant évolué : reprise depuis les fichiers vivants et nouvelle validation requises. Pour Kernel, une proposition de réconciliation est conservée, avec ses empreintes ; pour Vif, aucune garde de provenance FFI n’a été contournée.

Toutes les ressources temporaires propres sont nettoyées. Aucun contenu de conversation privée conservé dans les journaux. Les versions des stores ne sont pas modifiées par ce rollout.

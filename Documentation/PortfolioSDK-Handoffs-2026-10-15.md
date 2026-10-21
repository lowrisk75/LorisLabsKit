# Consignes SDK pour les sessions propriétaires

Quatorze lots sont intégrés localement par la mission SDK. Sept projets restent réservés à leurs sessions propriétaires. Ces consignes permettent au propriétaire de demander l’intégration dans la session déjà écrivain, sans transférer l’écriture à cette mission. Aucun message n’a été envoyé aux autres sessions et aucune intégration supplémentaire n’est revendiquée.

Prompt commun à coller dans chacune des sessions concernées :

```text
Lis /Users/kevin/GitHub/LorisLabsKit/Documentation/PortfolioSDK-Handoffs-2026-10-15.md. Repère uniquement le projet correspondant à ton checkout et lis sa consigne HANDOFF-FOR-CURRENT-WRITER.md. Si tu es son unique écrivain, intègre le lot SDK sur les sources vivantes, préserve les changements existants et revalide les builds et tests pertinents. Ne modifie ni le checkout SDK partagé ni un autre projet. Consigne le résultat dans ton journal et donne son chemin.
```

| Projet | Checkout propriétaire | Consigne |
| --- | --- | --- |
| Filova | `/Users/kevin/GitHub/Filova` | [Filova](../Qualification/PortfolioRollout-20261015/filova/HANDOFF-FOR-CURRENT-WRITER.md) |
| Lumen + LumenTV | `/Users/kevin/GitHub/Lumen for Frigate` | [Lumen + LumenTV](../Qualification/PortfolioRollout-20261015/lumen/HANDOFF-FOR-CURRENT-WRITER.md) |
| Clasp | `/Users/kevin/GitHub/Clasp` | [Clasp](../Qualification/PortfolioRollout-20261015/clasp/HANDOFF-FOR-CURRENT-WRITER.md) |
| Kernel | `/Users/kevin/GitHub/Kernel` | [Kernel](../Qualification/PortfolioRollout-20261015/kernel/HANDOFF-FOR-CURRENT-WRITER.md) |
| SiliconPass | `/Users/kevin/GitHub/SiliconPass` | [SiliconPass](../Qualification/PortfolioRollout-20261015/siliconpass/HANDOFF-FOR-CURRENT-WRITER.md) |
| Vif | `/Users/kevin/GitHub/AirDrop` | [Vif](../Qualification/PortfolioRollout-20261015/vif/HANDOFF-FOR-CURRENT-WRITER.md) |
| DNS Sinkhole | `/Users/kevin/GitHub/Sinkhole` | [DNS Sinkhole](../Qualification/PortfolioRollout-20261015/sinkhole/HANDOFF-FOR-CURRENT-WRITER.md) |

Les validations antérieures portent sur les candidats : Lumen Mac/iOS/tvOS ; Clasp Mac/iOS et 11 tests ; Kernel Mac/iOS et 15 tests ; Filova Mac/iOS et quatre contrats isolés ; SiliconPass Mac/iOS ; Sinkhole client iOS et console Mac. KernelWindow doit être réconcilié avec sa version vivante. Vif conserve un blocage de qualification complète FFI : seul le package support et l’hôte minimal d’aide/notices Mac/iOS sont qualifiés.

Les journaux des sessions propriétaires feront foi pour leur application effective. Mettre à jour le statut central seulement après vérification des sources et des preuves retournées. Ne jamais convertir une consigne préparée en statut « intégré ».


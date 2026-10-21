# Filova — handoff actualisé le 7 octobre 2026

Lire [activation et handoff final](../FilovaActivation-2026-10-07.md) et [COMMUN](COMMUN.md). Les correctifs sont déjà appliqués dans `/Users/kevin/GitHub/Filova` : messagerie macOS/iOS qualifiée et gates true ; visionOS false. Diagnostics/assistant/push false partout. Trois builds Release signés et sept tests app finaux passent.

`filova` a été ajouté à l’allowlist le 6 octobre, avec sauvegarde/readiness/rollback et préservation des secrets/apps/agents. Les trois rapports synthétiques sont effacés. L’URL publique renvoie actuellement 503 malgré readiness locale ready : réparer l’entrée HTTPS dans une tâche d’administration autorisée, puis refaire les gates natives manquantes de visionOS. Ne pas déduire la qualification du worker automatique, d’APNs ou des appareils physiques.

Ne pas recoller les patches déjà appliqués. Exécuter `python3 scripts/verify-feedback-integration.py`, préserver les sources concurrentes et le support email. Le [patch d’activation de revue](../../Qualification/FilovaActivation-20261006/ACTIVATION-APP.patch) et les inventaires sourcés sont fournis ; les copies QA ne sont pas des sources produit. Aucun commit/push/distribution.

Historique : [checkpoint SDK et reprise du 6 octobre](../FilovaSDK-Checkpoint-2026-10-06.md), [fonctions avancées](../SupportEvolution-2026-10-06.md).

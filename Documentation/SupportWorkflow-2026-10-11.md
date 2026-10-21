# Support — gestion des demandes, 11–12 octobre 2026

Écrivain unique : Codex. Mission limitée au CRM et au tableau de support existants ; aucun changement des apps, des gates SDK ou des credentials APNs. Préserver les modifications locales et les protections du serveur.

## Terminé

- Inspection en lecture seule des sources CRM, dashboard, proxy et tests existants.
- Résolution déjà disponible comme type de message, mais sans action directe. Archivage, dossiers et tags absents du modèle et de l'interface.
- Candidat isolé sous `/private/tmp/lorislabs-support-workflow-20261011`, avec baseline des sources locales et vivantes ; aucune donnée de rapport ou credential exporté.
- Actions directes : résoudre/réouvrir sans publier de message, archiver/désarchiver, enregistrer un dossier et jusqu'à dix tags. Nouvelle réponse utilisateur : réouverture et désarchivage ; une reprise du même message ne répète pas cette transition.
- Vues Inbox, Resolved, Archived, All reports ; filtres serveur par titre/référence/app, dossier, tag ; compteurs et pagination. Les filtres sont appliqués avant la limite.
- Suppression opérateur définitive après saisie exacte de la référence, via le service d'effacement existant ; conversation, diagnostics, classement et liens sont purgés. Tombstone minimal conservé. Archivage indépendant de la résolution, sans prolonger la rétention.
- Migration additive `20261011_report_workflows` ; aucune modification du contenu des rapports existants. Version du classement et version de conversation contrôlées ; conflit 409 sans écriture partielle. Journal d'audit sans noms de dossiers/tags ni texte utilisateur.
- Sources CRM locales réconciliées avec les protections déjà déployées scanner/artifacts et APNs par environnement. Baselines intégrales inchangées avant application : 18 fichiers CRM et 7 fichiers frontend appliqués, sauvegarde locale `local-before-workflow` dans le dossier candidat.
- Déploiement réussi le 12 octobre : backend, migration, dashboard et routes bornées. Sauvegarde privée finale `/root/feedback-support-backups/workflow-20261012T072450Z`. Environnement, credentials, gates et capacités avancées inchangés ; anciens assets conservés ; aucune restauration de base.
- Première tentative : backend/migration installés, puis interface/proxy revenus à l'état précédent après un contrôle HTTP ciblant le listener Help. Backend nouveau conservé pour garantir l'effacement du classement. Contrôle corrigé vers le listener dashboard avec source loopback, empreintes relues, puis interface/proxy déployés avec succès. Sauvegarde initiale `/root/feedback-support-backups/workflow-20261012T060515Z`.

## Reste à faire

- Aucune tâche restante pour les cinq fonctions demandées. Recharger entièrement un ancien onglet pour charger le nouveau JavaScript ; Refresh actualise seulement les données.
- Qualification mobile et VoiceOver complète non effectuée. Ces limites ne bloquent pas les parcours desktop vérifiés ; aucune certification d'accessibilité revendiquée.
- Le reste de l'activation SDK et le diff APNs Kernel restent dans `PortfolioActivation-2026-10-10.md` ; cette intervention ne les active pas.

## Validations

- 122 tests backend ; 15 tests web (3 API + 12 UI). TypeScript/Svelte : zéro erreur ; 15 avertissements préexistants dans les écrans non support. Build isolé du dashboard réussi.
- PostgreSQL isolé : 22 tests réussis, 2 cas SQLite/configuration exclus ; migration d'une demande synthétique préexistante avec hash identique ; concurrence entre deux opérateurs : une seule écriture réussit. Base et rôle temporaires supprimés.
- Safari local, données synthétiques : rendu, résolution silencieuse, archivage, dialogue de suppression et annulation vérifiés. Safari authentifié en ligne : nouvelles vues et commandes visibles, sans modification de demande réelle.
- Prévisualisation locale arrêtée et onglet temporaire fermé ; site de support déployé laissé ouvert pour revue.
- Après déploiement : 44 fichiers source serveur et cinq assets servis vérifiés par SHA-256 ; API et Nginx actifs. Forme des réponses classement/compteurs/pagination vérifiée. HTTPS public : Help 200, dashboard 302 vers l'authentification, TLS valide.
- Routes workflow/erase : origine absente ou différente refusée (403), méthode DELETE refusée (403), bonne origine vers référence fictive inexistante (404). Aucune extension des routes agent ni accès à la complétion arbitraire d'effacements. Aucun message envoyé ou rapport réel résolu, classé, archivé ou supprimé.
- Preuves et scripts : [Qualification/SupportWorkflow-20261011](../Qualification/SupportWorkflow-20261011/), manifeste SHA256.json. Aucun secret, profil Apple, base réelle, rapport réel ou transcript privé dans ce dossier.

## Blocages

Aucun blocage pour ce correctif. Aucun commit ni push effectué. Avant un futur changement, partir des sources vivantes réconciliées et vérifier les empreintes ; les anciens plans de déploiement ne s'appliquent plus tels quels.

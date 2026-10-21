# Support — déploiement et preuves du 2026-10-05

## Résultat

Correctifs CRM et dashboard publiés sur le service qui sert `help.lorislab.fr` et `feedback.lorislab.fr`. Aucune migration, aucune modification de configuration réseau/Auth et aucune restauration de données. Les rapports utilisateur existants n’ont pas été modifiés par la qualification.

- Service CRM et Nginx : actifs ; `/readyz` répond `ready`.
- Backend : 3 modules remplacés ; dashboard : HTML et nouveaux assets vérifiés par SHA-256. Les assets précédents sont conservés pour les onglets déjà ouverts.
- Liste CRM **et** proxy dashboard : 0 rapport consultable après le nettoyage du seul rapport synthétique. Les anciens reçus supprimés restent attestés côté serveur mais sont exclus de l’Inbox.
- Ancien rapport supprimé : détail renvoie 410 via le backend et via le proxy du dashboard ; ce statut est maintenant traité par le frontend.
- Help : HTTP 200. Dashboard sans session : HTTP 302 vers Authentik ; la protection opérateur reste en place.

## Parcours en ligne effectivement testé

Avec une identité aléatoire sous l’application autorisée `lorislabs.staging`, sans donnée utilisateur, diagnostic, pièce jointe, email ni consentement IA distant :

1. Challenge et envoi sur le HTTPS public : rapport accepté.
2. Réception et ouverture par l’API opérateur authentifiée.
3. Réponse synthétique de l’équipe, destinée exclusivement à cette identité de test.
4. Lecture de la réponse par le client sur le HTTPS public.
5. Demande de suppression publique : rapport immédiatement exclu de l’Inbox et accès à la conversation retiré (410).
6. Effacement confirmé par le service ; état public `completed`, accès 410. La capacité privée synthétique a été supprimée du poste de test.

Ce parcours utilise un client HTTP de qualification, pas une application native ni une session navigateur opérateur. Il ne prouve pas encore l’intégration de Vif sur appareils.

## Validation et divergences conservées

- 84 tests backend passent sur une copie exacte du code serveur avec les correctifs ; 8 tests web passent, vérification TypeScript sans erreur, build isolé du support passé, tests macOS SDK passés.
- Le serveur avait des versions plus récentes de `scanner.py` et `artifacts.py` que le dossier CRM local. Elles ont été préservées. La première tentative de publication a été arrêtée par le contrôle préalable avant modification.
- Une tentative suivante a été restaurée automatiquement : le contrôle HTML interrogeait le listener Help en loopback. Le contrôle a été corrigé pour utiliser le listener dashboard réel ; la publication finale a passé les vérifications.
- Le code source CRM local n’a pas de métadonnées Git. Utiliser les hashes et le snapshot serveur, pas une supposition de HEAD, pour préparer une prochaine publication.

## Référence de publication

Conteneur dédié : LXC 185. Code : `/opt/feedback-crm/src/feedback_crm`. Dashboard : `/var/www/feedback-dashboard`.
Sauvegarde finale : `/root/feedback-support-backups/20261005T110159Z` (source, dashboard et configuration root-only). Aucun dump de données n’a été créé pour ce correctif sans migration. Ne jamais restaurer du contenu effacé pour revenir à une version précédente.

| Module publié | SHA-256 |
| --- | --- |
| `api.py` | `e612f45e5f2dbb139ec2266b432b63cd83c424717ac84b02408e13687b4d4062` |
| `conversations.py` | `39dff57c935e19b73ec193591a115fea3251cc754cf006bf61927dcc4d12dbda` |
| `report_access.py` | `218f29cfd9da51a613b33979a826296008eac9a416119380da7d0d4c5cb8451a` |

Assets principaux : `/assets/support-D8TopBAD.js`, `/assets/support-CB17zq9A.css`.

## Limites encore ouvertes

- Vif : profil SDK disponible, activation serveur non effectuée. L’allowlist effective reste `eclair,lorislabs.staging,lumen,velya`; la portée des agents reste inchangée. L’intégration native doit être validée avant activation.
- Le client Python urllib est refusé par Cloudflare avec le code 1010, alors que le parcours HTTPS curl passe. Aucune règle WAF n’a été modifiée. Vérifier explicitement URLSession/CFNetwork sur les apps pilotes avant de conclure à la compatibilité de tous les clients.
- Pas de validation visuelle authentifiée du dashboard pendant cette publication : Safari était occupé par une feuille d’authentification d’un autre site, laissée intacte. Les routes et assets servis sont vérifiés ; les régressions UI sont couvertes par les tests DOM.
- VoiceOver, mobile, concurrence PostgreSQL sous charge, exercice de restauration et notifications email restent des gates distincts.

Recharger complètement la page du dashboard pour utiliser le nouveau JavaScript ; le bouton Refresh d’un onglet ancien ne remplace pas le bundle déjà chargé.

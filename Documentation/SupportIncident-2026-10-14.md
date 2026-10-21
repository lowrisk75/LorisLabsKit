# Support — disponibilité rétablie, 14 octobre 2026

Mission Codex terminée. Périmètre : passerelle existante du support `feedback.lorislab.fr` (dashboard opérateur) et `help.lorislab.fr` (API), LXC 185. Aucun transcript, cookie, capacité privée ou secret conservé dans les preuves.

## Travail terminé

- Diagnostic initial en lecture seule : Help /v2/apps en 503 avec « no available server » ; Feedback redirigeait vers Authentik avant d’atteindre une passerelle indisponible. Le conteneur était running, CRM et PostgreSQL actifs.
- Cause confirmée : Nginx failed depuis le 12 octobre à 17:52:01 UTC ; bind sur `10.9.8.185:8080` refusé car l’adresse n’était pas encore disponible au démarrage. L’adresse est présente lors du diagnostic, configuration Nginx valide, backend /readyz 200.
- Démarrage contrôlé de Nginx après contrôles IP, syntaxe, readiness et empreintes. L’API publique répond de nouveau 200.
- Ajout durable de `/etc/systemd/system/nginx.service.d/50-feedback-network-retry.conf` : Wants/After network-online, Restart=on-failure, délai 5 secondes, au plus 12 démarrages dans une fenêtre de 300 secondes. Configuration validée par systemd-analyze avant chargement ; daemon-reload et propriétés effectives contrôlés.
- Aucun changement des routes Nginx, de l’environnement CRM, des secrets, des gates, de l’allowlist, d’Auth/WAF/DNS, des apps, du code CRM ou des données. Empreintes de tous les fichiers Nginx et comparaison interne de l’environnement inchangées. Aucun rapport consulté, créé, modifié ou supprimé.
- Premier contrôle local : adresse source non conforme aux ACL, donc retrait automatique du seul override ajouté. Nginx démarré a été conservé, service public revenu. Contrôle corrigé vers la source loopback prévue par le contrat existant, sans assouplir les ACL, puis ajout et validation réussis.

## Validations

- Readiness backend : HTTP 200 ; Nginx active/running.
- Passerelle interne : Help /v2/apps 200 et dashboard HTML 200 ; aucun accès aux API opérateur de données.
- Propriétés systemd : Restart=on-failure, RestartUSec=5s, StartLimitIntervalUSec=5min, StartLimitBurst=12.
- Contrôle HTTPS public final à **2026-10-14T20:56:24Z** : /v2/apps 200, /v2/capabilities 200 ; Feedback racine et API opérateur sans session renvoient 302 vers `auth.kevinn.ie`. Aucun cookie ni état OAuth enregistré.
- Les 17 identités applicatives existantes restent présentes ; `seve` n’est pas ajouté et les flags de son intégration restent false.
- Aucun redémarrage de conteneur ni test de panne volontaire : le prochain boot n’est pas revendiqué comme qualifié. Aucun parcours navigateur authentifié ni rapport privé utilisé pour la validation ; HTML interne et protection publique vérifiés.

## Travail restant / limites

Aucun travail restant pour le rétablissement demandé. Un rechargement de la page du navigateur reprend l’accès via la connexion habituelle. La reprise au prochain boot et un contrôle navigateur authentifié pourront être vérifiés séparément sans lire ou modifier de demande réelle.

L’activation/qualification Sève est une mission distincte ; la réparation d’infrastructure n’active aucun envoi d’app ni capacité avancée du SDK.

## Ressources et preuves

Preuves : [Qualification/SupportIncident-20261014](../Qualification/SupportIncident-20261014/) : diagnostic, contenu exact de l’override, script borné, contrôle de récupération et postflight public. Aucun dossier temporaire externe, simulateur, build ou processus de prévisualisation créé.

Ressource serveur durable créée et à conserver : override systemd ci-dessus et son dossier `nginx.service.d`, créé pendant cette mission. Empreinte : `7bb8dadec860801217984b428f6556f6bad855624dcd7ce7579d859f9b6f92bb`. L’exécution SSH et ses sous-processus sont terminés ; Nginx reste volontairement actif comme service du produit. Rollback de la seule politique ajoutée : vérifier cette empreinte, retirer uniquement ce fichier, daemon-reload ; ne pas arrêter la passerelle rétablie, ne restaurer aucune base ni donnée.

## Blocages

Aucun. Modification serveur autorisée via la commande de récupération bornée. Aucun commit, push, publication d’app ni extension de portée agent effectué.

## Addendum du 15 octobre — reprise prolongée

Le délai de reprise est désormais de **30 s**, après qualification isolée d’un prérequis retardé au-delà de la fenêtre de démarrage. Cela évite que les seules reprises automatiques épuisent les 12 démarrages sur 300 s. Aucun redémarrage de Nginx : PID identique et HTTPS revalidé. Lire [SupportReliability-2026-10-15](SupportReliability-2026-10-15.md) pour la politique actuelle, son empreinte, les tests et les limites ; les paramètres 5 s ci-dessus décrivent l’état historique du 14 octobre.

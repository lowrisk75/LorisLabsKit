> **Addendum du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) et sa matrice de qualification avant les consignes historiques ci-dessous. Les nouvelles fonctions sont implémentées localement, avec gates false ; aucune nouvelle activation serveur ni publication.

# Contrat commun — support LorisLabs, 5 octobre 2026

À lire avant le fichier spécifique à l’application. Ces consignes sont un handoff, pas une preuve que les changements sont déjà appliqués.

## État vérifié

Le correctif CRM/dashboard du 5 octobre est déployé. Les rapports effacés/expirés sont exclus de l’Inbox et un accès retiré renvoie 410. Le parcours HTTPS synthétique envoi → réponse opérateur → lecture → suppression a passé sous `lorislabs.staging`. Voir `Documentation/SupportDeployment-2026-10-05.md` dans LorisLabsKit.

- API et page publique : https://help.lorislab.fr/
- Dashboard opérateur : https://feedback.lorislab.fr/ (Authentik).
- `GET https://help.lorislab.fr/v2/apps` observé pendant cet inventaire : `{"apps":["eclair","lorislabs.staging","lumen","velya"]}`. Relire cette réponse avant activation.
- Réponses consultables dans la conversation privée de l’app, à l’ouverture/au rafraîchissement. Notifications email et push non implémentées. Ne pas promettre un email.
- Un test curl passé ne prouve pas URLSession : Python urllib a rencontré Cloudflare 1010. Le vrai client natif reste une qualification obligatoire.

## Travail demandé au projet

Lire ses AGENTS.md, son projet et ses tests. Préserver les changements existants. Utiliser les API réelles de `Sources/LorisReports`, avec `Documentation/FeedbackV2.md` comme contrat ; ses notes initiales de rollout sont historiques, la qualification datée du 5 octobre fait foi.

Conserver un `FeedbackClient` par processus et injecter la même instance dans `FeedbackCenter` et les hooks. Garder un moyen d’aide accessible quand le service est indisponible. Ne pas confondre import SDK, build réussi, appID autorisé et parcours support validé.

1. Vérifier le profil exact, les cibles et la révision réellement compilée. Les fichiers locaux Feedback v2 non suivis ne sont pas inclus par magie dans un ancien SHA distant. Développement local possible ; une distribution reproductible exige une révision publiée vérifiée ou un snapshot maîtrisé. Ne pas publier le SDK dans cette tâche.
2. Si l’appID manque dans `/v2/apps`, documenter la modification serveur nécessaire et laisser les envois désactivés. Aucun changement d’allowlist, d’Auth, de WAF, de portée des agents ou de service externe n’est autorisé par ce handoff.
3. Préparer des tests ciblés avec transport injecté : autorisation absente, indisponibilité réseau, 410, reprise, conservation du brouillon, sélection changée, consentement. Un simple HTTP 200 sur la page d’accueil ne valide pas l’appID. Un contrôle de disponibilité doit lire `GET /v2/apps`, décoder `apps` et exiger l’identité exacte ; appliquer le contrat HTTPS sans redirection du SDK.
4. Après autorisation séparée des envois de qualification et activation serveur, tester dans la vraie app avec URLSession, une identité synthétique et aucun contenu utilisateur : consentement → envoi → présence dans le dashboard → réponse de test à cette seule identité → lecture dans l’app → suppression → accès retiré/410. Vérifier relance, mode hors ligne et réconciliation de l’outbox sans doublon. Ne pas exposer les capacités privées dans les preuves. Tester les cibles et réseaux pertinents ; un appareil testé ne qualifie pas toutes les plateformes.
5. Activer le support uniquement après les gates propres à l’app. L’enregistrement et l’envoi de diagnostics automatiques constituent un consentement distinct, désactivé par défaut. Ne pas les activer avec le flag de disponibilité du support. Aucun réseau sur une opération métier critique.
6. Contexte technique : codes fermés et état observé, jamais logs bruts, contenu de fichiers, URL, adresse réseau, caméra, bibliothèque musicale, token, coordonnées ou autre donnée utilisateur. L’ancien export diagnostic n’est pas un payload v2 à transférer tel quel.
7. Vérifier builds des cibles, confidentialité effective/manifeste, FR/EN, grand texte et accessibilité de l’aide. Conserver achats, droits acquis, partage familial, synchro, avis manuels et parcours métier. Ne pas remplacer ces modules pour activer le support.

Livrer un diff local reviewable, les tests réellement exécutés, les gates restantes et les instructions serveur précises. Ne pas commit/push, déployer, envoyer TestFlight ou soumettre sans autorisation séparée. Le correctif serveur seul ne demande aucun nouveau build ; une migration SDK ou activation dans le code en demande un.

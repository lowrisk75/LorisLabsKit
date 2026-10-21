> **Addendum du 6 octobre 2026 :** lire [SupportEvolution-2026-10-06](../SupportEvolution-2026-10-06.md) et sa matrice de qualification avant les consignes historiques ci-dessous. Les nouvelles fonctions sont implémentées localement, avec gates false ; aucune nouvelle activation serveur ni publication.

# Instructions à transmettre — SiliconPass

Projet : `/Users/kevin/GitHub/SiliconPass`.

## État constaté

L'inventaire des sources Swift, manifests SwiftPM et XcodeGen inspectés ne trouve pas d'intégration LorisLabsKit/LorisReports. `project.yml` référence seulement le package local SiliconPass. Il ne faut donc pas présenter cette tâche comme une simple activation déjà prête. Refaire ce constat au démarrage, car une autre session peut avoir avancé.

L'allowlist observée pendant l'inventaire du 5 octobre n'inclut pas SiliconPass. L'appID proposé `siliconpass` reste à vérifier contre toute configuration existante avant adoption. Une page Help accessible ne prouve pas son autorisation.

## Travail demandé

Lire les instructions du projet et le contrat commun :
`/Users/kevin/GitHub/LorisLabsKit/Documentation/IntegrationHandoffs-2026-10-05/COMMUN.md`.

Préparer et tester localement une intégration native adaptée à un gestionnaire de secrets, en préservant les changements existants. Ne pas modifier les services externes, publier le SDK, commit/push ou distribuer l'app dans cette tâche.

1. Utiliser XcodeGen comme source du projet. Ajouter la dépendance locale `../LorisLabsKit` après vérification. Lier seulement les produits utiles aux apps principales `SiliconPass-macOS`, `SiliconPass-iOS`, `SiliconPass-visionOS`. Garder la couche UI d'intégration dans les apps si possible pour ne pas ajouter de dépendance support aux modules sensibles. Ne pas lier le SDK aux extensions AutoFill/Safari, broker, helpers, sanitizer, import readers, cœur cryptographique ou compagnon watchOS.
2. Intégrer `LorisReports` avec un propriétaire persistant par processus, un `FeedbackClient` partagé et `FeedbackCenter` accessible depuis Aide/Réglages. Conserver l'aide actuelle et afficher honnêtement l'indisponibilité tant que l'appID et le parcours natif ne sont pas qualifiés. Utiliser un profil custom, appID stable vérifié, endpoint `https://help.lorislab.fr/`. Commencer sans diagnostic (`contextProvider: nil`), sans record/flush et sans collecte automatique.
3. Séparer complètement les capacités de conversation du coffre et de ses groupes Keychain partagés : suivre le stockage device-only du SDK sans réutiliser les clés, secrets, App Groups ou droits des extensions. Vérifier les entitlements réellement compilés avant d'affirmer cette isolation. Aucun assouplissement de sandbox ou d'autorisations pour contourner un échec réseau.
4. Ne jamais lire/exporter le coffre pour remplir un rapport : aucun mot de passe, login, domaine/site enregistré, clé SSH, passkey, seed, TOTP, récupération, document, chemin, presse-papiers, dump mémoire ou log brut. Le texte libre volontaire reste une donnée support : rappeler de ne pas y coller de secrets. Toute future collecte technique doit passer par un contrat séparé de codes fermés, validé et opt-in.
5. Garder la saisie/envoi et les avis hors des chemins unlock, AutoFill, authentification, crypto, import/export, synchronisation et accès broker. Préparer les avis avec `LorisLabsKit` uniquement si la politique du produit le justifie : actions réelles, premier plan calme, aucun filtrage satisfaction/achat et aucun compteur déduit d'une lecture du coffre. Conserver l'avis manuel. Ne pas remplacer achats, synchro, design ou mécanismes de sécurité par d'autres modules SDK.
6. Tester avec données et transports synthétiques : client unique, construction sans réseau, indisponibilité, appID absent, redirection rejetée, 410, brouillon, consentement, relance et isolation du stockage. Vérifier que les extensions et chemins sensibles restent sans dépendance/envoi support. Compiler les trois apps principales et les compagnons/extensions pertinents ; adapter les schémas existants sans casser les gates de qualification.
7. Vérifier les manifestes et déclarations de confidentialité selon les flux réellement activés, FR/EN, grand texte et navigation accessible vers l'aide. Ne pas inventer une révision publiée contenant les fichiers locaux du SDK.

## Activation restante

Remettre à l'opérateur une demande précise d'autorisation de l'appID vérifié (proposition `siliconpass`), sans extension de la portée des agents distants. Garder le support désactivé avant cette étape.

Après autorisation séparée des envois de qualification, tester URLSession/CFNetwork dans les apps natives avec une identité synthétique : envoi consenti → réception dans `https://feedback.lorislab.fr/` → réponse de test à cette seule identité → lecture dans l'app → suppression → accès retiré/410. Le test curl staging déjà passé ne qualifie pas SiliconPass et son sandbox. Les réponses sont dans la conversation privée ; aucun email/push automatique n'est implémenté.

Livrer diff local, preuves de tests réellement exécutés et blocages exacts. Un nouveau build sera nécessaire après intégration/activation ; aucune distribution n'est incluse ici.

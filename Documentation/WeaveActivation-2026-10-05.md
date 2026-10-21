# Weave — activation LorisReports du 5 octobre 2026

## État serveur et client

Les trois appIDs Weave sont autorisés sur le service public. Le projet source conserve `WeaveFeedbackBackendVerified=false` pour Host ; Viewer et Mobile sont passés à `true` après qualification native. Aucun commit, push, signature de distribution ni publication d'application.

| Cible | appID exact | Qualification | Flag source |
| --- | --- | --- | --- |
| Host macOS | `com.lorislab.weave.host` | API SDK native macOS passée ; interface Host non qualifiée, timeout Computer Use | `false` |
| Viewer macOS | `com.lorislab.weave.viewer` | Interface native, consentement, envoi, réponse lue, relance, file hors ligne, reprise avec identité inchangée, absence de doublon, suppression/410 et effacement confirmés | `true` |
| Mobile iOS | `com.lorislab.weave.ios` | Interface native sur simulateur iPhone iOS 27, consentement, file hors ligne, relance, reprise, réponse lue dans l'app, relance de conversation, suppression confirmée et contrôle opérateur 410 | `true` |

La qualification iOS ne vaut pas qualification d'un appareil physique, de tous les réseaux ou du parcours complet sur iPad. Le blocage Host concerne son interface : le processus QA démarre et compile, mais deux tentatives de lecture native de sa fenêtre expirent. Ne pas déduire sa readiness produit du test SDK seul. Ouvrir ses vrais réglages depuis le menu Host permettra de reprendre cette gate sans toucher aux deux cibles déjà activées.

## Administration autorisée

L'utilisateur a explicitement autorisé l'ajout des trois valeurs dans `/etc/feedback-crm/env` du LXC 185, le redémarrage CRM, les seuls envois/réponses synthétiques et l'activation des cibles qualifiées. Cette autorisation spécifique remplace les interdictions génériques des handoffs pour cette intervention seulement.

Le script exécuté via SSH administrateur et `pct exec 185` :

- vérifie une unique ligne `FEEDBACK_ALLOWED_APP_IDS`, conserve les appIDs existants et ajoute uniquement les trois identités exactes ;
- sauvegarde l'env dans un répertoire root privé (0700), fichier 0600 : `/root/feedback-weave-backups/20261005T130726690871Z/env` ;
- remplace atomiquement l'env en préservant mode/propriétaire, redémarre le CRM avec timeout et attend `ready` dans une fenêtre bornée de 45 secondes ;
- restaure l'env original et redémarre automatiquement si la readiness ou l'allowlist effective échoue, sans écraser une modification concurrente ;
- ne modifie ni Auth, ni WAF, ni DNS, ni la portée des agents.

Activation passée sans rollback. Contrôle final : readiness `ready`, toutes les autres lignes env **identiques octet pour octet** à la sauvegarde privée, aucun marqueur de qualification serveur restant. Aucune valeur de secret n'a été affichée.

`GET https://help.lorislab.fr/v2/apps` relu après activation :

```json
{"apps":["com.lorislab.weave.host","com.lorislab.weave.ios","com.lorislab.weave.viewer","eclair","lorislabs.staging","lumen","velya"]}
```

Dashboard opérateur : https://feedback.lorislab.fr/ ; endpoint public : https://help.lorislab.fr/. Les réponses sont consultables dans l'app ; aucune notification email/push n'a été activée.

## Qualification réellement exécutée

Le vrai `FeedbackClient`/`DirectReportTransport` a été compilé dans une sonde macOS isolée. Pour les trois identités : consentement synthétique, première tentative vers un endpoint injoignable, persistance d'une seule enveloppe, nouveau processus, reprise HTTPS publique URLSession, ticket en Keychain, réponse opérateur limitée à cette identité, lecture native, suppression publique, accès conversation 410, effacement confirmé et suppression du ticket privé. Pour l'identité iOS, cette première sonde reste une exécution **macOS** ; la preuve du runtime iOS vient des tests UI suivants.

Les interfaces Viewer et iOS ont ensuite utilisé des copies QA du projet et le même SDK réel. Les flags de production sont restés false pendant cette qualification. La copie QA contourne seulement le flag statique avant le contrôle HTTPS de l'appID exact ; le gate serveur et le refus des redirections restent actifs. Le scénario hors ligne rend seulement le transport support injoignable via un argument QA. Il ne change aucun réglage réseau système. Ces adaptations restent sous `/private/tmp`, pas dans le produit source.

- **Viewer** : revue du texte synthétique et des informations de consentement, confirmation d'envoi, réponse LorisLabs visible, ticket et réponse retrouvés après relance. Une seconde demande consentie hors ligne reste en file, conserve son UUID original après relance et est reprise par l'action native. L'opérateur vérifie cet UUID et un seul rapport correspondant. Suppression depuis l'interface, accès privé URLSession 410, effacement et nettoyage des capacités privés passés.
- **iOS** : le test de reprise UI complet passe sur le simulateur dédié. Il vérifie erreur hors ligne, file conservée, relance sans argument QA, action Retry, disparition de la file, ticket reçu, réponse lue, nouvelle relance et demande de suppression. Le test attend l'accusé « Deletion is pending » avant de quitter. L'opérateur vérifie le payload `platform=ios`, son unicité, répond au seul rapport de test et confirme son effacement avec 410.
- Contexte vide, aucune pièce jointe, aucun reporter/email, aucun consentement IA distant ; `contextProvider:nil` conservé. Les diagnostics automatiques ne sont pas activés. Aucun rapport réel n'a été modifié.

Les premiers essais iOS restent conservés : un sélecteur de texte trop strict n'a pas trouvé la réponse, puis le test quittait trop tôt après la demande de suppression. Une assertion de libellé utilisait aussi un mauvais texte. La qualification finale corrige ces erreurs et attend l'accusé réseau ; ne pas remplacer les preuves échouées par une prétention de succès initial.

## Modifications locales du projet source

Diff borné ajouté à l'état préexistant : flags Viewer/Mobile dans `project.yml`, régénération XcodeGen/Info.plist, adaptation des tests Aide FR/EN pour vérifier la surface disponible ou le repli réseau et, en cas de disponibilité, le toggle diagnostic désactivé. Aucune modification de la logique métier ou du SDK pendant cette activation.

Baseline privée des fichiers remplacés : `/private/tmp/weave-feedback-activation-20261005/source-backup`. Le script vérifie les SHA-256 avant écriture pour ne pas écraser un travail concurrent. `git diff --check` et la vérification des trois valeurs dans les Info.plist générés passent.

## Références de preuve

- Scripts d'activation, qualification native/opérateur et comparaison finale : `/private/tmp/weave-feedback-activation-20261005/`.
- Test iOS de reprise complet : `ios-offline.xcresult`, résultat `TEST SUCCEEDED` ; log `ios-offline.log`.
- Réconciliation du reçu synthétique iOS déjà effacé : `ios-cleanup.xcresult`, **TEST SUCCEEDED** ; après relance, aucun ticket synthétique ni envoi en attente ne reste sur le simulateur dédié.
- Copies QA : `qa/`, variantes exclues du projet source.
- Vérifications finales du projet source : build Release Viewer `viewer-final.log` **BUILD SUCCEEDED**, flag du binaire vérifié `true` ; deux tests Aide FR/EN iOS `ios-final-smoke.xcresult` / `ios-final-smoke.log` **TEST SUCCEEDED**. Les deux vérifient l'interface disponible et le toggle diagnostic à 0. Aucun envoi n'est effectué par ces tests finaux.
- Le binaire Release final Viewer a aussi été ouvert : Réglages → Aide → centre support disponible, « Nouvelle demande » visible, conversations synthétiques absentes, diagnostics à 0. L'export historique reste accessible dans Aide. Aucun nouvel envoi pendant ce contrôle.

Ces logs et preuves ne contiennent aucune capacité de conversation ni clé opérateur affichée. Les états privés synthétiques et marqueurs serveur ont été nettoyés après effacement ; l'état serveur minimal d'effacement/audit peut rester selon le contrat du service.

# Adoption SDK support — 7 octobre 2026

Révision corrigée : `7289fba3e439eccd398084dadb5a05c512bdac9bb9c0583a67295d09aed36671`. Parent LorisLabsKit immuable : `8fabdca451caf1088e40bda25fd73012eef74dc5e734f39174ca2296b9638064`. Candidat revu : `/private/tmp/SiliconPassSupport-reviewed-20261007`, 38 fichiers contrôlés, vérificateur read-only. Le candidat original LorisLabsKit est inchangé. Une copie vérifiée du candidat corrigé est remise dans `/Users/kevin/GitHub/LorisLabsKit/Qualification/SiliconPassSupport-reviewed-20261007`, avec ce handoff dans Documentation/SiliconPassSDK-Adoption-2026-10-07.md. Aucun message ni accord d’une autre session n’est revendiqué.

## Révision avant adoption

Transport SDK reçu borné pendant les callbacks URLSession, buffer annulé au dépassement annoncé/constaté, HTTPS/URL exacte, refus redirections, configuration sans cookies/cache/credentials, timeouts et annulation. Reprise des réponses/actions confirmées avec UUID, charge filtrée, kind et version conservés ; lecture/réconciliation avant réessai incertain et aucun nouveau UUID pour contourner 409. Queue privée support : 20 opérations/256 KiB, texte effacé à l’accès après 7 jours et marqueur conservé jusqu’à suppression ; pas d’envoi automatique au lancement. Brouillons non confirmés en mémoire. Suppression/pending/completed/410 retire les opérations ; completed/410 retire le reçu.

Le correctif ajouté avant adoption est `.sortedKeys` dans DirectReportTransport. Deux tests de relance vérifient les octets transmis contre un encodage canonique trié, puis égalité exacte au retry. Réponses déjà triées. 27 tests candidat PASS avant adoption. Trois processus distincts de tests, chacun 2 assertions/scénarios de rapport, PASS après adoption.

## Intégration et préservation

Adoption par staging vérifié puis renommage, après comparaison de toutes les empreintes de l’ancien SDK pour refuser une dérive concurrente. Ancien dossier complet conservé dans `Qualification/PreservedSupport-20261007`, sources/resources/tests optionnels et métadonnées intacts, non compilé. Parents des deux fichiers de fixture sont dans `Qualification/PreservedSupportAppFixtures-20261007`. Aucun reset/stash ni écrasement du travail hors lot.

SPAppSupport garde son client partagé et les deux gates false. Son argument features est retiré car les fonctions annexes sont absentes du candidat minimal. Le wrapper app-only existant est conservé : origine épinglée `https://help.lorislab.fr/v2/`, puis délégation au transport borné SDK (16 KiB disponibilité, 128 KiB rapport, 512 KiB conversation). Pas de limite accidentelle à 128 KiB pour les conversations. Groupe Keychain support explicite device-only/non synchronisé inchangé ; pas d’accès au coffre, App Group, extensions, crypto, broker ou Watch. Diagnostics, assistant et push absents du SDK compilé ; gates Info.plist false.

Fixture native mise à jour avec réponses/accusé perdu et namespace `SiliconPassSDKAdoptionSynthetic20261007`. Elle injecte seulement un acteur local et un stockage de tickets synthétiques. Captures macOS limitées à la fenêtre du banc ; pas de bureau/vault exporté. L’épreuve macOS de réponse n’a pas démarré : runner arrêté avant connexion XCTest (signal kill). Signature ad hoc/droits contrôlés, sans nouvelle identité Apple, exception réseau/root, modification Gatekeeper/TCC/provisioning ou contournement du blocage. Gate macOS reste ouverte.

## HTTPS 503 — blocage live

GET public `/v2/apps` en HTTPS, validation TLS normale, sans redirection, corps envoyé ou capacité : HTTP **503** constaté le 7 octobre. Aucun POST, ticket utilisateur, réponse opérateur ou suppression distante exécuté. Le statut 503 ne prouve ni présence ni absence actuelle de l’appID. Le quota autorisé reste 0/6 consommé. Toutes les gates restent false ; la qualification native réseau complète attend le rétablissement du service.

## Preuves et limites

- SDK intégré : 27 tests PASS, log `/private/tmp/siliconpass-adopted-sdk-tests-20261007.log`.
- Wrapper app-only : 6 tests PASS, log `/private/tmp/siliconpass-adopted-support-safety-tests-20261007.log`.
- Contrat CRM local : 16 tests PASS ; cinq sources CRM correspondent aux empreintes du checkpoint ; SQLite privée, aucun service de production. Log `/private/tmp/siliconpass-adopted-sdk-crm-contract-20261007.log`. Avertissement de dépréciation httpx du framework, pas d’échec.
- JSON : trois processus PASS, logs `siliconpass-sdk-json-process-1/2/3-20261007.log`. Ces 6 exécutions répètent 2 tests, pas 6 tests distincts.
- Apps Release macOS, iOS Simulator et visionOS Simulator PASS ; logs `siliconpass-sdk-adoption-release-<plateforme>-20261007.log`.
- Hôtes natifs des trois plateformes compilent ; 5 tests UI iOS simulateur PASS, `/private/tmp/siliconpass-sdk-adoption-iOS-native-20261007.log` et `.xcresult`. 4 tests UI Vision Pro simulateur PASS, `/private/tmp/siliconpass-sdk-adoption-visionOS-native-20261007.log` et `.xcresult`. macOS natif BLOCKED, `/private/tmp/siliconpass-sdk-adoption-macOS-reply-20261007.log`.
- Static CI, isolation SDK/provenance et inspection de 10 bundles PASS ; `/private/tmp/siliconpass-sdk-adoption-static-ci-r2-20261007.log`, `siliconpass-sdk-adoption-support-artifacts-20261007.json`. Premier static CI échoue sur lignes de contexte des patches historiques ; artefacts de revue déplacés hors snapshot produit, aucune règle de contrôle affaiblie.

Simulateurs : UI, cycle de processus et acteur local ; droits générés ne prouvent pas le Keychain device-only physique, CFNetwork des soumissions/réponses ou réception opérateur. Appareils physiques : non exécutés. Restent le canal natif signé macOS, disponibilité HTTPS, réception/réponse opérateur et boucle complète réellement native, Keychain/provisioning physiques, FR/VoiceOver/accessibilité du flux confirmé et revue de rétention/privacy. Rien ne lève une gate par intégrité seule. Aucun commit, push, installation de ce lot, publication ni mutation externe.


### Lecture des artefacts de coordination

Les fichiers minimal-sdk.patch et app-adoption.patch du candidat sont des artefacts historiques hérités du 6 octobre, à ne pas appliquer pour refaire cette adoption. Les sources/tests complets et leurs hashes dans PROVENANCE font autorité pour la révision corrigée ; UPSTREAM et CANDIDATE-PROVENANCE attestent le SDK effectivement compilé. L’adoption actuelle inclut l’adapter app-only conservé et ne se résume pas à l’ancien patch du constructeur. Le statut candidate-only des métadonnées héritées concerne l’artefact de revue, pas une autorisation d’activation ; adoption locale et qualification distante sont distinctes.

Retour produit reçu ensuite : verrouillage pendant la saisie sur Mac mini et demande de reprise d’édition. Ce défaut est ouvert, aucun brouillon persistant d’item n’est encore implémenté. Il reste distinct de la queue durable de réponses du support validée ici. Ne pas confondre les deux. Aucun nouveau banc UI macOS lancé pendant la saisie utilisateur.

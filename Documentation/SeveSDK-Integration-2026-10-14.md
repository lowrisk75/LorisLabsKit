# Sève — intégration locale du SDK support, 14 octobre 2026

**Intégration locale terminée et appliquée.** Propriétaire : Codex. Périmètre : produit LorisReports dans l’app iPhone Sève, dépôt `/Users/kevin/GitHub/Foods`, cible technique PRISM / `com.lorislab.prism`. Aucun transcript privé conservé.

## Travail terminé

- Inspection initiale en lecture seule ; nom public Sève confirmé. Développement dans un candidat isolé, puis transfert d’écriture Foods confirmé avant l’application. Les changements de l’autre session (avis, achats, rappels, droits Apple, traductions et métadonnées Store) sont préservés.
- Dépendance locale relative `../LorisLabsKit`, produit LorisReports seul ; XcodeGen et projet généré cohérents. Le projet et scheme initiaux étaient identiques à la génération initiale.
- Réglages → Aide et support : interface FR/EN, conseils locaux et contact existant disponibles sans abonnement et avant activation.
- Un client paresseux conservé par processus, construit uniquement à l’ouverture d’Aide et après les deux gates backend/messagerie. Identité exacte `seve`, contrôle HTTPS /v2/apps avant livraison, texte seul et contexte automatique nil.
- Aucun raccordement aux services Santé, scanner/OCR, nutrition, achats, rappels ou historique. Aucune collecte automatique de leur contenu ; avertissement sur le texte libre. Les cinq gates restent false ; diagnostics, assistant et push sont désactivés explicitement.
- Stockage support séparé ; Keychain privé de l’app, sans synchronisation ni nouveau groupe partagé. Entitlements conservés. Manifest et documentation locale de confidentialité adaptés au support facultatif.
- Patch de **12 fichiers** appliqué après vérification des empreintes ; tous les fichiers appliqués correspondent au candidat testé. Toutes les autres sources conservent leurs hashes. Aucun commit/push/déploiement/publication effectué par cette mission.
- Un ajustement externe de FeedbackCenter a été préservé : seul le layout du bouton Nouvelle demande est modifié (retour à la ligne et icône masquée pour l’accessibilité). L’application de l’inverse de ce hunk reproduit exactement l’empreinte SDK initiale. Compilation Release reprise avec cet état ; aucun transport ou contrat métier changé.

## Validations

- **Release iPhone non signée : PASS**, y compris après la réconciliation du bouton SDK. Deux warnings SDK préexistants de disponibilité iOS ; aucun correctif SDK effectué par cette mission.
- **90 tests unitaires PASS**, zéro échec et zéro skip ; sept tests spécifiques à Sève : gates et absence d’I/O, stockage indisponible, même client, refus du contexte automatique, identité exacte, payload/recovery/idempotence inchangés après relance hors ligne, retrait du reçu après 410. La fixture initiale utilise désormais le décodage public de FeedbackTicket, sans exposer de constructeur interne.
- **Deux parcours natifs FR/EN PASS**, zéro échec et zéro skip, grand texte `.accessibility3` : ouverture/fermeture de l’aide, aucun éditeur avant activation, contact entièrement visible après défilement et fermeture toujours accessible. Contrôle de géométrie en plus de isHittable ; quatre captures finales inspectées.
- `git apply --check` avant application, garde SHA-256 et `git apply --reverse --check` après application : PASS. Contrôle whitespace, plist, flags et sources non concernées : PASS. Les sources appliquées correspondent aux octets qualifiés ; aucun build identique répété après cette vérification.
- Dernière lecture publique GET-only : **HTTP 503 à 2026-10-14T20:30:41Z**. Identité `seve` non qualifiée. Aucun rapport réel/synthétique envoyé au service public, aucune conversation réelle consultée, aucun changement serveur.

## Travail restant

Aucun travail restant pour l’ajout local du SDK demandé. Avant une activation/distribution distincte :

- Vérifier disponibilité du backend et autorisation exacte de `seve` ; aucune extension d’allowlist ou réparation serveur effectuée ici.
- Sur l’app réellement signée et après autorisation des envois synthétiques : consentement, envoi, présence opérateur, réponse, lecture, relance/hors ligne/reprise sans doublon, suppression completed et retrait 410. BackendAllowed et MessagingVerified restent false jusque-là.
- Garder diagnostics, assistant et push désactivés sans qualifications propres. Aucune qualification VoiceOver complète ou appareil physique revendiquée par les tests simulateur.
- Figer une révision publiée autorisée ou un snapshot maîtrisé avant distribution reproductible ; la dépendance actuelle compile le working tree local du SDK. Réconcilier politique publiée, déclarations App Store et manifeste SDK (qui décrit aussi des diagnostics ici désactivés).

## Ressources et preuves

Preuves durables : [Qualification/SeveSupport-20261014](../Qualification/SeveSupport-20261014/) : patch, plan/hashes, résultats synthétiques, contrôles d’application, quatre captures et registre RESOURCES.json. Journal dans Foods : `/Users/kevin/GitHub/Foods/audit-output/Seve-SDK-20261014.md`.

Ressources créées puis **supprimées après export** :

- Candidat source et sauvegarde d’application : `/private/tmp/seve-sdk-integration-20261014`.
- Unique dossier de build isolé : `/Volumes/DeveloperStorage/BuildScratch/Auto/Foods/seve-sdk-20261014` ; son horodatage de naissance est postérieur à la création du registre. Aucun autre dossier de build créé ; xcresult temporaires supprimés après export des résumés/captures.
- Unique simulateur : Seve-SDK-20261014, iPhone 17 Pro / iOS 27.0, UDID `99C0FE60-3A27-466B-B0BF-0655C37DA7FA` ; shutdown puis delete exécutés.
- Toutes les sessions xcodebuild terminées. Aucun serveur/processus de fond conservé. Aucune ressource appartenant à une autre session touchée.

## Blocages et état de reprise

Aucun blocage pour l’intégration locale terminée. La messagerie demeure désactivée et non qualifiée côté backend. L’autorisation filesystem d’appliquer le patch à Foods a été obtenue ; aucun transfert d’écriture ultérieur effectué. Pour reprendre : lire les fichiers courants, ce journal et FINAL-CHECKS.json ; ne pas réappliquer le script d’intégration sur un arbre déjà intégré.

## Addendum — infrastructure support rétablie

Le 14 octobre à 20:56:24 UTC, Help /v2/apps et /v2/capabilities répondent 200 après récupération de Nginx ; dashboard interne HTML 200, protection Authentik publique conservée. Voir [SupportIncident-2026-10-14](SupportIncident-2026-10-14.md). `seve` reste absent de l’allowlist ; aucune gate de Sève ni source app modifiée par cette réparation. L’observation 503 précédente reste historique.

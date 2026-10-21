# Kernel — journal d’intégration LorisLabs

Mission locale Throttle du 10 octobre 2026, propriétaire Codex. Périmètre confirmé : aide/conversations LorisReports, avis App Store et promotion croisée sur macOS/iOS. Paywall existant conservé. Un seul agent écrit, aucune délégation. Aucun transcript privé copié.

## Terminé

- Inspection initiale en lecture seule et inventaire des changements préexistants des deux dépôts.
- Candidat préparé depuis les working trees courants dans /private/tmp/kernel-lorisreports-20261010-gapwoziu/candidate.
- Deux snapshots locaux explicites et reproductibles : KernelSupport et KernelEngagement. Provenance/hash pour chaque source ; aucun ancien SHA distant prétendu contenir les ajouts locaux.
- Aide FR/EN dans les deux hôtes ; un client support par processus, identité kernel exacte, texte uniquement, aucun provider de diagnostics.
- Avis après réussite réelle avec politique 14 jours/5 réussites/3 jours distincts/120 jours ; paiement et satisfaction sans effet. Catalogue LorisLabs dans Aide, ouverture App Store sur action utilisateur.
- Modules exclus des extensions, XPC, KernelCore et Bench ; tests seuls les lient pour qualification. Frontière de traitement local préservée, manifestes des hôtes et inventaires adaptés.
- Projet Xcode réel et schemes comparés à la génération de la configuration initiale : égalité exacte, aucune modification manuelle à écraser identifiée.
- 62 fichiers de mission figés. Patch reviewable et git apply --check réussis sur le Kernel réel.

## Validations

- Xcode 27.1, build 27A9275.
- 28 tests Reports + 15 tests avis/catalogue + 25 tests adaptateur/régressions Kernel réussis ; les quatre tests répétés ne sont pas comptés deux fois.
- Builds Release finaux macOS et iOS device non signés réussis. Cinq gates inspectées dans les deux bundles : booléens false.
- Sécurité locale, modules liés au binaire Mac, provenance, graphe, catalogues, manifestes et tests de rejet d’injections sur les trois snapshots passent.
- Deux parcours UI iOS passent après correction de la propagation du grand texte : EN et FR/accessibility5. Revue visuelle effectuée. Le catalogue a ensuite été adapté sans icônes ni limite de lignes aux tailles d’accessibilité ; cette version compile en Release sur les deux plateformes.
- Ultime relance iOS avec assertion de hauteur du grand texte bloquée avant exécution, interrompue sur machine saturée (load average 953.33 à 22:00 CEST). La dernière adaptation du catalogue ne se prévaut pas de la passe UI précédente.
- UI Mac tentée : clic interrompu par une fenêtre Throttle superposée ; parcours non qualifié. Aucun droit système ou état d’autre app modifié pour contourner l’interruption.

## Pose et reprise

- Patch : Qualification/KernelIntegration-20261010/APP-INTEGRATION.patch.
- Plan figé et empreintes : APPLY-PLAN.json et BASELINE.json dans ce même dossier.
- Résultats et logs de compilation/tests synthétiques : RESULTS.json et fichiers .log. Aucune capture du bureau Mac copiée.
- Script de pose borné : apply-reviewed-candidate.py, exécuté depuis /private/tmp/apply_kernel_lorisreports.py. Il refuse toute dérive, sauvegarde les fichiers remplacés et le projet généré, puis vérifie tous les inputs non touchés.
- Pose effectuée après autorisation d’écriture de l’environnement. Les 62 fichiers ont été vérifiés dans le Kernel réel ; le projet Xcode a été régénéré avec sauvegarde. Tous les inputs non touchés sont identiques aux empreintes initiales. APPLICATION.json atteste ce contrôle.
- Simulateur créé uniquement pour cette mission : 6C81772A-658E-45DA-A388-CEA2EE690EA4, iPhone 17 Pro/iOS 26.4. Il a été arrêté après les essais ; les simulateurs existants sont préservés.

## Reste et blocages

- Relancer UI Mac sur un bureau sans interruption et l’ultime passe iOS sur une machine non saturée.
- GET public /v2/apps : HTTP 503. Autorisation exacte de kernel non attestée ; messagerie désactivée.
- Les cinq gates restent false. L’activation serveur et les envois de qualification exigent une autorisation distincte ; qualifier consentement, URLSession, réponse opérateur, lecture, relance, hors ligne/reprise sans doublon et suppression/410 sur chaque plateforme.
- Diagnostics, assistant et push restent hard-disabled dans l’adaptateur ; adoption distincte.
- Aucun affichage réel d’avis StoreKit, signature de distribution, appareil physique ou publication qualifié.

Aucun commit, push, déploiement, mutation serveur, profil/certificat ou envoi de rapport.

## Résultat final de pose

APPLICATION.json : applied-and-verified, preservedAllUntouchedInputs=true, generatedProjectRegeneratedWithBackup=true. Sauvegarde privée : /private/tmp/kernel-lorisreports-20261010-gapwoziu/private-before-apply. Aucun commit ni publication. Les limites UI et d’activation ci-dessus restent ouvertes.

## Observation après pose

Le contrôle read-only dans Kernel passe et git diff --check passe. Les 62 fichiers de mission restent identiques au candidat figé. Après la pose, une autre activité a ajouté des sources de conversions/documents et modifié des inputs hors mission : Shared/XPCProtocols.swift. Ces changements sont préservés, sans investigation ni écriture supplémentaire dans Kernel. Les builds/tests concernent le candidat validé avant ces nouvelles modifications ; ils ne qualifient pas ces travaux externes. Voir FINAL-POSTFLIGHT.json.

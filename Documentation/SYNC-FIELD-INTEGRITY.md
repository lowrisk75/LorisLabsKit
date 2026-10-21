# LorisSync — intégrité des champs / field integrity

## Français

Le mapping interne CKRecord → SyncRecord est tout-ou-erreur : il refuse un record si son type ne correspond pas au type demandé, si modifiedAt manque, ou si un champ ne peut pas être représenté par SyncValue. Références, assets, locations et autres formes non prises en charge ne sont plus ignorés silencieusement. L'adaptateur remonte invalidRecord ; les collecteurs existants ne renvoient pas de préfixe ou checkpoint après cette erreur. Le CKRecord d'origine n'est pas modifié par la lecture.

Les NSNumber sont décodés selon leur représentation native observable : encodages entiers signés/non signés → Int exact avec contrôle de plage ; flottants → Double fini, même si la valeur est mathématiquement entière. Pas de détour par Double pour mesurer un entier. NSDecimalNumber, entier hors plage, NaN/infini et listes numériques non intégrales sont refusés plutôt que convertis avec perte. SyncValue ne représente pas tous les types CloudKit : ce sont des limites du SDK, pas une affirmation de rejet serveur.

Compatibilité : les cas/API publics, archive du journal et minimums OS ne changent pas. Les cas numériques inférés peuvent changer (ancien Double arrondi devenu Int exact ; ancien Int issu de flottant devenu Double). Les records auparavant partiellement acceptés sont désormais refusés. Conserver les données, rendre l'erreur visible et vérifier le schéma ; aucun reset/migration automatique. Les tableaux vides conservent l'interprétation historique stringList ; leur type source est ambigu. `.bool` s'écrit comme0/1 et n'est pas reconstruit automatiquement : bool(_:) ne devient pas un convertisseur d'entiers. Un adaptateur de schéma explicite reste requis.

Ce correctif n'autorise pas une sauvegarde allKeys d'un modèle arbitrairement incomplet, ne conserve pas les system fields/change tags et n'ajoute ni CAS ni politique de conflit. Les suppressions typées/concurrentes restent séparées. Huit méthodes Swift Testing utilisent des CKRecord/NSNumber synthétiques sans CKContainer, compte, réseau ni fichiers. Le comportement du serveur et les vrais schémas restent à qualifier. Aucun gain de performance ou certificat global de sécurité/SOTA.

## English

Native record mapping is all-or-error: wrong requested record type, missing modifiedAt or any unsupported field rejects the entire SyncRecord. References/assets/locations are not silently dropped. The existing adapter raises invalidRecord and collectors withhold partial results/checkpoints on failure. Reading does not mutate the original CKRecord.

Numeric mapping follows observable NSNumber representation: signed/unsigned integer encodings become range-checked exact Int; floating encodings become finite Double even when mathematically integral. No Double intermediate for integer magnitude/type inference. Decimal, out-of-range integers, nonfinite numbers and unsupported numeric lists fail rather than lose data. These are SDK support limits, not server validation claims.

Public API/cases/minimum OS and journal format are unchanged, but inferred numeric cases deliberately tighten/change. Previously partially accepted records now fail. Preserve original data and verify the schema; no automatic reset/migration. Empty arrays retain legacy stringList interpretation; original element type is ambiguous. Boolean writes remain numeric0/1 without automatic bool reconstruction. An explicit schema adapter is still required.

This does not make arbitrary partial allKeys writes safe, preserve system fields/change tags or implement CAS/conflicts/typed-delete concurrency. Eight local native-framework methods exercise synthetic profile-blob and typed-field shapes without container/account/network/files. Actual server/schema round-trips and full independent security/adoption/release qualification remain open. No performance/SOTA certificate.

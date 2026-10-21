# SDK Security — FR / EN

## Français

Mission C0294815-9DD4-49B1-B0F6-E26A203CEE57. Adoption locale non taguée de `../LorisFoundation`, produit runtime `LorisSecurity`; `LorisSecurityTesting` uniquement dans les tests. Aucun changement d'app. Fondation demeure propriétaire des primitives ; LabsKit conserve commerce/avis/support/sync/design.

`LorisKeychain` garde son API synchrone, service bundle par défaut, groupe implicite, Trousseau par défaut et Data vide. Le nouveau pont `LegacyKeychainStore` omet le sélecteur data-protection comme l'ancien wrapper. Sur macOS, il peut donc lire le Trousseau fichier ; ses ACL/accessibilités ne valent pas les garanties de SecureStore. La rotation modifie la valeur seulement, ne supprime jamais avant d'écrire et conserve la protection existante. Le changement volontaire de protection exige une migration explicite séparée.

Erreurs natives conservées comme `unexpectedStatus`; résultat réussi sans Data devient errSecDecode plutôt qu'absence. `contains` reste Bool pour compatibilité, donc ne distingue pas absent/refus : ne pas en déduire une régénération. Chaîne non-UTF8 reste nil comme avant. Identité vide/surdimensionnée refusée avec errSecParam. Aucune synchronisation, import ou suppression automatique ajouté.

Tests LorisKeychainTests : backend mémoire, rotation refusée, valeur conservée, Data vide, suppression explicite/absent, mapping d'erreur. Ils ne prouvent pas les ACL ou le Trousseau fichier natifs. Les tests de trial préexistants utilisent le vrai Trousseau et restent séparés ; aucune validation commerce complète n'est revendiquée. Les trois checkouts SDK doivent rester adjacents tant qu'aucune révision distante n'est explicitement qualifiée/autorisée.

## English

Legacy nil-group lookups span entitled groups, unlike default-group creation. Ambiguity now fails (errSecDuplicateItem); operations pin one native persistent reference, never an unbounded wildcard. This continues one historical item and does NOT prove private ownership if a shared item was preplanted alone. Configure the actual signed group using the additive `LorisKeychain(service:accessGroup:)` initializer when group ownership matters. Native two-group/file-Keychain/reference behavior must be qualified before adoption; unsupported selectors fail without broad fallback.

Local unreleased integration of adjacent LorisFoundation/LorisSecurity. Testing product is test-only. LorisKeychain preserves synchronous APIs, service/default-group/platform-default storage and empty Data. Value-only rotation no longer deletes first or rewrites existing protection. New modern namespaces should use SecureStore directly; this legacy bridge does not migrate or provide file-Keychain ACL guarantees. Invalid identities fail, malformed successful reads map to decode error, and legacy Bool/nil convenience methods retain documented information loss. Synthetic tests are not signed-host/device/trial/release qualification. No app changes, commit, tag, push or publication.

import Foundation
import Testing
#if canImport(AppKit)
import AppKit
#endif
@testable import LorisLabsKit

@Suite struct CrossPromotionCatalogTests {
    @Test func releasedCatalogHasUniqueIdentitiesAndOfflineArtwork() throws {
        let apps = LorisLabsApp.portfolio
        #expect(apps.count == 21)
        #expect(Set(apps.map(\.ascAppId)).count == apps.count)
        #expect(Set(apps.map(\.bundleIdentifier)).count == apps.count)
        for app in apps {
            #expect(!app.name.isEmpty && !app.tagline.isEmpty)
            #expect(app.appStoreURL.host == "apps.apple.com")
            #expect(app.ascAppId.allSatisfy { $0.isNumber })
            let url = try #require(app.bundledIconURL)
            #expect(try Data(contentsOf: url).count > 1024)
            #if canImport(AppKit)
            let image = try #require(NSImage(contentsOf: url))
            #expect(image.size.width >= 256 && image.size.height >= 256)
            #endif
        }
    }

    @Test func currentAppDebugBuildAndExtensionsAreExcluded() {
        for identifier in ["com.lorislab.kernel", "com.lorislab.kernel.debug", "COM.LORISLAB.KERNEL.share"] {
            #expect(!LorisLabsApp.othersThan(identifier).contains { $0.ascAppId == "6795820987" })
        }
        #expect(LorisLabsApp.othersThan("com.lorislab.kernelish").count == 21)
    }

    @Test func frenchAndEnglishDescriptionsAndTitlesAreAvailable() {
        let french = Locale(identifier: "fr_FR")
        let english = Locale(identifier: "en_US")
        #expect(PortfolioText.title(locale: french) == "Les autres apps LorisLabs")
        #expect(PortfolioText.title(locale: english) == "More from LorisLabs")
        for app in LorisLabsApp.portfolio {
            #expect(app.localizedTagline(locale: french) != app.localizedTagline(locale: english))
        }
    }

    @Test func reconstructedHostEntriesKeepIconsAndLocalizedCopy() throws {
        let original = try #require(LorisLabsApp.portfolio.first)
        let copy = LorisLabsApp(name: original.name, bundleIdentifier: original.bundleIdentifier,
            ascAppId: original.ascAppId, tagline: original.tagline, category: original.category)
        #expect(copy.bundledIconURL == original.bundledIconURL)
        #expect(copy.localizedTagline(locale: Locale(identifier: "fr")) == original.taglineFrench)
        #expect(copy.appStoreURL.path == "/app/id\(copy.ascAppId)")
    }
}

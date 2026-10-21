import Foundation
import Testing
@testable import LorisLabsKit
#if canImport(AppKit)
import AppKit
#endif

@Suite struct PortfolioCatalogueTests {
    @Test func publishedCatalogueHasUniqueIdentitiesAndOfflineIcons() throws {
        let apps = LorisLabsApp.portfolio
        #expect(apps.count == 21)
        #expect(Set(apps.map(\.bundleIdentifier)).count == apps.count)
        #expect(Set(apps.map(\.ascAppId)).count == apps.count)
        for app in apps {
            let icon = try #require(app.iconURL)
            let bytes = try Data(contentsOf: icon)
            #expect(bytes.starts(with: [0xff, 0xd8, 0xff]) || bytes.starts(with: [0x89, 0x50, 0x4e, 0x47]))
            #expect(bytes.count > 1_024)
            #if canImport(AppKit)
            #expect((NSImage(contentsOf: icon)?.size.width ?? 0) >= 256)
            #endif
            #expect(app.appStoreURL.host == "apps.apple.com")
            #expect(app.appStoreURL.path == "/app/id\(app.ascAppId)")
            #expect(!app.localizedTagline(locale: Locale(identifier: "fr")).isEmpty)
            #expect(app.taglineFrench != nil)
        }
    }
    @Test func currentAppExcludedInBothLanguagesAndWithCaseVariants() {
        for app in LorisLabsApp.portfolio {
            #expect(!LorisLabsApp.othersThan(app.bundleIdentifier.uppercased()).contains { $0.ascAppId == app.ascAppId })
        }
        #expect(LorisLabsApp.othersThan("com.lorislab.prism").count == 20)
        #expect(LorisLabsApp.portfolio.first { $0.ascAppId == "6793450821" }?.localizedName(locale: Locale(identifier: "fr")).contains("Sève") == true)
    }
}

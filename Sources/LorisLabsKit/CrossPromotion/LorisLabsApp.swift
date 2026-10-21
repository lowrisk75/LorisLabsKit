import Foundation

/// A published app. The built-in catalogue and official icons are bundled for offline use.
public struct LorisLabsApp: Identifiable, Hashable, Sendable, Codable {
    public var id: String { bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String
    public let ascAppId: String
    public let tagline: String
    public let category: String
    public let appStoreCountry: String
    public let nameFrench: String?
    public let taglineFrench: String?

    public init(name: String, bundleIdentifier: String, ascAppId: String, tagline: String,
                category: String, appStoreCountry: String = "", nameFrench: String? = nil,
                taglineFrench: String? = nil) {
        precondition(!ascAppId.isEmpty && ascAppId.allSatisfy(\.isNumber), "App Store ID must be numeric")
        precondition(appStoreCountry.isEmpty || (appStoreCountry.count == 2 && appStoreCountry.allSatisfy(\.isLetter)))
        self.name = name; self.bundleIdentifier = bundleIdentifier; self.ascAppId = ascAppId
        self.tagline = tagline; self.category = category; self.appStoreCountry = appStoreCountry
        self.nameFrench = nameFrench; self.taglineFrench = taglineFrench
    }

    /// A country-neutral link lets the App Store resolve the person's storefront.
    public var appStoreURL: URL {
        let country = appStoreCountry.isEmpty ? "" : "/\(appStoreCountry)"
        return URL(string: "https://apps.apple.com\(country)/app/id\(ascAppId)")!
    }
    public var itmsURL: URL { URL(string: "itms-apps://apps.apple.com/app/id\(ascAppId)")! }
    public var iconURL: URL? { Bundle.module.url(forResource: "app-\(ascAppId)", withExtension: "jpg") ?? Bundle.module.url(forResource: "app-\(ascAppId)", withExtension: "png") }
    public var bundledIconURL: URL? { iconURL }
    public func localizedName(locale: Locale = .current) -> String {
        locale.language.languageCode?.identifier == "fr" ? (nameFrench ?? Self.portfolio.first { $0.ascAppId == ascAppId }?.nameFrench ?? name) : name
    }
    public func localizedTagline(locale: Locale = .current) -> String {
        locale.language.languageCode?.identifier == "fr" ? (taglineFrench ?? Self.portfolio.first { $0.ascAppId == ascAppId }?.taglineFrench ?? tagline) : tagline
    }
}

public extension LorisLabsApp {
    /// Public Apple release snapshot. Refresh with Scripts/update-portfolio-catalog.py.
    static let portfolio: [LorisLabsApp] = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let apps = try? JSONDecoder().decode([LorisLabsApp].self, from: data) else {
            assertionFailure("Missing or invalid bundled LorisLabs catalogue")
            return []
        }
        return apps
    }()

    static func othersThan(_ currentBundleIdentifier: String) -> [LorisLabsApp] {
        let current = currentBundleIdentifier.lowercased()
        return portfolio.filter {
            let own = $0.bundleIdentifier.lowercased()
            return current != own && !current.hasPrefix(own + ".")
        }
    }
}

/// Shared labels for hosts that provide their own Settings styling.
public enum PortfolioText {
    public static func title(locale: Locale = .current) -> String {
        let language = locale.language.languageCode?.identifier == "fr" ? "fr" : "en"
        let localized = Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
        return localized.localizedString(forKey: "More from LorisLabs", value: nil, table: nil)
    }
}

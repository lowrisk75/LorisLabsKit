import Foundation

/// One LorisLabs app, for the "More from LorisLabs" cross-promotion view.
public struct LorisLabsApp: Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String
    public let ascAppId: String
    public let tagline: String
    public let category: String
    public let appStoreCountry: String

    public init(
        name: String,
        bundleIdentifier: String,
        ascAppId: String,
        tagline: String,
        category: String,
        appStoreCountry: String = "us"
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.ascAppId = ascAppId
        self.tagline = tagline
        self.category = category
        self.appStoreCountry = appStoreCountry
    }

    /// Universal App Store URL.
    public var appStoreURL: URL {
        URL(string: "https://apps.apple.com/\(appStoreCountry)/app/id\(ascAppId)")!
    }

    /// In-app `itms-apps://` URL for in-app navigation (no Safari bounce).
    public var itmsURL: URL {
        URL(string: "itms-apps://apps.apple.com/app/id\(ascAppId)")!
    }
}

public extension LorisLabsApp {
    /// Full LorisLabs portfolio (live apps only). Update as the catalog grows.
    static let portfolio: [LorisLabsApp] = [
        LorisLabsApp(
            name: "Lumen for Frigate",
            bundleIdentifier: "com.lorislab.lumenforfrigate.Lumen-for-Frigate",
            ascAppId: "6760238729",
            tagline: "Native multi-platform Frigate NVR companion",
            category: "Utilities"
        ),
        LorisLabsApp(
            name: "LumenTV",
            bundleIdentifier: "com.lorislab.lumenforfrigate.tv.LumenTV",
            ascAppId: "6760317319",
            tagline: "Frigate cameras on your Apple TV",
            category: "Utilities"
        ),
        LorisLabsApp(
            name: "Clasp",
            bundleIdentifier: "com.lorislab.claspapp",
            ascAppId: "6759068382",
            tagline: "Cross-device clipboard manager",
            category: "Productivity"
        ),
        LorisLabsApp(
            name: "TypeMetrics",
            bundleIdentifier: "com.LorisLabs.typemetrics",
            ascAppId: "6758631803",
            tagline: "Understand how you type",
            category: "Productivity"
        ),
        LorisLabsApp(
            name: "404 Network",
            bundleIdentifier: "com.lorislab.app404",
            ascAppId: "6760702536",
            tagline: "Network diagnostics, simplified",
            category: "Utilities"
        ),
    ]

    /// Filter the portfolio to apps OTHER than the current one (for "More from…" lists).
    static func othersThan(_ currentBundleIdentifier: String) -> [LorisLabsApp] {
        portfolio.filter { $0.bundleIdentifier != currentBundleIdentifier }
    }
}

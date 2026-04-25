import SwiftUI

/// Visual configuration for `LorisLabsPaywallView`.
///
/// Each LorisLabs app has its own brand color (Lumen blue, Aura purple, etc.).
/// Pass a `PaywallStyle` to override the default and match the host app.
public struct PaywallStyle: Sendable {
    public let accentColor: Color
    public let backgroundColor: Color
    public let cardBackgroundColor: Color
    public let popularBadgeText: String
    public let purchaseButtonText: String
    public let restoreButtonText: String
    public let cancelButtonText: String

    public init(
        accentColor: Color = .accentColor,
        backgroundColor: Color = Color(white: 0.05),
        cardBackgroundColor: Color = Color(white: 0.10),
        popularBadgeText: String = "Most popular",
        purchaseButtonText: String = "Continue",
        restoreButtonText: String = "Restore Purchase",
        cancelButtonText: String = "Not now"
    ) {
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.cardBackgroundColor = cardBackgroundColor
        self.popularBadgeText = popularBadgeText
        self.purchaseButtonText = purchaseButtonText
        self.restoreButtonText = restoreButtonText
        self.cancelButtonText = cancelButtonText
    }

    public static let `default` = PaywallStyle()
}

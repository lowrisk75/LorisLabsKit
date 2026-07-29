import SwiftUI

/// Shared design tokens for the LorisLabs portfolio. Apps keep their own skin
/// (PulseUI, VigilUI, RampartUI…) but common primitives read these tokens so a
/// single component (GlassCard, …) renders correctly everywhere. Override per
/// app via `LorisDesignTokens.current`.
public struct LorisDesignTokens: Sendable {
    public var cardCornerRadius: CGFloat
    public var cardPadding: CGFloat
    public var cardBorder: Color
    public var cardBorderHighContrast: Color
    public var accent: Color

    public init(cardCornerRadius: CGFloat = 14,
                cardPadding: CGFloat = 14,
                // A white border at rest reads as a highlight on glass, which is the
                // intended look. The high-contrast variant is different: it exists so
                // users who ask for increased contrast can actually see the card edge.
                // `.white` there is invisible on a light background — exactly the
                // people it is meant to serve get nothing. `.primary` adapts to the
                // colour scheme, which is what PulseUI used before this was ported.
                cardBorder: Color = .white.opacity(0.14),
                cardBorderHighContrast: Color = .primary.opacity(0.4),
                accent: Color = Color(red: 0, green: 0x71 / 255.0, blue: 0xE3 / 255.0)) {
        self.cardCornerRadius = cardCornerRadius
        self.cardPadding = cardPadding
        self.cardBorder = cardBorder
        self.cardBorderHighContrast = cardBorderHighContrast
        self.accent = accent
    }

    /// Process-wide tokens; set once at app launch before any view renders.
    nonisolated(unsafe) public static var current = LorisDesignTokens()
}

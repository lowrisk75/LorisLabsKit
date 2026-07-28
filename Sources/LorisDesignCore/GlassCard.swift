import SwiftUI

/// Canonical GlassCard for the portfolio — ported from 404/PulseUI (the richest
/// of the 4 divergent copies: accessibility-aware contrast + reduce-transparency,
/// macOS adaptive variant, Liquid Glass refractive border on iOS 18+), with the
/// Pulse-specific tokens replaced by `LorisDesignTokens`.
public struct GlassCard<Content: View>: View {
    let borderColor: Color?
    @ViewBuilder let content: () -> Content
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        borderColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.borderColor = borderColor
        self.content = content
    }

    private var tokens: LorisDesignTokens { LorisDesignTokens.current }

    private var cornerRadius: CGFloat {
        #if os(macOS)
        10
        #else
        tokens.cardCornerRadius
        #endif
    }

    private var effectiveBorder: Color {
        let base = borderColor ?? tokens.cardBorder
        #if os(macOS)
        return base
        #else
        if contrast == .increased, borderColor == nil {
            // In high contrast, boost opacity for visibility
            return tokens.cardBorderHighContrast
        }
        return base
        #endif
    }

    private var effectiveLineWidth: CGFloat {
        #if os(macOS)
        0.5
        #else
        contrast == .increased ? 2 : 1
        #endif
    }

    public var body: some View {
        content()
            .padding(tokens.cardPadding)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            #if os(macOS)
            .background(.regularMaterial)
            #else
            .background(
                reduceTransparency
                    ? AnyShapeStyle(.thickMaterial)
                    : AnyShapeStyle(contrast == .increased ? Material.regularMaterial : Material.ultraThinMaterial)
            )
            #endif
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                #if os(macOS)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(effectiveBorder, lineWidth: effectiveLineWidth)
                #else
                if #available(iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *) {
                    // Refractive gradient border (Liquid Glass effect)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    effectiveBorder.opacity(0.3),
                                    effectiveBorder.opacity(0.8),
                                    effectiveBorder.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: effectiveLineWidth
                        )
                        .blur(radius: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(effectiveBorder, lineWidth: effectiveLineWidth)
                }
                #endif
            }
    }
}

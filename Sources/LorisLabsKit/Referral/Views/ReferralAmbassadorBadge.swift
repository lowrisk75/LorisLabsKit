import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct ReferralAmbassadorBadge: View {
    public init() {}

    public var body: some View {
        let e = ReferralKit.shared.entitlement
        if e.tiersUnlocked.contains("tier5") || e.tiersUnlocked.contains("tier10") {
            Label(
                e.tiersUnlocked.contains("tier10") ? "Top Ambassador" : "Ambassador",
                systemImage: "rosette"
            )
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.yellow.opacity(0.2), in: .capsule)
            .foregroundStyle(.orange)
        }
    }
}

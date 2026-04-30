import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct ReferralStatusBanner: View {
    public init() {}

    public var body: some View {
        let e = ReferralKit.shared.entitlement
        if e.pendingReferrals > 0 || e.isActive {
            HStack(spacing: 10) {
                Image(systemName: e.isActive ? "checkmark.seal.fill" : "hourglass")
                    .foregroundStyle(e.isActive ? .green : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    if e.isActive, let until = e.bonusUntil {
                        Text("Pro bonus active")
                            .font(.subheadline.weight(.semibold))
                        Text("Until \(until.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("\(e.pendingReferrals) referral(s) pending")
                            .font(.subheadline.weight(.semibold))
                        Text("Bonus unlocks once friends complete their refund window")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(.tint.opacity(0.1), in: .rect(cornerRadius: 10))
        }
    }
}

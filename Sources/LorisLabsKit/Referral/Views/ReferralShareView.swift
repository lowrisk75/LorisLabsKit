import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct ReferralShareView: View {
    @State private var referralCode: String?
    @State private var isLoading = true
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        VStack(spacing: 24) {
            header
            if let code = referralCode {
                codeCard(code: code)
                progressSection
                shareButton(code: code)
            } else if isLoading {
                ProgressView().task { await load() }
            } else if let err = errorMessage {
                Text(err).foregroundStyle(.red)
            }
        }
        .padding(20)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "gift.fill")
                .font(.system(size: 44))
                .foregroundStyle(.blue)
            Text("Invite friends")
                .font(.title2.weight(.semibold))
            Text("Get +1 month Pro for each friend who subscribes")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func codeCard(code: String) -> some View {
        VStack(spacing: 8) {
            Text("Your referral link")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: linkURL(code: code).absoluteString)
                .font(.system(.callout, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.tint.opacity(0.15), in: .rect(cornerRadius: 8))
        }
    }

    private var progressSection: some View {
        let e = ReferralKit.shared.entitlement
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Progress")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(e.confirmedReferrals) confirmed · \(e.pendingReferrals) in flight")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: e.progressTowardsTier5)
                .tint(e.progressTowardsTier5 >= 1 ? .green : .blue)
            Text("Tier 5: 50% off Lifetime")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ProgressView(value: e.progressTowardsTier10)
                .tint(e.progressTowardsTier10 >= 1 ? .green : .blue)
            Text("Tier 10: Free Lifetime")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func shareButton(code: String) -> some View {
        ShareLink(item: linkURL(code: code)) {
            Label("Share", systemImage: "square.and.arrow.up")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.tint, in: .rect(cornerRadius: 10))
                .foregroundStyle(.white)
        }
    }

    private func linkURL(code: String) -> URL {
        URL(string: "https://r.lorislab.fr/v1/refer/\(ReferralKit.shared.bundleID)/\(code)")!
    }

    private func load() async {
        do {
            let identity = ReferralIdentity()
            let uuid = try identity.getOrCreateUUID()
            let client = ReferralClient(
                workerURL: ReferralKit.shared.workerURL,
                bundleID: ReferralKit.shared.bundleID
            )
            let resp = try await client.share(uuid: uuid)
            await MainActor.run {
                self.referralCode = resp.code
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

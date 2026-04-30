import SwiftUI

@available(iOS 17.0, macOS 14.0, *)
public struct ReferralRedeemView: View {
    public let onRedeemed: ((URL) -> Void)?

    @State private var code: String = ""
    @State private var isLoading = false
    @State private var resultMessage: String?
    @State private var redeemUrl: URL?

    public init(initialCode: String? = nil, onRedeemed: ((URL) -> Void)? = nil) {
        if let c = initialCode { _code = State(initialValue: c) }
        self.onRedeemed = onRedeemed
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Redeem a referral code")
                .font(.title3.weight(.semibold))
            TextField("ABC123", text: $code)
                #if os(iOS)
                .textInputAutocapitalization(.characters)
                #endif
                .disableAutocorrection(true)
                .font(.system(.body, design: .monospaced))
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(.tint.opacity(0.1), in: .rect(cornerRadius: 8))
            Button(action: { Task { await redeem() } }) {
                HStack {
                    if isLoading { ProgressView() }
                    Text("Redeem")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.tint, in: .rect(cornerRadius: 10))
                .foregroundStyle(.white)
            }
            .disabled(code.count != 6 || isLoading)
            if let msg = resultMessage {
                Text(msg).font(.callout).foregroundStyle(.secondary)
            }
            if let url = redeemUrl {
                Link("Open in App Store", destination: url)
            }
        }
        .padding(20)
    }

    private func redeem() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let client = ReferralClient(
                workerURL: ReferralKit.shared.workerURL,
                bundleID: ReferralKit.shared.bundleID
            )
            let lookup = try await client.lookup(code: code.uppercased())
            await MainActor.run {
                self.resultMessage = "Code valid: \(lookup.appName) — \(lookup.refereeReward). Tap Subscribe in the app to apply."
                NotificationCenter.default.post(
                    name: .referralCodeAccepted,
                    object: nil,
                    userInfo: ["claimNonce": lookup.claimNonce, "code": code]
                )
            }
        } catch {
            await MainActor.run { self.resultMessage = "\(error)" }
        }
    }
}

public extension Notification.Name {
    static let referralCodeAccepted = Notification.Name("ReferralKit.codeAccepted")
}

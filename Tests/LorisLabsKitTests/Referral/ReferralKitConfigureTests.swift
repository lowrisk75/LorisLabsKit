import Testing
import Foundation
@testable import LorisLabsKit

@MainActor
struct ReferralKitConfigureTests {
    @Test func configure_storesBundleAndURL() {
        ReferralKit.configure(
            bundleID: "com.test.app",
            workerURL: URL(string: "https://referrals.lorislab.fr")!
        )
        #expect(ReferralKit.shared.bundleID == "com.test.app")
        #expect(ReferralKit.shared.workerURL.host == "referrals.lorislab.fr")
    }

    @Test func configure_isIdempotent() {
        ReferralKit.configure(
            bundleID: "com.test.app",
            workerURL: URL(string: "https://example.com")!
        )
        ReferralKit.configure(
            bundleID: "com.test.app",
            workerURL: URL(string: "https://other.com")!
        )
        // Second call should win (re-configure allowed for staging swap)
        #expect(ReferralKit.shared.workerURL.host == "other.com")
    }
}

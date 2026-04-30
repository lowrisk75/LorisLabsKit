import Testing
import Foundation
@testable import LorisLabsKit

struct ReferralDeepLinkTests {
    @Test func parse_validLink() {
        let url = URL(string: "https://r.lorislab.fr/v1/refer/com.lorislab.lumenforfrigate.Lumen-for-Frigate/K3F7AB")!
        let result = ReferralDeepLink.parse(url)
        #expect(result?.bundleID == "com.lorislab.lumenforfrigate.Lumen-for-Frigate")
        #expect(result?.code == "K3F7AB")
    }

    @Test func parse_validShortLink() {
        let url = URL(string: "https://r.lorislab.fr/refer/com.test.app/ABCDEF")!
        let result = ReferralDeepLink.parse(url)
        #expect(result?.bundleID == "com.test.app")
        #expect(result?.code == "ABCDEF")
    }

    @Test func parse_invalidHost() {
        let url = URL(string: "https://evil.example/refer/com.test/ABCDEF")!
        #expect(ReferralDeepLink.parse(url) == nil)
    }

    @Test func parse_invalidCode() {
        let url = URL(string: "https://r.lorislab.fr/refer/com.test/lower6")!
        #expect(ReferralDeepLink.parse(url) == nil)
    }

    @Test func parse_missingPath() {
        let url = URL(string: "https://r.lorislab.fr/")!
        #expect(ReferralDeepLink.parse(url) == nil)
    }
}

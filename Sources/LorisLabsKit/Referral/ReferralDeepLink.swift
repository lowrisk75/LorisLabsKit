import Foundation

public struct ReferralDeepLink: Sendable, Equatable {
    public let bundleID: String
    public let code: String

    public init(bundleID: String, code: String) {
        self.bundleID = bundleID
        self.code = code
    }

    /// Acceptable hostnames for referral universal links.
    public static let allowedHosts: Set<String> = [
        "r.lorislab.fr",
        "referrals.lorislab.fr",
    ]

    /// Match a 6-char code from our base32 alphabet (no I O 0 1).
    private static let codePattern = "[A-HJ-NP-Z2-9]{6}"

    public static func parse(_ url: URL) -> ReferralDeepLink? {
        guard let host = url.host, allowedHosts.contains(host) else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }
        // Patterns: ["v1", "refer", bundle, code]  OR  ["refer", bundle, code]
        let stripped: [String]
        if segments.first == "v1" {
            guard segments.count >= 4, segments[1] == "refer" else { return nil }
            stripped = Array(segments[2...])
        } else if segments.first == "refer" {
            guard segments.count >= 3 else { return nil }
            stripped = Array(segments[1...])
        } else {
            return nil
        }
        guard stripped.count >= 2 else { return nil }
        let bundleID = stripped[0]
        let code = stripped[1]
        guard !bundleID.isEmpty,
              code.range(of: "^\(codePattern)$", options: .regularExpression) != nil else {
            return nil
        }
        return ReferralDeepLink(bundleID: bundleID, code: code)
    }
}

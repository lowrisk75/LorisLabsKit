import Foundation

/// Networking client for the referrals worker. All endpoints validated
/// against the worker's API contract (see spec §7).
public actor ReferralClient {
    public enum ClientError: Error, Sendable {
        case http(status: Int, error: String?)
        case decoding(String)
        case hmacMismatch
        case missingHmacSecret
    }

    public struct LookupResponse: Sendable, Decodable {
        public let claimNonce: String
        public let appName: String
        public let refereeReward: String
        public let expiresAt: String
    }

    public struct ShareResponse: Sendable, Decodable {
        public let code: String
        public let confirmedReferrals: Int
        public let pendingReferrals: Int
    }

    public struct ClaimResponse: Sendable, Decodable {
        public let status: String
        public let scheduledConfirmAt: String?
        public let refereeOfferCode: String?
        public let refereeRedeemUrl: String?
    }

    public struct MeResponse: Sendable, Decodable {
        public let uuid: String
        public let code: String
        public let confirmedReferrals: Int
        public let pendingReferrals: Int
        public let bonusUntil: String?
        public let tiersUnlocked: [String]
        public let rewardsAvailable: [Reward]
        public let _signedAt: String

        public struct Reward: Sendable, Decodable {
            public let tier: String
            public let promoCode: String
            public let redeemUrl: String
        }
    }

    private let workerURL: URL
    private let bundleID: String
    private let session: URLSession
    private let hmacSecret: String?

    public init(
        workerURL: URL,
        bundleID: String,
        session: URLSession = .shared,
        hmacSecret: String? = nil
    ) {
        self.workerURL = workerURL
        self.bundleID = bundleID
        self.session = session
        self.hmacSecret = hmacSecret
    }

    public func lookup(code: String) async throws -> LookupResponse {
        try await postJSON(
            path: "/v1/refer/\(bundleID)/lookup",
            body: ["code": code]
        )
    }

    public func share(uuid: String) async throws -> ShareResponse {
        try await postJSON(
            path: "/v1/refer/\(bundleID)/share",
            body: ["uuid": uuid]
        )
    }

    public func claim(transactionID: String, productID: String) async throws -> ClaimResponse {
        try await postJSON(
            path: "/v1/refer/\(bundleID)/claim",
            body: ["transactionID": transactionID, "productID": productID]
        )
    }

    /// Returns parsed `/me` only after HMAC signature is verified.
    public func me(uuid: String) async throws -> MeResponse {
        guard let secret = hmacSecret else {
            throw ClientError.missingHmacSecret
        }
        let url = workerURL.appendingPathComponent("v1/refer/\(bundleID)/me/\(uuid)")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw ClientError.http(status: status, error: nil)
        }

        // Extract `_hmac` and re-serialize body without it
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providedHmac = raw["_hmac"] as? String else {
            throw ClientError.decoding("missing _hmac")
        }
        var bodyDict = raw
        bodyDict.removeValue(forKey: "_hmac")
        let bodyData = try JSONSerialization.data(
            withJSONObject: bodyDict,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
        let bodyStr = String(data: bodyData, encoding: .utf8) ?? ""
        guard try ReferralHMAC.verify(secret: secret, body: bodyStr, signatureHex: providedHmac) else {
            throw ClientError.hmacMismatch
        }

        // Decode the verified body
        return try JSONDecoder.referralKit.decode(MeResponse.self, from: bodyData)
    }

    private func postJSON<T: Decodable>(
        path: String,
        body: [String: String]
    ) async throws -> T {
        let url = workerURL.appendingPathComponent(path.trimmingCharacters(in: ["/"]))
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw ClientError.http(status: -1, error: nil)
        }
        if http.statusCode >= 200 && http.statusCode < 300 {
            return try JSONDecoder.referralKit.decode(T.self, from: data)
        }
        let err = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw ClientError.http(status: http.statusCode, error: err)
    }
}

extension JSONDecoder {
    static let referralKit: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

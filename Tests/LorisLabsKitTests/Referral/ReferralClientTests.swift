import Testing
import Foundation
@testable import LorisLabsKit

@MainActor
@Suite(.serialized)
struct ReferralClientTests {
    let workerURL = URL(string: "https://referrals.test/")!
    let bundleID = "com.test.app"

    @Test func lookup_returnsClaimNonce() async throws {
        URLProtocolStub.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/v1/refer/com.test.app/lookup")
            let body = """
            {"ok":true,"claimNonce":"nonce-uuid","appName":"X","refereeReward":"30 days free","expiresAt":"2099-01-01T00:00:00Z"}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = ReferralClient(workerURL: workerURL, bundleID: bundleID, session: URLProtocolStub.makeSession())
        let result = try await client.lookup(code: "K3F7AB")
        #expect(result.claimNonce == "nonce-uuid")
        #expect(result.appName == "X")
    }

    @Test func lookup_rejectsUnknownCode() async throws {
        URLProtocolStub.handler = { request in
            let body = #"{"ok":false,"error":"UNKNOWN_CODE"}"#.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = ReferralClient(workerURL: workerURL, bundleID: bundleID, session: URLProtocolStub.makeSession())
        await #expect(throws: ReferralClient.ClientError.self) {
            _ = try await client.lookup(code: "NONE99")
        }
    }

    @Test func share_returnsCode() async throws {
        URLProtocolStub.handler = { request in
            let body = """
            {"ok":true,"code":"K3F7AB","confirmedReferrals":0,"pendingReferrals":0}
            """.data(using: .utf8)!
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = ReferralClient(workerURL: workerURL, bundleID: bundleID, session: URLProtocolStub.makeSession())
        let r = try await client.share(uuid: "uuid-1")
        #expect(r.code == "K3F7AB")
    }

    @Test func me_verifiesHMACSignature() async throws {
        let secret = "test-secret"
        // Keys in alphabetical order to match JSONSerialization.data(.sortedKeys)
        // Note: underscore (0x5F) sorts before lowercase letters in ASCII
        let body = "{\"_signedAt\":\"2026-04-29T12:00:00Z\",\"bonusUntil\":null,\"code\":\"ABCDEF\",\"confirmedReferrals\":3,\"pendingReferrals\":0,\"rewardsAvailable\":[],\"tiersUnlocked\":[],\"uuid\":\"u\"}"
        let sig = try ReferralHMAC.sign(secret: secret, body: body)
        let signedBody = body.dropLast() + ",\"_hmac\":\"\(sig)\"}"
        URLProtocolStub.handler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(signedBody.utf8))
        }
        let client = ReferralClient(workerURL: workerURL, bundleID: bundleID, session: URLProtocolStub.makeSession(), hmacSecret: secret)
        let me = try await client.me(uuid: "u")
        #expect(me.confirmedReferrals == 3)
    }

    @Test func me_rejectsTamperedHMAC() async throws {
        let body = "{\"uuid\":\"u\",\"code\":\"ABCDEF\",\"confirmedReferrals\":3,\"pendingReferrals\":0,\"bonusUntil\":null,\"tiersUnlocked\":[],\"rewardsAvailable\":[],\"_signedAt\":\"2026-04-29T12:00:00Z\",\"_hmac\":\"" + String(repeating: "0", count: 64) + "\"}"
        URLProtocolStub.handler = { request in
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let client = ReferralClient(workerURL: workerURL, bundleID: bundleID, session: URLProtocolStub.makeSession(), hmacSecret: "real-secret")
        await #expect(throws: ReferralClient.ClientError.self) {
            _ = try await client.me(uuid: "u")
        }
    }
}

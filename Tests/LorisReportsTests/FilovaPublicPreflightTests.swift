import XCTest
@testable import LorisReports

private struct FilovaPublicReadOnlyTransport: FeedbackHTTPTransport {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> FeedbackHTTPResponse {
        guard request.httpMethod == "GET", request.httpBody == nil,
              request.url?.absoluteString == "https://help.lorislab.fr/v2/apps" else { throw FeedbackClientError.invalidReport }
        return try await NativeFeedbackHTTPTransport().send(request, maximumBytes: maximumBytes)
    }
}
final class FilovaPublicPreflightTests: XCTestCase, @unchecked Sendable {
    func testNativePublicAllowlistReadOnly() async throws {
        guard ProcessInfo.processInfo.environment["FILOVA_PUBLIC_PREFLIGHT"] == "1" else { throw XCTSkip("Opt-in public GET only") }
        let client = FeedbackClient(profile: .init(appID: "filova", displayName: "Filova", allowedFields: [.component,.permissionState]),
            configuration: .init(directory: URL(fileURLWithPath: "/unused")), transport: FilovaPublicReadOnlyTransport())
        let allowed = try await client.isAppAuthorized()
        let expectation = ProcessInfo.processInfo.environment["FILOVA_EXPECT_AUTHORIZED"] ?? "0"
        guard ["0", "1"].contains(expectation) else { throw FeedbackClientError.invalidReport }
        XCTAssertEqual(allowed, expectation == "1", "Public authorization differs from the explicitly selected dated expectation")
        print("Native URLSession GET /v2/apps: filova authorized=\(allowed); no report, reply or Keychain operation")
    }
}

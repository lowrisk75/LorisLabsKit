import Foundation
import XCTest
@testable import LorisReports

private final class ResponseProbe: @unchecked Sendable {
    let lock = NSLock()
    let status: Int; let length: Int?; let responseURL: URL?
    let chunks: [Data]; let interval: Double
    var sent = 0; var stopped = false; var requests = 0
    init(status: Int = 200, length: Int? = nil, responseURL: URL? = nil, chunks: [Data], interval: Double = 0.01) {
        self.status = status; self.length = length; self.responseURL = responseURL; self.chunks = chunks; self.interval = interval
    }
}
private final class ProbeRegistry: @unchecked Sendable {
    let lock = NSLock(); var probes: [String: ResponseProbe] = [:]
    func add(_ probe: ResponseProbe, url: URL) { lock.withLock { probes[url.path] = probe } }
    func get(_ url: URL) -> ResponseProbe? { lock.withLock { probes[url.path] } }
    func remove(_ url: URL) { _ = lock.withLock { probes.removeValue(forKey: url.path) } }
}
private final class BoundedResponseProtocol: URLProtocol, @unchecked Sendable {
    static let registry = ProbeRegistry()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "synthetic.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let probe = Self.registry.get(url) else { return }
        probe.lock.withLock { probe.requests += 1 }
        var headers = ["Content-Type": "application/json"]
        if let length = probe.length { headers["Content-Length"] = String(length) }
        if probe.status == 302 { headers["Location"] = "https://other.invalid/private" }
        let response = HTTPURLResponse(url: probe.responseURL ?? url, statusCode: probe.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        deliver(0, probe: probe)
    }
    private func deliver(_ index: Int, probe: ResponseProbe) {
        DispatchQueue.global().asyncAfter(deadline: .now() + probe.interval) { [self] in
            guard probe.lock.withLock({ !probe.stopped }) else { return }
            guard index < probe.chunks.count else { client?.urlProtocolDidFinishLoading(self); return }
            probe.lock.withLock { probe.sent += 1 }
            client?.urlProtocol(self, didLoad: probe.chunks[index])
            deliver(index + 1, probe: probe)
        }
    }
    override func stopLoading() {
        if let url = request.url, let probe = Self.registry.get(url) { probe.lock.withLock { probe.stopped = true } }
    }
}

final class NativeTransportTests: XCTestCase, @unchecked Sendable {
    private func fixture(_ probe: ResponseProbe) -> (NativeFeedbackHTTPTransport, URLRequest) {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [BoundedResponseProtocol.self]
        let session = URLSession(configuration: config)
        let transport = NativeFeedbackHTTPTransport(session: session); session.invalidateAndCancel()
        let url = URL(string: "https://synthetic.invalid/" + UUID().uuidString)!
        BoundedResponseProtocol.registry.add(probe, url: url)
        return (transport, URLRequest(url: url))
    }
    func testExactLimitAcrossChunks() async throws {
        let probe = ResponseProbe(length: 8, chunks: [Data("1234".utf8), Data("5678".utf8)])
        let (transport, request) = fixture(probe); defer { BoundedResponseProtocol.registry.remove(request.url!) }
        let response = try await transport.send(request, maximumBytes: 8)
        XCTAssertEqual(response.data, Data("12345678".utf8)); XCTAssertEqual(response.statusCode, 200)
    }
    func testAnnouncedOversizeIsCanceledBeforeBody() async throws {
        let probe = ResponseProbe(length: 9, chunks: [Data(repeating: 1, count: 9)])
        let (transport, request) = fixture(probe); defer { BoundedResponseProtocol.registry.remove(request.url!) }
        do { _ = try await transport.send(request, maximumBytes: 8); XCTFail("Must reject header") }
        catch ReportTransportError.invalidResponse { }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(probe.lock.withLock { probe.sent }, 0)
        XCTAssertTrue(probe.lock.withLock { probe.stopped })
    }
    func testUnknownLengthAndMisleadingLengthCancelOnFirstOverflow() async throws {
        for length in [nil, 1] as [Int?] {
            let probe = ResponseProbe(length: length, chunks: Array(repeating: Data(repeating: 1, count: 4), count: 20))
            let (transport, request) = fixture(probe); defer { BoundedResponseProtocol.registry.remove(request.url!) }
            do { _ = try await transport.send(request, maximumBytes: 8); XCTFail("Must stop while receiving") }
            catch ReportTransportError.invalidResponse { }
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertLessThan(probe.lock.withLock { probe.sent }, 20)
            XCTAssertTrue(probe.lock.withLock { probe.stopped })
        }
    }
    func testRedirectStatusAndDifferentResponseURLRejected() async throws {
        for probe in [ResponseProbe(status: 302, chunks: [Data("redirect".utf8)]),
                      ResponseProbe(responseURL: URL(string: "https://other.invalid/")!, chunks: [])] {
            let (transport, request) = fixture(probe); defer { BoundedResponseProtocol.registry.remove(request.url!) }
            do { _ = try await transport.send(request, maximumBytes: 32); XCTFail("Reject changed URL or redirect") }
            catch ReportTransportError.invalidResponse { }
            catch ReportTransportError.rejected(statusCode: 302) { }
            XCTAssertEqual(probe.lock.withLock { probe.requests }, 1)
        }
    }
    func testTaskCancellationStopsReception() async throws {
        let probe = ResponseProbe(chunks: Array(repeating: Data([1]), count: 100), interval: 0.02)
        let (transport, request) = fixture(probe); defer { BoundedResponseProtocol.registry.remove(request.url!) }
        let task = Task { try await transport.send(request, maximumBytes: 100) }
        try await Task.sleep(for: .milliseconds(60)); task.cancel()
        do { _ = try await task.value; XCTFail("Canceled") } catch is CancellationError { }
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(probe.lock.withLock { probe.stopped })
        XCTAssertLessThan(probe.lock.withLock { probe.sent }, 100)
    }
    func testCancellationBeforeStartAndInvalidBoundDoNotSend() async throws {
        let probe = ResponseProbe(chunks: [])
        let (transport, request) = fixture(probe); defer { BoundedResponseProtocol.registry.remove(request.url!) }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await transport.send(request, maximumBytes: 8)
        }
        do { _ = try await task.value; XCTFail("Canceled") } catch is CancellationError { }
        do { _ = try await transport.send(request, maximumBytes: 0); XCTFail("Invalid bound") }
        catch ReportTransportError.invalidResponse { }
        XCTAssertEqual(probe.lock.withLock { probe.requests }, 0)
    }
    func testInvalidJSONIsNotAppAuthorization() async throws {
        let probe = ResponseProbe(chunks: [Data("not-json".utf8)])
        let (transport, request) = fixture(probe)
        let base = request.url!.deletingLastPathComponent()
        let apps = base.appendingPathComponent("v2/apps")
        BoundedResponseProtocol.registry.add(probe, url: apps)
        defer { BoundedResponseProtocol.registry.remove(request.url!); BoundedResponseProtocol.registry.remove(apps) }
        let profile = FeedbackAppProfile(appID: "siliconpass", displayName: "Synthetic", allowedFields: [], endpoint: base)
        let client = FeedbackClient(profile: profile, configuration: FeedbackConfiguration(directory: URL(fileURLWithPath: "/unused"), keychainAccessGroup: "TESTTEAM.com.lorislab.siliconpass.support"), transport: transport)
        do { _ = try await client.isAppAuthorized(); XCTFail("Invalid JSON") } catch is DecodingError { }
    }
}

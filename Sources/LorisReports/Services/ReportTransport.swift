import Foundation

public struct ReportDeliveryReceipt: Codable, Equatable, Sendable {
    public let publicReference: String
    public let trackingToken: String
    public let receivedAt: Date
    public let duplicate: Bool
    public let rawExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case publicReference = "public_reference"
        case trackingToken = "tracking_token"
        case receivedAt = "received_at"
        case duplicate
        case rawExpiresAt = "raw_expires_at"
    }
}

public protocol ReportTransport: Sendable {
    /// Performs the first network operation. Constructing a transport or envelope never sends data.
    func submit(_ envelope: ReportEnvelope) async throws -> ReportDeliveryReceipt
}

public enum ReportTransportError: Error, Equatable, Sendable {
    case invalidEndpoint
    case invalidResponse
    case rejected(statusCode: Int)
}

public struct DirectReportTransport: ReportTransport, Sendable {
    private let endpoint: URL
    private let transport: any FeedbackHTTPTransport
    private let redactor: ReportRedactionPipeline

    public init(endpoint: URL, session: URLSession? = nil, redactor: ReportRedactionPipeline = .init()) {
        self.endpoint = endpoint
        self.transport = NativeFeedbackHTTPTransport(session: session)
        self.redactor = redactor
    }

    public init(endpoint: URL, transport: any FeedbackHTTPTransport, redactor: ReportRedactionPipeline = .init()) {
        self.endpoint = endpoint; self.transport = transport; self.redactor = redactor
    }

    private func boundedData(for request: URLRequest, maximumBytes: Int = 128 * 1024) async throws -> (Data, HTTPURLResponse) {
        let result = try await transport.send(request, maximumBytes: maximumBytes)
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: result.statusCode, httpVersion: nil, headerFields: nil) else {
            throw ReportTransportError.invalidResponse
        }
        return (result.data, response)
    }

    public func submit(_ envelope: ReportEnvelope) async throws -> ReportDeliveryReceipt {
        let recoveryToken = UUID().uuidString + UUID().uuidString
        return try await submit(envelope, recoveryToken: recoveryToken)
    }

    public func submit(_ envelope: ReportEnvelope, recoveryToken: String) async throws -> ReportDeliveryReceipt {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
              endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
              (32...128).contains(recoveryToken.utf8.count) else {
            throw ReportTransportError.invalidEndpoint
        }
        let redacted = try redactor.redact(envelope)
        guard let challengeURL = URL(string: "v\(envelope.version)/challenges", relativeTo: endpoint)?.absoluteURL else {
            throw ReportTransportError.invalidEndpoint
        }
        guard let url = URL(string: "v\(envelope.version)/reports", relativeTo: endpoint)?.absoluteURL else {
            throw ReportTransportError.invalidEndpoint
        }
        guard challengeURL.scheme == endpoint.scheme, challengeURL.host == endpoint.host, challengeURL.port == endpoint.port,
              url.scheme == endpoint.scheme, url.host == endpoint.host, url.port == endpoint.port else {
            throw ReportTransportError.invalidEndpoint
        }
        var challengeRequest = URLRequest(url: challengeURL)
        challengeRequest.httpMethod = "POST"
        let (challengeData, challengeResponse) = try await boundedData(for: challengeRequest, maximumBytes: 16 * 1024)
        let challengeHTTP = challengeResponse
        guard (200..<300).contains(challengeHTTP.statusCode),
              let challengeObject = try JSONSerialization.jsonObject(with: challengeData) as? [String: Any],
              let challenge = challengeObject["challenge"] as? String else {
            throw ReportTransportError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(envelope.clientReportID.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        request.setValue(challenge, forHTTPHeaderField: "X-Feedback-Challenge")
        request.setValue(recoveryToken, forHTTPHeaderField: "X-Receipt-Recovery-Token")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(redacted)
        let (data, response) = try await boundedData(for: request)
        let http = response
        guard (200..<300).contains(http.statusCode) else {
            throw ReportTransportError.rejected(statusCode: http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let plain = ISO8601DateFormatter()
            guard let date = plain.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Invalid ISO-8601 date"
                )
            }
            return date
        }
        return try decoder.decode(ReportDeliveryReceipt.self, from: data)
    }
}

public struct ExportOnlyReportTransport: ReportTransport, Sendable {
    public init() {}

    public func submit(_ envelope: ReportEnvelope) async throws -> ReportDeliveryReceipt {
        _ = envelope
        throw ReportTransportError.rejected(statusCode: 501)
    }
}

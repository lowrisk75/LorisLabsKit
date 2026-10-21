import Foundation

/// Each request has its own delegate and bounded buffer. Supplied sessions contribute
/// configuration (including test protocol classes), never cookies, credentials or delegates.
public struct NativeFeedbackHTTPTransport: FeedbackHTTPTransport {
    private let configuration: URLSessionConfiguration
    public init(session: URLSession? = nil) {
        let configuration = session?.configuration ?? .ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 45
        self.configuration = configuration
    }
    public func send(_ request: URLRequest, maximumBytes: Int) async throws -> FeedbackHTTPResponse {
        guard let url = request.url, url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { throw ReportTransportError.invalidEndpoint }
        guard maximumBytes > 0, maximumBytes <= 512 * 1024 else { throw ReportTransportError.invalidResponse }
        let operation = BoundedFeedbackRequest(url: url, maximumBytes: maximumBytes)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.start(request, configuration: configuration, continuation: continuation)
            }
        } onCancel: { operation.cancel() }
    }
}

/// The lock protects both the continuation and buffer. Cancellation may arrive
/// before start, while a delegate callback is running, or after completion.
final class BoundedFeedbackRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let maximumBytes: Int
    private var continuation: CheckedContinuation<FeedbackHTTPResponse, any Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var data = Data()
    private var status: Int?
    private var finished = false
    init(url: URL, maximumBytes: Int) { self.url = url; self.maximumBytes = maximumBytes }

    func start(_ request: URLRequest, configuration: URLSessionConfiguration,
               continuation: CheckedContinuation<FeedbackHTTPResponse, any Error>) {
        let task: URLSessionDataTask? = lock.withLock {
            guard !finished else { return nil }
            self.continuation = continuation
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            let task = session.dataTask(with: request)
            self.task = task
            return task
        }
        guard let task else { continuation.resume(throwing: CancellationError()); return }
        task.resume()
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func finish(_ result: Result<FeedbackHTTPResponse, any Error>) {
        let resources = lock.withLock { () -> (CheckedContinuation<FeedbackHTTPResponse, any Error>?, URLSession?)? in
            guard !finished else { return nil }
            finished = true
            let result = (continuation, session)
            continuation = nil; task = nil; session = nil; data = Data()
            return result
        }
        guard let resources else { return }
        resources.1?.invalidateAndCancel()
        resources.0?.resume(with: result)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse, response.url == url else {
            finish(.failure(ReportTransportError.invalidResponse)); completionHandler(.cancel); return
        }
        guard !(300..<400).contains(response.statusCode) else {
            finish(.failure(ReportTransportError.rejected(statusCode: response.statusCode))); completionHandler(.cancel); return
        }
        guard response.expectedContentLength <= Int64(maximumBytes) else {
            finish(.failure(ReportTransportError.invalidResponse)); completionHandler(.cancel); return
        }
        let accepted = lock.withLock { () -> Bool in
            guard !finished else { return false }
            status = response.statusCode; return true
        }
        completionHandler(accepted ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        let overflow = lock.withLock { () -> Bool in
            guard !finished else { return false }
            guard status != nil, chunk.count <= maximumBytes - data.count else { return true }
            data.append(chunk); return false
        }
        if overflow { finish(.failure(ReportTransportError.invalidResponse)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error { finish(.failure(error)); return }
        let response = lock.withLock { status.map { FeedbackHTTPResponse(data: data, statusCode: $0) } }
        if let response { finish(.success(response)) }
        else { finish(.failure(ReportTransportError.invalidResponse)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        finish(.failure(ReportTransportError.rejected(statusCode: response.statusCode)))
        completionHandler(nil)
    }
}

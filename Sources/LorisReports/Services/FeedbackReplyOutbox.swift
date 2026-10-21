import Foundation

/// Only a confirmed operation is persisted. Conversation capabilities remain in
/// the host's ticket storage, never in this queue. One uncertain operation per ticket.
public struct PendingFeedbackReply: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let reference: String
    public let expectedVersion: Int
    public let kind: String
    public private(set) var body: String
    public let confirmedAt: Date
    public fileprivate(set) var attempted: Bool
    public fileprivate(set) var expired: Bool
    mutating func scrubExpired() { body = ""; expired = true }
    var payload: Data {
        get throws {
            let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
            return try encoder.encode(Payload(clientMessageID: id, body: body, expectedVersion: expectedVersion, kind: kind))
        }
    }
    private struct Payload: Encodable {
        let clientMessageID: UUID; let body: String; let expectedVersion: Int; let kind: String
        enum CodingKeys: String, CodingKey {
            case body, kind, clientMessageID = "client_message_id", expectedVersion = "expected_version"
        }
    }
}

public enum FeedbackReplyOutboxError: Error { case conflict, full, expired, invalidOperation }

actor FeedbackReplyOutbox {
    private let directory: URL
    private let maximumBytes = 256 * 1024
    init(directory: URL) { self.directory = directory }

    func stage(reference: String, id: UUID, body: String, version: Int, kind: String,
               now: Date = Date()) throws -> PendingFeedbackReply {
        guard validReference(reference), version >= 1, ["message", "resolved", "reopened"].contains(kind),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, body.count <= 10000 else {
            throw FeedbackReplyOutboxError.invalidOperation
        }
        let operations = try pending(now: now)
        if let previous = operations.first(where: { $0.reference == reference }) {
            guard !previous.expired else { throw FeedbackReplyOutboxError.expired }
            // Refreshing the conversation must not silently change a confirmed payload.
            guard previous.id == id, previous.body == body, previous.kind == kind else {
                throw FeedbackReplyOutboxError.conflict
            }
            return previous
        }
        guard !operations.contains(where: { $0.id == id }) else { throw FeedbackReplyOutboxError.conflict }
        guard operations.count < 20 else { throw FeedbackReplyOutboxError.full }
        let operation = PendingFeedbackReply(id: id, reference: reference, expectedVersion: version,
            kind: kind, body: body, confirmedAt: now, attempted: false, expired: false)
        let encoder = JSONEncoder()
        guard try operations.reduce(encoder.encode(operation).count, { try $0 + encoder.encode($1).count }) <= maximumBytes else {
            throw FeedbackReplyOutboxError.full
        }
        try write(operation)
        return operation
    }
    func pending(now: Date = Date()) throws -> [PendingFeedbackReply] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
            .filter { validReference($0.deletingPathExtension().lastPathComponent) && $0.pathExtension == "json" }
        guard files.count <= 20 else { throw FeedbackReplyOutboxError.full }
        var totalBytes = 0
        let operations = try files
            .map { url in
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey, .isRegularFileKey])
                guard values.isSymbolicLink != true, values.isRegularFile == true,
                      let size = values.fileSize, size <= maximumBytes - totalBytes else {
                    throw FeedbackReplyOutboxError.invalidOperation
                }
                totalBytes += size
                var operation = try JSONDecoder().decode(PendingFeedbackReply.self, from: Data(contentsOf: url))
                guard operation.reference == url.deletingPathExtension().lastPathComponent,
                      operation.expectedVersion >= 1, ["message", "resolved", "reopened"].contains(operation.kind),
                      operation.body.count <= 10000,
                      operation.confirmedAt <= now.addingTimeInterval(300) else { throw FeedbackReplyOutboxError.invalidOperation }
                if !operation.expired && now.timeIntervalSince(operation.confirmedAt) > 7 * 86400 {
                    // Retain a bounded marker until explicit deletion, so expiration never
                    // permits a new UUID to bypass an uncertain server acknowledgement.
                    operation.scrubExpired(); try write(operation)
                }
                return operation
            }.sorted { $0.confirmedAt < $1.confirmedAt }
        guard Set(operations.map(\.id)).count == operations.count else { throw FeedbackReplyOutboxError.invalidOperation }
        return operations
    }
    func markAttempted(_ operation: PendingFeedbackReply) throws -> PendingFeedbackReply {
        guard let stored = try pending().first(where: { $0.reference == operation.reference }),
              !stored.expired, stored == operation else { throw FeedbackReplyOutboxError.invalidOperation }
        var operation = stored; operation.attempted = true; try write(operation); return operation
    }
    func remove(reference: String) throws {
        guard validReference(reference) else { throw FeedbackReplyOutboxError.invalidOperation }
        let url = file(reference)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func validReference(_ value: String) -> Bool {
        value.range(of: "^[A-Z0-9]+-[0-9]{4}-[A-Z0-9]+$", options: .regularExpression) != nil && value.count <= 100
    }
    private func file(_ reference: String) -> URL { directory.appendingPathComponent(reference + ".json") }
    private func write(_ operation: PendingFeedbackReply) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var root = directory; var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try root.setResourceValues(flags)
        let data = try JSONEncoder().encode(operation)
        #if os(iOS) || os(visionOS) || os(watchOS) || os(tvOS)
        try data.write(to: file(operation.reference), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file(operation.reference), options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(operation.reference).path)
    }
}

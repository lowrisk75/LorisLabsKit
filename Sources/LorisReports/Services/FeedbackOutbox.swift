import Foundation
import Security

struct PendingFeedbackDelivery: Sendable {
    let envelope: ReportEnvelope
    let recoveryToken: String
}

/// Only explicitly confirmed reports enter this outbox. It stores a one-purpose
/// receipt-recovery capability, never the stronger conversation tracking token.
public actor FeedbackOutbox {
    private struct StoredReport: Codable {
        let envelope: ReportEnvelope
        let recoveryToken: String
    }
    private let directory: URL
    private let maximumBytes = 10 * 1024 * 1024
    public init(directory: URL) { self.directory = directory }

    @discardableResult
    public func enqueue(_ envelope: ReportEnvelope) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var root = directory
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try root.setResourceValues(flags)
        _ = try pending() // Expired reports must not consume the bounded queue.
        let destination = directory.appendingPathComponent(filename(envelope.clientReportID))
        if FileManager.default.fileExists(atPath: destination.path) {
            let existing = try decode(destination)
            guard existing.envelope == envelope else { throw FeedbackOutboxError.conflict }
            return existing.recoveryToken
        }
        let stored = StoredReport(envelope: envelope, recoveryToken: try makeRecoveryToken())
        let data = try JSONEncoder().encode(stored)
        let files = try reportFiles()
        let used = try files.filter { $0.lastPathComponent != filename(envelope.clientReportID) }.reduce(0) { total, url in
            total + (try Data(contentsOf: url).count)
        }
        guard used + data.count <= maximumBytes else { throw FeedbackOutboxError.full }
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: destination, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        return stored.recoveryToken
    }
    public func pending(now: Date = Date()) throws -> [ReportEnvelope] {
        try pendingDeliveries(now: now).map(\.envelope)
    }
    func pendingDeliveries(now: Date = Date()) throws -> [PendingFeedbackDelivery] {
        try reportFiles().compactMap { url in
            let stored: StoredReport
            do {
                stored = try decode(url)
            } catch {
                try quarantineCorrupt(url)
                return nil
            }
            if now.timeIntervalSince(stored.envelope.consent.grantedAt) > 7 * 86_400 {
                try FileManager.default.removeItem(at: url); return nil
            }
            return PendingFeedbackDelivery(envelope: stored.envelope, recoveryToken: stored.recoveryToken)
        }.sorted { $0.envelope.consent.grantedAt < $1.envelope.consent.grantedAt }
    }
    public func remove(_ id: UUID) throws {
        let url = directory.appendingPathComponent(filename(id))
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    private func filename(_ id: UUID) -> String { id.uuidString.lowercased() + ".json" }
    private func decode(_ url: URL) throws -> StoredReport {
        let data = try Data(contentsOf: url)
        if let stored = try? JSONDecoder().decode(StoredReport.self, from: data), stored.recoveryToken.count >= 32 {
            return stored
        }
        // One-time local migration for reports queued by the pre-recovery SDK.
        let envelope = try JSONDecoder().decode(ReportEnvelope.self, from: data)
        let migrated = StoredReport(envelope: envelope, recoveryToken: try makeRecoveryToken())
        let encoded = try JSONEncoder().encode(migrated)
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        try encoded.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try encoded.write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return migrated
    }
    private func makeRecoveryToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw FeedbackOutboxError.randomness
        }
        return Data(bytes).base64EncodedString()
    }
    private func reportFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ).filter { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true && values.isSymbolicLink != true &&
                url.pathExtension == "json" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
        }
    }
    private func quarantineCorrupt(_ url: URL) throws {
        let corrupt = directory.appendingPathComponent("corrupt", isDirectory: true)
        try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: corrupt.path)
        let destination = corrupt.appendingPathComponent(url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: url, to: destination)
    }
}
public enum FeedbackOutboxError: Error { case full, conflict, randomness }

#if canImport(SQLite3)
import Foundation
import SQLite3
import Testing
@testable import LorisSync

private enum OutboxSQLFixtureError: Error, Equatable { case missingRoot, invalidRoot, existingFile, sql(Int32), injected }

/// Test-only host transaction. No app schema, provider, process spawning or production dependency.
private final class OutboxSQLHost {
    let url: URL
    private var db: OpaquePointer?

    static func create() throws -> OutboxSQLHost {
        guard let path = ProcessInfo.processInfo.environment["LORIS_SYNC_OUTBOX_TEST_ROOT"] else {
            throw OutboxSQLFixtureError.missingRoot
        }
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var directory: ObjCBool = false
        guard path.hasPrefix("/"), root.path == root.resolvingSymlinksInPath().path,
              FileManager.default.fileExists(atPath: root.path, isDirectory: &directory), directory.boolValue else {
            throw OutboxSQLFixtureError.invalidRoot
        }
        let url = root.appendingPathComponent(UUID().uuidString + ".sqlite")
        guard !FileManager.default.fileExists(atPath: url.path) else { throw OutboxSQLFixtureError.existingFile }
        return try OutboxSQLHost(url: url, create: true)
    }

    init(url: URL, create: Bool = false) throws {
        self.url = url
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (create ? SQLITE_OPEN_CREATE : 0)
        let code = sqlite3_open_v2(url.path, &pointer, flags, nil)
        guard code == SQLITE_OK, let pointer else {
            if let pointer { sqlite3_close_v2(pointer) }
            throw OutboxSQLFixtureError.sql(code)
        }
        db = pointer
        if create {
            try execute("PRAGMA journal_mode=DELETE")
            try execute("PRAGMA synchronous=FULL")
            try execute("CREATE TABLE state (key TEXT PRIMARY KEY, payload BLOB NOT NULL)")
        }
    }
    deinit { if let db { sqlite3_close_v2(db) } }

    func close() throws {
        if let pointer = db {
            let code = sqlite3_close(pointer)
            guard code == SQLITE_OK else { throw OutboxSQLFixtureError.sql(code) }
            db = nil
        }
    }
    func execute(_ sql: String) throws {
        guard let db else { throw OutboxSQLFixtureError.sql(SQLITE_MISUSE) }
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else { throw OutboxSQLFixtureError.sql(code) }
    }
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            if let db, sqlite3_get_autocommit(db) == 0 { try execute("ROLLBACK") }
            throw error
        }
    }
    func write(_ key: String, _ data: Data) throws {
        guard let db else { throw OutboxSQLFixtureError.sql(SQLITE_MISUSE) }
        var statement: OpaquePointer?
        let sql = "INSERT INTO state(key,payload) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload"
        let prepared = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw OutboxSQLFixtureError.sql(prepared) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let keyCode = key.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
        guard keyCode == SQLITE_OK, data.count <= Int(Int32.max) else {
            throw OutboxSQLFixtureError.sql(keyCode)
        }
        let blobCode: Int32
        if data.isEmpty { blobCode = sqlite3_bind_zeroblob(statement, 2, 0) }
        else {
            blobCode = data.withUnsafeBytes {
                sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32($0.count), transient)
            }
        }
        guard blobCode == SQLITE_OK else { throw OutboxSQLFixtureError.sql(blobCode) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else { throw OutboxSQLFixtureError.sql(code) }
    }
    func read(_ key: String) throws -> Data? {
        guard let db else { throw OutboxSQLFixtureError.sql(SQLITE_MISUSE) }
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(db, "SELECT payload FROM state WHERE key=?", -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw OutboxSQLFixtureError.sql(prepared) }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let keyCode = key.withCString { sqlite3_bind_text(statement, 1, $0, -1, transient) }
        guard keyCode == SQLITE_OK else { throw OutboxSQLFixtureError.sql(keyCode) }
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE { return nil }
        guard code == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_BLOB else {
            throw OutboxSQLFixtureError.sql(code)
        }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count <= 16_777_216 else { throw OutboxSQLFixtureError.invalidRoot }
        if count == 0 { return Data() }
        guard let bytes = sqlite3_column_blob(statement, 0) else { throw OutboxSQLFixtureError.sql(SQLITE_CORRUPT) }
        return Data(bytes: bytes, count: count)
    }
}

@Suite("Outbox host SQLite commit/rollback/reopen", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["LORIS_SYNC_OUTBOX_TEST_ROOT"] != nil,
                "Requires an explicitly registered mission-owned fixture directory"))
struct OutboxSQLiteTransactionTests {
    let scope = SyncOutboxScope(accountID: "fixture-a", namespace: "fixture-provider/private/owner/zone")
    let key = SyncOutboxKey(recordType: "Fixture", recordID: "record")

    @Test(arguments: [false, true])
    func twoContractShapesCommitDomainAndJournalTogether(presealedShape: Bool) throws {
        let host = try OutboxSQLHost.create()
        let payload = presealedShape ? Data([0xAA, 0, 0xF1]) : Data(#"{"profile":"fixture"}"#.utf8)
        var candidate = try RevisionedSyncOutbox(scope: scope)
        try host.transaction {
            try candidate.enqueue(.save(payload), for: key, scope: scope)
            try host.write("domain", payload)
            try host.write("outbox", candidate.encoded())
        }
        // Publish candidate only after transaction returns successfully.
        try host.close()
        let reopened = try OutboxSQLHost(url: host.url)
        #expect(try reopened.read("domain") == payload)
        var journal = try load(reopened)
        let session = try journal.beginSession(for: scope)
        let delivery = try #require(try journal.pending(using: session).first)
        #expect(delivery.operation == .save(payload))
        #expect(delivery.receipt.revision == 1)
        try reopened.close()
    }

    @Test func failedHostTransactionRollsBackDomainAndOutbox() throws {
        let host = try baseline()
        let before = try #require(try host.read("outbox"))
        var unpublished = try load(host)
        #expect(throws: OutboxSQLFixtureError.injected) {
            try host.transaction {
                try unpublished.enqueue(.save(Data([2])), for: key, scope: scope)
                try host.write("domain", Data([2]))
                try host.write("outbox", unpublished.encoded())
                throw OutboxSQLFixtureError.injected
            }
        }
        #expect(try host.read("domain") == Data([1]))
        #expect(try host.read("outbox") == before)
        #expect(try load(host).pendingCount == 0)
        try host.close()
    }

    @Test func abandonedTransactionCloseRollsBackOnReopenNotProcessCrashProof() throws {
        let host = try baseline()
        var unpublished = try load(host)
        try host.execute("BEGIN IMMEDIATE")
        try unpublished.enqueue(.save(Data([2])), for: key, scope: scope)
        try host.write("domain", Data([2]))
        try host.write("outbox", unpublished.encoded())
        try host.close() // SQLite documented rollback on close, not a killed process.
        let reopened = try OutboxSQLHost(url: host.url)
        #expect(try reopened.read("domain") == Data([1]))
        #expect(try load(reopened).pendingCount == 0)
        try reopened.close()
    }

    @Test func staleAckCannotDeleteNewerCommittedRevision() throws {
        let host = try OutboxSQLHost.create()
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.save(Data([1])), for: key, scope: scope)
        let session = try journal.beginSession(for: scope)
        let old = try #require(try journal.pending(using: session).first)
        try host.transaction {
            try host.write("domain", Data([1]))
            try host.write("outbox", journal.encoded())
        }
        try host.transaction {
            var current = try load(host)
            try current.enqueue(.save(Data([2])), for: key, scope: scope)
            try host.write("domain", Data([2]))
            try host.write("outbox", current.encoded())
        }
        try host.transaction {
            var current = try load(host)
            #expect(try !current.acknowledge(old.receipt, using: session))
            try host.write("outbox", current.encoded())
        }
        var current = try load(host)
        let newest = try #require(try current.pending(using: session).first)
        #expect(newest.receipt.revision == 2)
        try host.transaction {
            current = try load(host)
            #expect(try current.acknowledge(newest.receipt, using: session))
            try host.write("outbox", current.encoded())
            try host.write("serverMetadata", Data([9]))
        }
        try host.close()
        let reopened = try OutboxSQLHost(url: host.url)
        #expect(try reopened.read("domain") == Data([2]))
        #expect(try load(reopened).pendingCount == 0)
        #expect(try reopened.read("serverMetadata") == Data([9]))
        try reopened.close()
    }

    @Test func ackAndServerMetadataRollBackTogether() throws {
        let host = try OutboxSQLHost.create()
        var journal = try RevisionedSyncOutbox(scope: scope)
        try journal.enqueue(.delete, for: key, scope: scope)
        let session = try journal.beginSession(for: scope)
        let delivery = try #require(try journal.pending(using: session).first)
        try host.transaction { try host.write("outbox", journal.encoded()) }
        #expect(throws: OutboxSQLFixtureError.injected) {
            try host.transaction {
                var candidate = try load(host)
                #expect(try candidate.acknowledge(delivery.receipt, using: session))
                try host.write("outbox", candidate.encoded())
                try host.write("serverMetadata", Data([9]))
                throw OutboxSQLFixtureError.injected
            }
        }
        #expect(try load(host).pendingCount == 1)
        #expect(try host.read("serverMetadata") == nil)
        try host.close()
    }

    private func load(_ host: OutboxSQLHost) throws -> RevisionedSyncOutbox {
        try RevisionedSyncOutbox(restoring: #require(try host.read("outbox")), expectedScope: scope)
    }
    private func baseline() throws -> OutboxSQLHost {
        let host = try OutboxSQLHost.create()
        let journal = try RevisionedSyncOutbox(scope: scope)
        try host.transaction {
            try host.write("domain", Data([1]))
            try host.write("outbox", journal.encoded())
        }
        return host
    }
}
#endif

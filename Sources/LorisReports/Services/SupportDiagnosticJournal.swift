import Foundation

/// A device-local, opt-in journal. No API here performs network I/O or reads host content.
public actor SupportDiagnosticJournal {
    private struct State: Codable {
        var enabled = false
        var consentVersion = "support-local-journal-20261005"
        var events: [SupportDiagnosticEvent] = []
    }
    private var state = State()
    private let file: URL
    private let consentFile: URL
    private let appID: String
    private let qualified: Bool
    public init(appID: String, directory: URL, qualified: Bool = false) {
        self.appID = appID; self.file = directory.appendingPathComponent("local-journal.json"); self.qualified = qualified
        self.consentFile = directory.appendingPathComponent("journal-consent.json")
        if qualified, let consent = try? Data(contentsOf: consentFile), consent == Data("true".utf8), let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 2*1024*1024,
           let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(State.self, from: data),
           saved.consentVersion == state.consentVersion { state = saved }
    }
    public var isEnabled: Bool { qualified && state.enabled }
    public func setEnabled(_ enabled: Bool, now: Date = Date()) throws {
        guard qualified || !enabled else { throw FeedbackClientError.featureDisabled }
        if !enabled {
            // Disable in memory before touching disk, even if erasure of the file fails.
            state = State()
            if FileManager.default.fileExists(atPath: consentFile.path) {
                // Revoke durable permission before removing the data file.
                try SupportPrivateFile.write(Data("false".utf8), to: consentFile)
            }
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        try SupportPrivateFile.write(Data("true".utf8), to: consentFile)
        state.enabled = true
        prune(now: now)
        try persist()
    }
    public func record(_ event: SupportDiagnosticEvent, now: Date = Date()) throws {
        guard isEnabled, SupportDiagnosticPolicy.components(appID: appID).contains(event.component),
              event.occurredAt <= now.addingTimeInterval(300), event.occurredAt >= now.addingTimeInterval(-86_400) else { return }
        prune(now: now)
        guard !state.events.contains(where: { $0.id == event.id }) else { return }
        state.events.append(event)
        state.events = Array(state.events.suffix(1000))
        try persist()
    }
    public func snapshot(components: Set<SupportComponent>? = nil, since: Date? = nil, now: Date = Date()) throws -> [SupportDiagnosticEvent] {
        guard isEnabled else { return [] }
        prune(now: now)
        try persist()
        return state.events.filter { event in (components == nil || components!.contains(event.component)) && (since == nil || event.occurredAt >= since!) }
    }
    private func prune(now: Date) {
        state.events.removeAll { $0.occurredAt < now.addingTimeInterval(-86_400) || $0.occurredAt > now.addingTimeInterval(300)
            || !SupportDiagnosticPolicy.components(appID: appID).contains($0.component) }
        state.events = Array(state.events.suffix(1000))
    }
    private func persist() throws {
        var data = try JSONEncoder().encode(state)
        while data.count > 2*1024*1024 && !state.events.isEmpty {
            state.events.removeFirst(); data = try JSONEncoder().encode(state)
        }
        try SupportPrivateFile.write(data, to: file)
    }
}

enum SupportPrivateFile {
    static func write(_ data: Data, to file: URL) throws {
        var directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true; try directory.setResourceValues(flags)
        #if os(iOS) || os(watchOS) || os(tvOS) || os(visionOS)
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: file, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

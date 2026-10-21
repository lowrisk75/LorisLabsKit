import SwiftUI

/// A staged migration for legacy help surfaces. Main-app gates remain independent
/// of diagnostics, assistant and push qualification. Existing support stays reachable.
public struct FeedbackMigrationCenter<Legacy: View>: View {
    private let profile: FeedbackAppProfile
    private let client: FeedbackClient
    private let enabled: Bool
    private let legacy: () -> Legacy
    public init(profile: FeedbackAppProfile, bundle: Bundle = .main, @ViewBuilder legacy: @escaping () -> Legacy) {
        self.profile = profile; self.legacy = legacy
        self.enabled = FeedbackMigrationOwner.enabled(bundle)
        self.client = FeedbackMigrationOwner.client(profile: profile, bundle: bundle)
    }
    public var body: some View {
        Group {
            if enabled { FeedbackCenter(profile: profile, client: client, contextProvider: nil) }
            else { legacy() }
        }
    }
}

@MainActor
private enum FeedbackMigrationOwner {
    private static var clients: [String: FeedbackClient] = [:]
    static func enabled(_ bundle: Bundle) -> Bool {
        bundle.object(forInfoDictionaryKey: "LorisReportsBackendAllowed") as? Bool == true
            && bundle.object(forInfoDictionaryKey: "LorisReportsMessagingVerified") as? Bool == true
    }
    static func client(profile: FeedbackAppProfile, bundle: Bundle) -> FeedbackClient {
        if let client = clients[profile.appID] { return client }
        let safeID = profile.appID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LorisReports/\(safeID)", isDirectory: true)
        let client = FeedbackClient(profile: profile, configuration: .init(directory: directory,
            serverAuthorizationApproved: bundle.object(forInfoDictionaryKey: "LorisReportsBackendAllowed") as? Bool ?? false,
            nativeQualificationApproved: bundle.object(forInfoDictionaryKey: "LorisReportsMessagingVerified") as? Bool ?? false,
            features: .forBuild(bundle), requiresExactAppAuthorization: true))
        clients[profile.appID] = client
        return client
    }
}

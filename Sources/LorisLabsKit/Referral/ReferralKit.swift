import Foundation

/// Top-level namespace and entry point for the LorisLabs refer-a-friend
/// program. Apps call `ReferralKit.configure(bundleID:, workerURL:)` at
/// launch, then access state via `ReferralKit.shared` or use the SwiftUI
/// views.
@MainActor
public final class ReferralKit {
    /// The shared instance is created lazily by the first `configure(...)`
    /// call. Until then, accessing this throws a fatalError.
    public static var shared: ReferralKit {
        guard let instance = _shared else {
            fatalError("ReferralKit.configure(bundleID:, workerURL:) must be called before accessing ReferralKit.shared")
        }
        return instance
    }
    private static var _shared: ReferralKit?

    /// Bundle identifier the worker uses to scope per-app config.
    public let bundleID: String

    /// Base URL for `referrals.lorislab.fr` (or staging equivalent).
    public private(set) var workerURL: URL

    /// Observable entitlement source-of-truth — drop into your app's
    /// `hasPaidPro` gate.
    public let entitlement: ReferralEntitlement

    private init(bundleID: String, workerURL: URL) {
        self.bundleID = bundleID
        self.workerURL = workerURL
        self.entitlement = ReferralEntitlement()
    }

    /// Configure or reconfigure ReferralKit. Subsequent calls swap the
    /// worker URL (useful for staging) while preserving identity.
    public static func configure(bundleID: String, workerURL: URL) {
        if let existing = _shared, existing.bundleID == bundleID {
            existing.workerURL = workerURL
            return
        }
        _shared = ReferralKit(bundleID: bundleID, workerURL: workerURL)
    }

    /// Test seam: reset shared instance.
    static func _resetForTesting() {
        _shared = nil
    }
}

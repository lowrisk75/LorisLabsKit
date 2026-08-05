import Foundation
import Observation
import StoreKit

#if canImport(UIKit)
import UIKit
#endif

/// The StoreKit engine behind `LorisLabsPaywallView`.
///
/// Until now the kit shipped the paywall *view* but no engine, so every app
/// wrote its own manager — with product identifiers hardcoded, trials kept in
/// `UserDefaults`, and no visibility on whether a subscription was actually
/// renewing.
@MainActor
@Observable
public final class LorisPaywallStore {
    // MARK: Published state

    public private(set) var products: [Product] = []
    public private(set) var entitlement: EntitlementState = .none
    public private(set) var renewalStatus: RenewalStatus = .notSubscribed
    public private(set) var isLoadingProducts = false
    public private(set) var didLoadProducts = false

    /// True once entitlements have been read at least once — including for
    /// users who already paid.
    ///
    /// UI gates must wait for this before showing a paywall. Lumen shipped
    /// without it and paying subscribers hit the paywall on every cold launch
    /// until StoreKit finished reading entitlements (reported 2026-05-22).
    public private(set) var entitlementsLoaded = false

    /// Latest expiration seen across active entitlements; nil for lifetime
    /// purchases and for users who never paid.
    public private(set) var subscriptionExpiration: Date?

    /// Identifiers the user currently owns — lets a paywall tell which tier is
    /// active instead of only whether *something* was bought.
    public private(set) var purchasedProductIDs: Set<String> = []

    /// Set when a purchase or restore fails, for the view to display.
    public var lastError: String?

    // MARK: Dependencies

    private let configuration: PaywallConfiguration
    private let trial: LorisTrialService?
    private let keychain: LorisKeychain
    private var updatesTask: Task<Void, Never>?

    /// False once a store call fails, so a missing entitlement is read as
    /// "unreachable" rather than "cancelled".
    private var isStoreReachable = true

    private static let cachedEntitlementKey = "loris.paywall.cached.paid"
    private static let lastVerifiedKey = "loris.paywall.lastVerified"

    // MARK: Lifecycle

    public init(configuration: PaywallConfiguration) {
        self.configuration = configuration
        self.keychain = LorisKeychain(service: configuration.keychainService)
        self.trial = configuration.trialDuration.map {
            LorisTrialService(duration: $0, keychainService: configuration.keychainService)
        }
    }

    /// Starts listening for transactions, loads products and computes the
    /// current entitlement. Call once, early in the app's lifetime; calling it
    /// again replaces the listener rather than stacking a second one.
    ///
    /// There is deliberately no `deinit` cleanup: a `deinit` is nonisolated and
    /// cannot touch main-actor state under Swift 6. Call `stop()` if the store
    /// is ever torn down before the app exits.
    public func start() async {
        updatesTask?.cancel()
        updatesTask = listenForTransactions()
        await loadProducts()
        await refreshEntitlements()
    }

    public func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    // MARK: Products

    public func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let loaded = try await Product.products(for: configuration.productIDs)
            products = loaded.sorted { $0.price < $1.price }
            didLoadProducts = true
            isStoreReachable = true
        } catch {
            isStoreReachable = false
            lastError = error.localizedDescription
        }
    }

    /// Products rendered as paywall tiers, cheapest first.
    public var tiers: [PaywallTier] {
        products.map { PaywallTier(product: $0) }
    }

    // MARK: Trial

    /// True once the trial has ever been started on this device, running or not.
    public var hasStartedTrial: Bool { trial?.hasStarted ?? false }

    /// True while the trial is running.
    public var isTrialActive: Bool { trial?.isActive() ?? false }

    /// True only after a trial that was started has run out.
    public var hasTrialExpired: Bool { trial?.hasExpired() ?? false }

    /// Whole days left in the trial, 0 when it never started or has ended.
    public var trialDaysRemaining: Int { trial?.daysRemaining() ?? 0 }

    /// Grants the trial the first time it is called on this device.
    ///
    /// Synchronous on purpose: callers routinely read `entitlement` on the very
    /// next line, so the trial must be visible immediately rather than after an
    /// await. The full entitlement refresh still runs in the background.
    @discardableResult
    public func startTrialIfNeeded() -> Bool {
        guard let trial, !trial.hasStarted else { return false }
        let started = trial.startIfNeeded()
        if started, !entitlement.isPaid {
            entitlement = trialState()
        }
        Task { await refreshEntitlements() }
        return started
    }

    // MARK: Purchase

    /// Returns true when the purchase completed and the entitlement is live.
    @discardableResult
    public func purchase(_ product: Product) async -> Bool {
        lastError = nil
        do {
            let result: Product.PurchaseResult
            #if os(tvOS) || os(visionOS)
            // These platforms reject the plain purchase() call — it must be
            // confirmed in a window scene, or the sheet never appears.
            guard let scene = Self.activeWindowScene() else {
                lastError = "No active window scene to present the purchase."
                return false
            }
            result = try await product.purchase(confirmIn: scene)
            #else
            result = try await product.purchase()
            #endif

            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return true
            case .userCancelled:
                return false
            case .pending:
                // Ask-to-buy and SCA land here; `Transaction.updates` will fire.
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// True while a restore is in flight, so the button can show progress.
    ///
    /// Without it a restore reads as a dead button: Lumen's swallowed every
    /// failure into a log line and a paying subscriber reported it as "nothing
    /// happens" (Ghislain, 2026-07-25).
    public private(set) var isRestoring = false

    /// True when the last restore completed without error but found no
    /// entitlement for this Apple ID — a distinct outcome from a failure, and
    /// one a silent restore reports identically to success.
    public private(set) var restoreFoundNothing = false

    public func restorePurchases() async {
        lastError = nil
        restoreFoundNothing = false
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            isStoreReachable = true
            await refreshEntitlements()
            restoreFoundNothing = purchasedProductIDs.isEmpty
        } catch {
            isStoreReachable = false
            lastError = error.localizedDescription
        }
    }

    #if os(iOS)
    /// Presents Apple's offer-code sheet. Only two apps in the portfolio ever
    /// wired this up, so promo campaigns had nowhere to land.
    public func redeemOfferCode(in scene: UIWindowScene) {
        Task { @MainActor in
            do {
                try await AppStore.presentOfferCodeRedeemSheet(in: scene)
                await refreshEntitlements()
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
    #endif

    // MARK: Entitlements

    public func refreshEntitlements() async {
        var isLifetime = false
        var subscriptionExpiry: Date?
        var foundPaid = false
        var owned: Set<String> = []

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? Self.checkVerified(result) else { continue }
            guard transaction.revocationDate == nil else { continue }

            owned.insert(transaction.productID)

            if configuration.lifetimeProductIDs.contains(transaction.productID) {
                isLifetime = true
                foundPaid = true
            } else if let expiry = transaction.expirationDate {
                if expiry > Date() {
                    foundPaid = true
                    subscriptionExpiry = max(subscriptionExpiry ?? expiry, expiry)
                }
            } else {
                // Non-consumable not declared as lifetime — still a purchase.
                isLifetime = true
                foundPaid = true
            }
        }

        subscriptionExpiration = subscriptionExpiry
        purchasedProductIDs = owned

        if foundPaid {
            cachePaidEntitlement(true)
            entitlement = isLifetime ? .lifetime : .subscribed(expiration: subscriptionExpiry)
        } else if !isStoreReachable, cachedPaidEntitlementIsFresh() {
            // Offline and previously paid — keep access rather than locking the
            // user out of an app they bought.
            entitlement = .subscribed(expiration: subscriptionExpiry)
        } else {
            cachePaidEntitlement(false)
            entitlement = trialState()
        }

        // Set last so an observer reacting to the flag also sees fresh state.
        entitlementsLoaded = true

        await refreshRenewalStatus()
    }

    /// Adopts a trial previously stored in `UserDefaults` by an older build.
    /// Call before `start()`. No-op when the keychain already holds a trial.
    @discardableResult
    public func migrateLegacyTrial(fromUserDefaultsKey key: String) -> Bool {
        trial?.migrateLegacyStart(fromUserDefaultsKey: key) ?? false
    }

    private func trialState() -> EntitlementState {
        guard let trial, trial.isActive() else { return .none }
        return .trial(daysRemaining: trial.daysRemaining())
    }

    // MARK: Renewal monitoring

    /// Reads the subscription group status so the app can tell an active
    /// subscription from one silently failing to renew.
    public func refreshRenewalStatus() async {
        guard let subscription = subscriptionForMonitoring() else {
            renewalStatus = .notSubscribed
            return
        }

        do {
            let statuses = try await subscription.status
            guard let status = statuses.first else {
                renewalStatus = .notSubscribed
                return
            }

            let renewalInfo = try? Self.checkVerified(status.renewalInfo)
            let transaction = try? Self.checkVerified(status.transaction)
            let expiration = transaction?.expirationDate

            switch status.state {
            case .subscribed:
                if let renewalInfo, renewalInfo.willAutoRenew == false, let expiration {
                    renewalStatus = .expiringSoon(expiration: expiration)
                } else {
                    renewalStatus = .active(expiration: expiration)
                }
            case .inGracePeriod:
                renewalStatus = .inGracePeriod(until: renewalInfo?.gracePeriodExpirationDate)
            case .inBillingRetryPeriod:
                renewalStatus = .inBillingRetry
            case .revoked:
                renewalStatus = .revoked
            case .expired:
                renewalStatus = .expired
            default:
                renewalStatus = .notSubscribed
            }
        } catch {
            isStoreReachable = false
            renewalStatus = .notSubscribed
        }
    }

    private func subscriptionForMonitoring() -> Product.SubscriptionInfo? {
        if let groupID = configuration.subscriptionGroupID {
            return products.first { $0.subscription?.subscriptionGroupID == groupID }?.subscription
        }
        return products.first { $0.subscription != nil }?.subscription
    }

    // MARK: Offline tolerance

    private func cachePaidEntitlement(_ isPaid: Bool) {
        try? keychain.save(isPaid ? "1" : "0", forKey: Self.cachedEntitlementKey)
        try? keychain.save(String(Date().timeIntervalSince1970), forKey: Self.lastVerifiedKey)
    }

    private func cachedPaidEntitlementIsFresh() -> Bool {
        guard let cached = try? keychain.string(forKey: Self.cachedEntitlementKey), cached == "1",
              let raw = try? keychain.string(forKey: Self.lastVerifiedKey),
              let seconds = TimeInterval(raw) else { return false }
        let lastVerified = Date(timeIntervalSince1970: seconds)
        return Date().timeIntervalSince(lastVerified) < configuration.offlineTolerance
    }

    // MARK: Scene resolution

    #if canImport(UIKit) && !os(watchOS)
    /// The scene a purchase sheet should be confirmed in: the foreground-active
    /// one, falling back to any connected scene.
    @MainActor
    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }
    #endif

    // MARK: Verification

    private nonisolated static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let safe): return safe
        }
    }

    // MARK: Transaction listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? Self.checkVerified(result) else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }
}

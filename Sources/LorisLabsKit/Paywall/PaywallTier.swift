import Foundation
import StoreKit

/// One tier (Monthly / Annual / Lifetime) shown on a paywall.
public struct PaywallTier: Identifiable, Sendable {
    public let id: String  // typically the StoreKit Product.id
    public let displayName: String
    public let priceText: String
    public let trailingNote: String?
    public let billingCadence: BillingCadence
    public let isPopular: Bool
    public let saveBadge: String?

    public enum BillingCadence: String, Sendable {
        case monthly
        case annual
        case lifetime
    }

    public init(
        id: String,
        displayName: String,
        priceText: String,
        trailingNote: String? = nil,
        billingCadence: BillingCadence,
        isPopular: Bool = false,
        saveBadge: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.priceText = priceText
        self.trailingNote = trailingNote
        self.billingCadence = billingCadence
        self.isPopular = isPopular
        self.saveBadge = saveBadge
    }
}

public extension PaywallTier {
    /// Build from a StoreKit `Product`. The display name and badges are derived
    /// from the cadence; override with the explicit init if you need custom copy.
    init(product: Product, isPopular: Bool = false, saveBadge: String? = nil) {
        let cadence: BillingCadence
        let displayName: String
        let trailingNote: String?

        switch product.type {
        case .nonConsumable:
            cadence = .lifetime
            displayName = product.displayName.isEmpty ? "Lifetime" : product.displayName
            trailingNote = "One-time purchase"
        case .autoRenewable:
            if let period = product.subscription?.subscriptionPeriod {
                switch period.unit {
                case .year:
                    cadence = .annual
                    displayName = product.displayName.isEmpty ? "Annual" : product.displayName
                case .month:
                    cadence = .monthly
                    displayName = product.displayName.isEmpty ? "Monthly" : product.displayName
                default:
                    cadence = .monthly
                    displayName = product.displayName
                }
                trailingNote = nil
            } else {
                cadence = .monthly
                displayName = product.displayName
                trailingNote = nil
            }
        default:
            cadence = .lifetime
            displayName = product.displayName
            trailingNote = nil
        }

        self.init(
            id: product.id,
            displayName: displayName,
            priceText: product.displayPrice,
            trailingNote: trailingNote,
            billingCadence: cadence,
            isPopular: isPopular,
            saveBadge: saveBadge
        )
    }
}

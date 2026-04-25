import Testing
@testable import LorisLabsKit

struct PaywallTierTests {
    @Test func explicitInitPreservesAllFields() {
        let tier = PaywallTier(
            id: "annual",
            displayName: "Annual",
            priceText: "$19.99",
            trailingNote: "7-day trial",
            billingCadence: .annual,
            isPopular: true,
            saveBadge: "Save 44%"
        )
        #expect(tier.id == "annual")
        #expect(tier.displayName == "Annual")
        #expect(tier.priceText == "$19.99")
        #expect(tier.trailingNote == "7-day trial")
        #expect(tier.billingCadence == .annual)
        #expect(tier.isPopular)
        #expect(tier.saveBadge == "Save 44%")
    }
}

import SwiftUI

/// A reusable paywall view for LorisLabs apps.
///
/// Drop-in usage:
/// ```swift
/// LorisLabsPaywallView(
///     headline: "Unlock Lumen Pro",
///     subhead: "Unlimited cameras, AI features, all platforms.",
///     features: ["Unlimited cameras", "Face recognition", "License plate", "Apple Watch + TV + Vision Pro"],
///     tiers: [monthly, annual, lifetime],
///     onPurchase: { tier in await myStoreManager.purchase(tier.id) },
///     onRestore: { await myStoreManager.restore() },
///     onCancel: { dismiss() }
/// )
/// ```
///
/// The view is intentionally view-model agnostic — your app passes ready-made
/// `PaywallTier` values (built from StoreKit `Product`s or hand-rolled) and
/// receives callbacks for purchase/restore/cancel. State management of
/// loading / purchasing / errors is the host's responsibility.
public struct LorisLabsPaywallView: View {

    private let headline: String
    private let subhead: String
    private let features: [String]
    private let tiers: [PaywallTier]
    private let style: PaywallStyle
    private let onPurchase: (PaywallTier) async -> Void
    private let onRestore: () async -> Void
    private let onCancel: () -> Void

    @State private var selectedTierID: String?
    @State private var isPurchasing: Bool = false

    public init(
        headline: String,
        subhead: String,
        features: [String],
        tiers: [PaywallTier],
        style: PaywallStyle = .default,
        onPurchase: @escaping (PaywallTier) async -> Void,
        onRestore: @escaping () async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.headline = headline
        self.subhead = subhead
        self.features = features
        self.tiers = tiers
        self.style = style
        self.onPurchase = onPurchase
        self.onRestore = onRestore
        self.onCancel = onCancel
        self._selectedTierID = State(initialValue: tiers.first(where: \.isPopular)?.id ?? tiers.first?.id)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                featuresSection
                tiersSection
                purchaseButton
                restoreAndCancel
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(style.backgroundColor.ignoresSafeArea())
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 8) {
            Text(headline)
                .font(.largeTitle).bold()
                .multilineTextAlignment(.center)
            Text(subhead)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(features, id: \.self) { feature in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(style.accentColor)
                    Text(feature)
                        .font(.callout)
                    Spacer()
                }
            }
        }
        .padding(16)
        .background(style.cardBackgroundColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var tiersSection: some View {
        VStack(spacing: 10) {
            ForEach(tiers) { tier in
                tierCard(tier)
            }
        }
    }

    private func tierCard(_ tier: PaywallTier) -> some View {
        let isSelected = selectedTierID == tier.id
        return Button {
            selectedTierID = tier.id
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(tier.displayName)
                            .font(.headline)
                        if tier.isPopular {
                            Text(style.popularBadgeText)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(style.accentColor, in: Capsule())
                        }
                        if let badge = tier.saveBadge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(style.accentColor)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(style.accentColor.opacity(0.15), in: Capsule())
                        }
                    }
                    if let trailing = tier.trailingNote {
                        Text(trailing)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(tier.priceText)
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(style.cardBackgroundColor)
                    .stroke(isSelected ? style.accentColor : .clear, lineWidth: 2)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var purchaseButton: some View {
        Button {
            guard let tier = tiers.first(where: { $0.id == selectedTierID }) else { return }
            Task {
                isPurchasing = true
                await onPurchase(tier)
                isPurchasing = false
            }
        } label: {
            HStack {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(style.purchaseButtonText)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(style.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isPurchasing || selectedTierID == nil)
    }

    private var restoreAndCancel: some View {
        VStack(spacing: 8) {
            Button {
                Task { await onRestore() }
            } label: {
                Text(style.restoreButtonText)
                    .font(.callout)
                    .foregroundStyle(style.accentColor)
            }
            .buttonStyle(.plain)

            Button {
                onCancel()
            } label: {
                Text(style.cancelButtonText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }
}

#Preview {
    LorisLabsPaywallView(
        headline: "Unlock Lumen Pro",
        subhead: "Unlimited cameras, AI features, all platforms.",
        features: [
            "Unlimited cameras",
            "Face recognition + license plate",
            "Semantic event search",
            "Apple Watch, TV, Vision Pro support",
        ],
        tiers: [
            PaywallTier(id: "monthly", displayName: "Monthly", priceText: "$2.99 / mo", billingCadence: .monthly),
            PaywallTier(id: "annual", displayName: "Annual", priceText: "$19.99 / yr", trailingNote: "7-day free trial · less than $2/mo", billingCadence: .annual, isPopular: true, saveBadge: "Save 44%"),
            PaywallTier(id: "lifetime", displayName: "Lifetime", priceText: "$49.99", trailingNote: "One-time purchase", billingCadence: .lifetime),
        ],
        onPurchase: { _ in },
        onRestore: {},
        onCancel: {}
    )
}

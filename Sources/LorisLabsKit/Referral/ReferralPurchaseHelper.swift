import Foundation
import StoreKit

@MainActor
public enum ReferralPurchaseHelper {
    public enum HelperError: Error, Sendable {
        case invalidNonce
        case userCancelled
        case pending
        case unknownPurchaseResult
        case unsupportedPlatform
    }

    /// Call this when you have a `claimNonce` from `ReferralClient.lookup(...)`
    /// and a `Product` to buy. Returns the `Transaction` after verification, or
    /// throws on cancel / pending.
    ///
    /// `Product.purchase(options:)` is iOS / macOS / tvOS / watchOS only —
    /// visionOS uses a different StoreKit purchase entry point and is not
    /// supported by ReferralKit V1. Calls from visionOS throw
    /// `HelperError.unsupportedPlatform`.
    public static func purchase(
        product: Product,
        claimNonce: String
    ) async throws -> StoreKit.Transaction {
        #if os(visionOS)
        throw HelperError.unsupportedPlatform
        #else
        guard let token = UUID(uuidString: claimNonce) else {
            throw HelperError.invalidNonce
        }
        let options: Set<Product.PurchaseOption> = [.appAccountToken(token)]
        let result = try await product.purchase(options: options)
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let txn):
                await txn.finish()
                return txn
            case .unverified(_, let err):
                throw err
            }
        case .userCancelled:
            throw HelperError.userCancelled
        case .pending:
            throw HelperError.pending
        @unknown default:
            throw HelperError.unknownPurchaseResult
        }
        #endif
    }
}

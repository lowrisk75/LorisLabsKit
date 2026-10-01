import SwiftUI
import StoreKit

/// Convenience modifier that asks `SmartReviewPromptManager` to prompt if criteria are met,
/// when the modified view appears. Intended to be attached to "moment of success" views.
///
/// Example:
/// ```swift
/// EventDetailView(event: event)
///     .reviewPromptOnAppear(reviewManager)
/// ```
public struct ReviewPromptOnAppearModifier: ViewModifier {
    private let manager: SmartReviewPromptManager
    // `requestReview` (RequestReviewAction) is unavailable on tvOS.
    #if !os(tvOS) && !os(watchOS)
    @Environment(\.requestReview) private var requestReview
    #endif

    public init(manager: SmartReviewPromptManager) {
        self.manager = manager
    }

    public func body(content: Content) -> some View {
        #if os(tvOS) || os(watchOS)
        content // No App Store review prompt on tvOS — no-op.
        #else
        content.task {
            // 0.5s delay so the success view actually renders before the prompt appears.
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled else { return }
            manager.requestIfAppropriate(via: requestReview)
        }
        #endif
    }
}

public extension View {
    /// Asks `SmartReviewPromptManager` to prompt if criteria are met, on appear.
    /// Should ONLY be attached to views that represent a moment of success
    /// (an action the user just completed successfully).
    func reviewPromptOnAppear(_ manager: SmartReviewPromptManager) -> some View {
        modifier(ReviewPromptOnAppearModifier(manager: manager))
    }
}

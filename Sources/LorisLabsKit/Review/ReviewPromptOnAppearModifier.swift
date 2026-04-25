import SwiftUI

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
    @Environment(\.requestReview) private var requestReview

    public init(manager: SmartReviewPromptManager) {
        self.manager = manager
    }

    public func body(content: Content) -> some View {
        content.task {
            // 0.5s delay so the success view actually renders before the prompt appears.
            try? await Task.sleep(for: .milliseconds(500))
            manager.requestIfAppropriate(via: requestReview)
        }
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
